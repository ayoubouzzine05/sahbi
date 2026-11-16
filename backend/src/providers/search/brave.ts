import { expectOk, fetchWithRetry, type FetchLike } from '../../http.js';
import type { SearchProvider, SearchResult } from './types.js';

/** Brave Search Web API: GET https://api.search.brave.com/res/v1/web/search (X-Subscription-Token). */
export class BraveSearchProvider implements SearchProvider {
  readonly name = 'brave';
  constructor(
    private readonly apiKey: string,
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async search(query: string, opts: { freshness?: 'pd' | 'pw' | 'pm' | 'py'; country?: string; lang?: string } = {}): Promise<SearchResult[]> {
    const params = new URLSearchParams({ q: query, count: '6', extra_snippets: 'true', safesearch: 'moderate' });
    if (opts.freshness) params.set('freshness', opts.freshness);
    if (opts.country) params.set('country', opts.country);
    if (opts.lang) params.set('search_lang', opts.lang);
    const res = await fetchWithRetry(this.fetchImpl, `https://api.search.brave.com/res/v1/web/search?${params}`, {
      headers: { accept: 'application/json', 'X-Subscription-Token': this.apiKey },
    });
    await expectOk(res, 'Search');
    const json = (await res.json()) as {
      web?: { results?: Array<{ title?: string; url?: string; description?: string; extra_snippets?: string[]; page_age?: string; age?: string }> };
    };
    return (json.web?.results ?? [])
      .filter((r) => r.url && r.title)
      .map((r) => ({
        title: stripTags(r.title!),
        url: r.url!,
        snippet: stripTags([r.description ?? '', ...(r.extra_snippets ?? []).slice(0, 2)].join(' … ')).slice(0, 700),
        ...(r.page_age || r.age ? { date: r.page_age ?? r.age } : {}),
      }));
  }
}

export function stripTags(s: string): string {
  return s.replace(/<[^>]+>/g, '').replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&#x27;|&#39;/g, "'").trim();
}
