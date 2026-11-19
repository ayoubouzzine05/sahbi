import type { FetchLike } from '../../http.js';
import type { SearchProvider, SearchResult } from './types.js';

const UA = 'SAHBI/0.1 (https://github.com/ayoubouzzine05/sahbi; open-source companion app)';

/**
 * Free web search without any key or card:
 * - Wikipedia (MediaWiki Action API, generator=search + intro extracts) in the
 *   query's languages, for "what/who is …" questions.
 * - GDELT DOC 2.0 API (open news index) for recent news, best effort: it allows
 *   about one request per 5 s per IP and answers with plain text when limited,
 *   which is then skipped.
 * Google Search grounding would be better but is not free for new Gemini
 * accounts (2.5 models: 404 "no longer available to new users"; 3.x: 429 quota,
 * both seen 2026-11-19), and Google News RSS forbids use outside personal feed
 * readers, so neither is used here.
 */
export class FreeWebSearchProvider implements SearchProvider {
  readonly name = 'wikipedia+gdelt';
  constructor(
    private readonly fetchImpl: FetchLike = fetch,
    private readonly timeoutMs = 8000,
  ) {}

  async search(query: string, opts: { freshness?: 'pd' | 'pw' | 'pm' | 'py'; country?: string; lang?: string } = {}): Promise<SearchResult[]> {
    const arabic = /[\u0600-\u06FF]/.test(query);
    const langs = arabic ? ['ar', 'fr'] : ['fr', 'en'];
    const fresh = opts.freshness === 'pd' || opts.freshness === 'pw' || opts.freshness === 'pm' ? opts.freshness : null;
    const [w1, w2, news] = await Promise.all([
      this.wikipedia(langs[0]!, query),
      this.wikipedia(langs[1]!, query),
      fresh ? this.gdelt(query, fresh) : Promise.resolve([]),
    ]);
    // News first when asked for fresh facts; then interleave the two wikis.
    const wiki: SearchResult[] = [];
    for (let i = 0; i < Math.max(w1.length, w2.length); i++) {
      if (w1[i]) wiki.push(w1[i]!);
      if (w2[i]) wiki.push(w2[i]!);
    }
    return [...news, ...wiki].slice(0, 6);
  }

  private async get(url: string): Promise<Response | null> {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), this.timeoutMs);
    try {
      return await this.fetchImpl(url, { headers: { 'user-agent': UA, accept: 'application/json' }, signal: ctrl.signal });
    } catch {
      return null;
    } finally {
      clearTimeout(t);
    }
  }

  async wikipedia(lang: string, query: string): Promise<SearchResult[]> {
    const params = new URLSearchParams({
      action: 'query',
      format: 'json',
      formatversion: '2',
      utf8: '1',
      generator: 'search',
      gsrsearch: query,
      gsrlimit: '3',
      prop: 'extracts|info|revisions',
      exintro: '1',
      explaintext: '1',
      exchars: '700',
      inprop: 'url',
      rvprop: 'timestamp',
    });
    const res = await this.get(`https://${lang}.wikipedia.org/w/api.php?${params}`);
    if (!res?.ok) return [];
    try {
      const j = (await res.json()) as {
        query?: { pages?: Array<{ title?: string; extract?: string; fullurl?: string; index?: number; revisions?: Array<{ timestamp?: string }> }> };
      };
      return (j.query?.pages ?? [])
        .filter((p) => p.title && p.fullurl && p.extract)
        .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
        .map((p) => ({
          title: `${p.title} — Wikipedia (${lang})`,
          url: p.fullurl!,
          snippet: p.extract!.replace(/\s+/g, ' ').slice(0, 700),
          ...(p.revisions?.[0]?.timestamp ? { date: `edited ${p.revisions[0].timestamp.slice(0, 10)}` } : {}),
        }));
    } catch {
      return [];
    }
  }

  async gdelt(query: string, freshness: 'pd' | 'pw' | 'pm'): Promise<SearchResult[]> {
    const timespan = { pd: '1d', pw: '7d', pm: '1m' }[freshness];
    const q = query.replace(/["()]/g, ' ').trim();
    const params = new URLSearchParams({ query: q, mode: 'artlist', maxrecords: '6', format: 'json', sort: 'datedesc', timespan });
    const res = await this.get(`https://api.gdeltproject.org/api/v2/doc/doc?${params}`);
    if (!res?.ok) return [];
    const text = await res.text().catch(() => '');
    if (!text.startsWith('{')) return []; // rate-limit / error notice in plain text
    try {
      const j = JSON.parse(text) as { articles?: Array<{ title?: string; url?: string; domain?: string; seendate?: string; language?: string }> };
      return (j.articles ?? [])
        .filter((a) => a.title && a.url)
        .slice(0, 4)
        .map((a) => ({
          title: `${a.title} — ${a.domain ?? ''}`.trim(),
          url: a.url!,
          // GDELT gives headlines only: the model must not claim more than the title says.
          snippet: `Headline only (no article text): ${a.title}`,
          ...(a.seendate ? { date: gdeltDate(a.seendate) } : {}),
        }));
    } catch {
      return [];
    }
  }
}

/** "20261118T101500Z" → "2026-11-18". */
function gdeltDate(s: string): string {
  const m = /^(\d{4})(\d{2})(\d{2})/.exec(s);
  return m ? `${m[1]}-${m[2]}-${m[3]}` : s;
}
