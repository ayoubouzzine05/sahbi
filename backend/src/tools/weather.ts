import { expectOk, fetchWithRetry, type FetchLike } from '../http.js';
import { ServiceError } from '../errors.js';

export interface WeatherReport {
  location: { name: string; country?: string; latitude: number; longitude: number };
  current: { temperature_c: number; apparent_c?: number; wind_kmh?: number; humidity?: number; weather_code: number; description_en: string; is_day?: boolean };
  today?: { max_c?: number; min_c?: number; precipitation_probability?: number };
  source: { title: string; url: string };
}

/** WMO weather interpretation codes, as documented by Open-Meteo. */
export const WMO: Record<number, string> = {
  0: 'clear sky', 1: 'mainly clear', 2: 'partly cloudy', 3: 'overcast', 45: 'fog', 48: 'depositing rime fog',
  51: 'light drizzle', 53: 'moderate drizzle', 55: 'dense drizzle', 56: 'light freezing drizzle', 57: 'dense freezing drizzle',
  61: 'slight rain', 63: 'moderate rain', 65: 'heavy rain', 66: 'light freezing rain', 67: 'heavy freezing rain',
  71: 'slight snow', 73: 'moderate snow', 75: 'heavy snow', 77: 'snow grains', 80: 'slight rain showers', 81: 'moderate rain showers',
  82: 'violent rain showers', 85: 'slight snow showers', 86: 'heavy snow showers', 95: 'thunderstorm', 96: 'thunderstorm with slight hail', 99: 'thunderstorm with heavy hail',
};

/** Common Darija / French spellings → name the geocoder understands. */
const CITY_ALIASES: Record<string, string> = {
  tanja: 'Tangier', tanger: 'Tangier', 'طنجة': 'Tangier', casa: 'Casablanca', 'dar lbida': 'Casablanca', 'الدار البيضاء': 'Casablanca', kaza: 'Casablanca',
  rbat: 'Rabat', 'الرباط': 'Rabat', fas: 'Fes', fès: 'Fes', 'فاس': 'Fes', mrakch: 'Marrakesh', marrakech: 'Marrakesh', 'مراكش': 'Marrakesh',
  agadir: 'Agadir', 'أكادير': 'Agadir', meknes: 'Meknes', 'مكناس': 'Meknes', oujda: 'Oujda', 'وجدة': 'Oujda', tetouan: 'Tetouan', 'تطوان': 'Tetouan',
};

export function normaliseCity(city: string): string {
  const k = city.trim().toLowerCase();
  return CITY_ALIASES[k] ?? city.trim();
}

/** Open-Meteo geocoding + forecast (no API key). https://open-meteo.com/en/docs */
export async function getWeather(city: string, fetchImpl: FetchLike = fetch): Promise<WeatherReport> {
  const name = normaliseCity(city);
  if (!name) throw new ServiceError('bad_request', 'city is required', 400);
  const geoRes = await fetchWithRetry(fetchImpl, `https://geocoding-api.open-meteo.com/v1/search?${new URLSearchParams({ name, count: '1', language: 'en', format: 'json' })}`, {});
  await expectOk(geoRes, 'Geocoding');
  const geo = (await geoRes.json()) as { results?: Array<{ name: string; country?: string; latitude: number; longitude: number }> };
  const place = geo.results?.[0];
  if (!place) throw new ServiceError('bad_request', `Unknown place: ${name}`, 404);
  const params = new URLSearchParams({
    latitude: String(place.latitude),
    longitude: String(place.longitude),
    current: 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day',
    daily: 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
    timezone: 'auto',
    forecast_days: '1',
  });
  const url = `https://api.open-meteo.com/v1/forecast?${params}`;
  const wRes = await fetchWithRetry(fetchImpl, url, {});
  await expectOk(wRes, 'Weather');
  const w = (await wRes.json()) as {
    current?: { temperature_2m: number; apparent_temperature?: number; relative_humidity_2m?: number; weather_code: number; wind_speed_10m?: number; is_day?: number };
    daily?: { temperature_2m_max?: number[]; temperature_2m_min?: number[]; precipitation_probability_max?: number[] };
  };
  if (!w.current) throw new ServiceError('upstream_error', 'Weather response missing current data');
  return {
    location: { name: place.name, country: place.country, latitude: place.latitude, longitude: place.longitude },
    current: {
      temperature_c: w.current.temperature_2m,
      apparent_c: w.current.apparent_temperature,
      humidity: w.current.relative_humidity_2m,
      wind_kmh: w.current.wind_speed_10m,
      weather_code: w.current.weather_code,
      description_en: WMO[w.current.weather_code] ?? 'unknown',
      is_day: w.current.is_day === undefined ? undefined : w.current.is_day === 1,
    },
    today: {
      max_c: w.daily?.temperature_2m_max?.[0],
      min_c: w.daily?.temperature_2m_min?.[0],
      precipitation_probability: w.daily?.precipitation_probability_max?.[0],
    },
    source: { title: `Open-Meteo forecast — ${place.name}`, url: `https://open-meteo.com/en/docs#latitude=${place.latitude}&longitude=${place.longitude}` },
  };
}
