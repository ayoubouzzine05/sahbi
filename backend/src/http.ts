import { ServiceError } from './errors.js';

export type FetchLike = typeof fetch;

export interface RetryOptions {
  retries?: number;
  timeoutMs?: number;
  baseDelayMs?: number;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * fetch with timeout + exponential backoff on network errors, 429 and 5xx.
 * Never logs request or response bodies.
 */
export async function fetchWithRetry(
  fetchImpl: FetchLike,
  url: string,
  init: RequestInit,
  { retries = 2, timeoutMs = 15000, baseDelayMs = 400 }: RetryOptions = {},
): Promise<Response> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, { ...init, signal: ctrl.signal });
      clearTimeout(timer);
      if ((res.status === 429 || res.status >= 500) && attempt < retries) {
        await sleep(baseDelayMs * 2 ** attempt);
        continue;
      }
      return res;
    } catch (err) {
      clearTimeout(timer);
      lastError = err;
      if (attempt < retries) {
        await sleep(baseDelayMs * 2 ** attempt);
        continue;
      }
    }
  }
  const aborted = lastError instanceof Error && lastError.name === 'AbortError';
  throw new ServiceError(aborted ? 'upstream_timeout' : 'upstream_error', aborted ? 'Upstream timed out' : 'Upstream unreachable', aborted ? 504 : 502);
}

export async function expectOk(res: Response, what: string): Promise<Response> {
  if (!res.ok) {
    // Body is intentionally not included: it may echo user content.
    throw new ServiceError('upstream_error', `${what} returned HTTP ${res.status}`, 502);
  }
  return res;
}
