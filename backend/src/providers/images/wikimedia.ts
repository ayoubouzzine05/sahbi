import type { FetchLike } from '../../http.js';

export interface ImageResult {
  /** Thumbnail URL (upload.wikimedia.org), about 800 px wide. */
  url: string;
  title: string;
  /** Page with the image, its author and licence. */
  page: string;
  source: 'Wikipedia' | 'Wikimedia Commons';
  width?: number;
  height?: number;
}

const UA = 'SAHBI/0.1 (companion robot app; https://github.com/ayoubouzzine05/sahbi)';

/**
 * Free photos for "show me …" without any key: the lead image of the best
 * matching Wikipedia articles (en, fr, ar), then a Wikimedia Commons file
 * search. Every result links to its page so the author and licence stay one
 * tap away. Only bitmap photos (jpg/png/webp) are returned.
 */
export class WikimediaImages {
  constructor(
    private readonly fetchImpl: FetchLike = fetch,
    private readonly timeoutMs = 8000,
  ) {}

  async search(query: string, max = 4): Promise<ImageResult[]> {
    const arabic = /[\u0600-\u06FF]/.test(query);
    const langs = arabic ? ['ar', 'en'] : ['en', 'fr'];
    const lists = await Promise.all([...langs.map((l) => this.wikipedia(l, query).catch(() => [])), this.commons(query).catch(() => [])]);
    const wiki = lists.slice(0, langs.length);
    const commons = lists[langs.length] ?? [];
    // Most relevant first: the top article of each Wikipedia, then Commons
    // files matching the query, then the other articles' images.
    const ordered = [...wiki.map((l) => l.slice(0, 1)).flat(), ...commons, ...wiki.map((l) => l.slice(1)).flat()];
    const out: ImageResult[] = [];
    const seen = new Set<string>();
    for (const r of ordered) {
      const key = r.url.replace(/[?#].*$/, '').replace(/\/\d+px-[^/]+$/, '');
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(r);
      if (out.length >= max) break;
    }
    return out;
  }

  private async get(url: string): Promise<unknown> {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), this.timeoutMs);
    try {
      const res = await this.fetchImpl(url, { headers: { 'user-agent': UA, 'api-user-agent': UA, accept: 'application/json' }, signal: ctrl.signal });
      if (!res.ok) return null;
      return await res.json();
    } finally {
      clearTimeout(t);
    }
  }

  async wikipedia(lang: string, query: string): Promise<ImageResult[]> {
    const p = new URLSearchParams({
      action: 'query',
      format: 'json',
      formatversion: '2',
      generator: 'search',
      gsrsearch: query,
      gsrlimit: '4',
      prop: 'pageimages|info',
      piprop: 'thumbnail',
      pithumbsize: '800',
      // Free licences only (no fair-use posters or logos).
      pilicense: 'free',
      inprop: 'url',
      origin: '*',
    });
    const j = (await this.get(`https://${lang}.wikipedia.org/w/api.php?${p}`)) as {
      query?: { pages?: Array<{ index?: number; title?: string; fullurl?: string; thumbnail?: { source?: string; width?: number; height?: number } }> };
    } | null;
    return (j?.query?.pages ?? [])
      .slice()
      .sort((a, b) => (a.index ?? 99) - (b.index ?? 99))
      .filter((pg) => pg.thumbnail?.source && isPhoto(pg.thumbnail.source))
      .map((pg) => ({
        url: pg.thumbnail!.source!,
        title: pg.title ?? query,
        page: pg.fullurl ?? `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(pg.title ?? query)}`,
        source: 'Wikipedia' as const,
        width: pg.thumbnail!.width,
        height: pg.thumbnail!.height,
      }));
  }

  async commons(query: string): Promise<ImageResult[]> {
    const p = new URLSearchParams({
      action: 'query',
      format: 'json',
      formatversion: '2',
      generator: 'search',
      gsrsearch: `${query} filetype:bitmap`,
      gsrnamespace: '6',
      gsrlimit: '6',
      prop: 'imageinfo',
      iiprop: 'url|mime',
      iiurlwidth: '800',
      origin: '*',
    });
    const j = (await this.get(`https://commons.wikimedia.org/w/api.php?${p}`)) as {
      query?: { pages?: Array<{ index?: number; title?: string; imageinfo?: Array<{ thumburl?: string; thumbwidth?: number; thumbheight?: number; descriptionurl?: string; mime?: string }> }> };
    } | null;
    return (j?.query?.pages ?? [])
      .slice()
      .sort((a, b) => (a.index ?? 99) - (b.index ?? 99))
      .map((pg) => ({ pg, ii: pg.imageinfo?.[0] }))
      .filter(({ ii }) => ii?.thumburl && /^image\/(jpeg|png|webp)$/.test(ii.mime ?? '') && isPhoto(ii.thumburl))
      .map(({ pg, ii }) => ({
        url: ii!.thumburl!,
        title: (pg.title ?? query).replace(/^File:/, '').replace(/\.[a-z]+$/i, ''),
        page: ii!.descriptionurl ?? 'https://commons.wikimedia.org/',
        source: 'Wikimedia Commons' as const,
        width: ii!.thumbwidth,
        height: ii!.thumbheight,
      }));
  }
}

/** Bitmap thumbnails on Wikimedia's image servers (an SVG rendered as .svg.png, e.g. a flag, is fine). */
export function isPhoto(url: string): boolean {
  try {
    const u = new URL(url);
    return u.protocol === 'https:' && /^(upload|thumb)\.wikimedia\.org$/.test(u.hostname) && /\.(jpe?g|png|webp)$/i.test(u.pathname);
  } catch {
    return false;
  }
}
