import { ServiceError } from '../../errors.js';
import { expectGoogleOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { generateContentUrl } from '../llm/gemini.js';
import type { SearchProvider, SearchResult } from './types.js';

/**
 * Web search through Gemini "Grounding with Google Search"
 * (https://ai.google.dev/gemini-api/docs/google-search): `tools: [{google_search: {}}]`
 * on generateContent. Per the pricing page (checked 2026-11-19) grounding is
 * free (up to 500 requests/day, shared) on gemini-2.5-flash / 2.5-flash-lite in
 * the free tier, and NOT available in the free tier for Gemini 3+ models,
 * hence the separate model. Uses the same Gemini key as the chat.
 *
 * NOT the default any more: grounding is not free for new accounts (see
 * free.ts). Kept for accounts where it works (SEARCH_PROVIDER=gemini).
 *
 * Google returns sources as `vertexaisearch.cloud.google.com/grounding-api-redirect/…`
 * links; we resolve them to the real page URL (one redirect hop, no body read)
 * so the app shows real domains and the "confirmed by 2 domains" check works.
 */
export class GeminiGroundedSearchProvider implements SearchProvider {
  readonly name = 'gemini-google-search';
  constructor(
    private readonly opts: { apiKey: string; baseUrl: string; models: string[]; timeoutMs: number },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  async search(query: string, opts: { freshness?: 'pd' | 'pw' | 'pm' | 'py'; country?: string; lang?: string } = {}): Promise<SearchResult[]> {
    const g = await this.grounded(searchInstruction(query, opts));
    const results = await this.toResults(g);
    // Google's terms ask apps to show the search suggestions: we pass the
    // queries Gemini ran as Google Search links (kind 'search').
    for (const q of g.queries.slice(0, 2)) {
      results.push({ kind: 'search', title: `Google: ${q}`, url: `https://www.google.com/search?q=${encodeURIComponent(q)}`, snippet: '' });
    }
    return results;
  }

  private async grounded(prompt: string): Promise<Grounded> {
    let lastErr: unknown;
    for (const model of this.opts.models) {
      try {
        const res = await fetchWithRetry(
          this.fetchImpl,
          generateContentUrl(this.opts.baseUrl, model),
          {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'x-goog-api-key': this.opts.apiKey },
            body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }], tools: [{ google_search: {} }], generationConfig: { temperature: 0.2, maxOutputTokens: 900 } }),
          },
          { timeoutMs: this.opts.timeoutMs, retries: 0 },
        );
        await expectGoogleOk(res, 'Search');
        return parseGrounded(await res.json());
      } catch (err) {
        lastErr = err;
        // Try the next model when this one is missing, busy or over quota.
        if (!(err instanceof ServiceError) || !/HTTP (400|403|404|429|500|503|504)|timed out|timeout/i.test(err.message)) throw err;
      }
    }
    throw lastErr instanceof Error ? lastErr : new ServiceError('upstream_error', 'Search failed', 502);
  }

  private async toResults(g: Grounded): Promise<SearchResult[]> {
    const urls = await this.resolveAll(g.chunks.map((c) => c.uri));
    const seen = new Set<string>();
    const out: SearchResult[] = [];
    g.chunks.forEach((c, i) => {
      const url = urls[i]!;
      if (seen.has(url)) return;
      seen.add(url);
      const snippet = g.supports
        .filter((s) => s.chunks.includes(i))
        .map((s) => s.text)
        .join(' … ')
        .slice(0, 700);
      out.push({ title: c.title || hostOf(url), url, snippet: snippet || g.text.slice(0, 300) });
    });
    return out.slice(0, 6);
  }

  private resolveAll(uris: string[]): Promise<string[]> {
    return Promise.all(uris.map((u) => this.resolve(u)));
  }

  /** Follows one redirect hop of a grounding link; returns the original on any problem. */
  private async resolve(uri: string): Promise<string> {
    if (!/^https:\/\/vertexaisearch\.cloud\.google\.com\/grounding-api-redirect\//.test(uri)) return uri;
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 3000);
    try {
      const res = await this.fetchImpl(uri, { method: 'GET', redirect: 'manual', signal: ctrl.signal });
      const loc = res.headers.get('location');
      void res.body?.cancel().catch(() => {});
      return loc && /^https?:\/\//.test(loc) ? loc : uri;
    } catch {
      return uri;
    } finally {
      clearTimeout(t);
    }
  }

}

interface Grounded {
  text: string;
  queries: string[];
  chunks: Array<{ uri: string; title: string }>;
  supports: Array<{ text: string; chunks: number[] }>;
}

export function parseGrounded(json: unknown): Grounded {
  const c = (json as { candidates?: Array<Record<string, unknown>> }).candidates?.[0] ?? {};
  const parts = ((c.content as { parts?: Array<{ text?: string; thought?: boolean }> } | undefined)?.parts ?? []).filter((p) => !p.thought);
  const gm = (c.groundingMetadata ?? {}) as {
    webSearchQueries?: string[];
    groundingChunks?: Array<{ web?: { uri?: string; title?: string } }>;
    groundingSupports?: Array<{ segment?: { text?: string }; groundingChunkIndices?: number[] }>;
  };
  return {
    text: parts.map((p) => p.text ?? '').join(''),
    queries: (gm.webSearchQueries ?? []).filter((q) => typeof q === 'string' && q.trim() !== ''),
    chunks: (gm.groundingChunks ?? []).filter((x) => x.web?.uri).map((x) => ({ uri: x.web!.uri!, title: x.web!.title ?? '' })),
    supports: (gm.groundingSupports ?? []).map((s) => ({ text: s.segment?.text ?? '', chunks: s.groundingChunkIndices ?? [] })).filter((s) => s.text),
  };
}

function searchInstruction(query: string, opts: { freshness?: string; country?: string }): string {
  const when = { pd: 'from the last 24 hours', pw: 'from the last 7 days', pm: 'from the last month', py: 'from the last year' }[opts.freshness ?? ''] ?? '';
  return (
    `Search the web for: ${query}\n` +
    (when ? `Prefer results ${when}.\n` : '') +
    (opts.country ? `Prefer sources from country ${opts.country}.\n` : '') +
    'Report only facts found in the search results, as short factual sentences with dates and numbers. If the results do not answer it, say so.'
  );
}



function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url;
  }
}

