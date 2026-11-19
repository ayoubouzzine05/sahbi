import { ServiceError } from '../../errors.js';
import { expectGoogleOk, fetchWithRetry, type FetchLike } from '../../http.js';
import { generateContentUrl } from '../llm/gemini.js';

export interface YoutubeVideo {
  id: string;
  title: string;
  author: string;
  thumbnail: string;
  url: string;
}

/**
 * Finds YouTube videos for in-app playback with the official embedded player.
 *
 * 1. With `YOUTUBE_API_KEY` (YouTube Data API v3, free quota, no billing):
 *    `search.list` with `videoEmbeddable=true`.
 * 2. Without it: the chat's Gemini model suggests official video links from
 *    its own knowledge (free; no web search), and every suggestion is checked
 *    against YouTube's oEmbed endpoint. oEmbed answers 200 only for public,
 *    embeddable videos and returns the REAL title, which must match the song
 *    the model claimed, so an invented or wrong id is dropped.
 */
export class YoutubeFinder {
  constructor(
    private readonly opts: { apiKey?: string; gemini?: { apiKey: string; baseUrl: string; models: string[] } },
    private readonly fetchImpl: FetchLike = fetch,
  ) {}

  private dataApiRefused = '';

  get mode(): 'youtube-data-api' | 'gemini-oembed' | 'none' {
    return this.opts.apiKey ? 'youtube-data-api' : this.opts.gemini ? 'gemini-oembed' : 'none';
  }

  async find(query: string): Promise<YoutubeVideo[]> {
    return (await this.findWithStats(query)).videos;
  }

  /** Also reports how many links the model suggested and how many were real + embeddable. */
  async findWithStats(query: string): Promise<{ videos: YoutubeVideo[]; suggested: number; embeddable: number; via?: string; dataApi?: string }> {
    if (this.opts.apiKey) {
      const videos = await this.dataApi(query, this.opts.apiKey);
      return { videos, suggested: videos.length, embeddable: videos.length };
    }
    if (this.opts.gemini) {
      // The Gemini key also works for the YouTube Data API when that API is
      // enabled on the same Google Cloud project (no billing needed). Try it
      // once; remember a refusal so later requests skip straight to Gemini.
      if (!this.dataApiRefused) {
        try {
          const videos = await this.dataApi(query, this.opts.gemini.apiKey);
          return { videos, suggested: videos.length, embeddable: videos.length, via: 'youtube-data-api' };
        } catch (err) {
          if (err instanceof ServiceError && /HTTP (400|401|403|404|429)/.test(err.message)) {
            this.dataApiRefused = err.message.slice(0, 300);
          } else {
            throw err;
          }
        }
      }
      return { ...(await this.fromGemini(query, this.opts.gemini)), via: 'gemini-oembed', dataApi: this.dataApiRefused };
    }
    throw new ServiceError('not_configured', 'YouTube search is not configured', 503);
  }

  private async dataApi(query: string, key: string): Promise<YoutubeVideo[]> {
    const params = new URLSearchParams({ part: 'snippet', type: 'video', videoEmbeddable: 'true', maxResults: '5', q: query, key });
    const res = await fetchWithRetry(this.fetchImpl, `https://www.googleapis.com/youtube/v3/search?${params}`, { headers: { accept: 'application/json' } }, { timeoutMs: 10000, retries: 1 });
    await expectGoogleOk(res, 'YouTube');
    const j = (await res.json()) as {
      items?: Array<{ id?: { videoId?: string }; snippet?: { title?: string; channelTitle?: string; thumbnails?: { high?: { url?: string } } } }>;
    };
    return (j.items ?? [])
      .filter((i) => i.id?.videoId && /^[A-Za-z0-9_-]{11}$/.test(i.id.videoId))
      .map((i) => ({
        id: i.id!.videoId!,
        title: decodeEntities(i.snippet?.title ?? ''),
        author: decodeEntities(i.snippet?.channelTitle ?? ''),
        thumbnail: i.snippet?.thumbnails?.high?.url ?? `https://i.ytimg.com/vi/${i.id!.videoId}/hqdefault.jpg`,
        url: `https://www.youtube.com/watch?v=${i.id!.videoId}`,
      }));
  }

  private async fromGemini(query: string, g: { apiKey: string; baseUrl: string; models: string[] }): Promise<{ videos: YoutubeVideo[]; suggested: number; embeddable: number }> {
    const prompt =
      `List up to 8 YouTube videos for this music request: "${query}". ` +
      'The request may be in Moroccan Darija, Arabic, French or English; first work out the artist and song (or the artist\'s best-known songs if only an artist is given). ' +
      'Prefer official music videos, official audio or the artist\'s channel. Only give links you are confident really exist. ' +
      'Answer JSON only: {"videos":[{"url":"https://www.youtube.com/watch?v=...","title":"song title","artist":"artist name"}]}';
    let lastErr: unknown;
    for (const model of g.models) {
      try {
        const res = await fetchWithRetry(
          this.fetchImpl,
          generateContentUrl(g.baseUrl, model),
          {
            method: 'POST',
            headers: { 'content-type': 'application/json', 'x-goog-api-key': g.apiKey },
            body: JSON.stringify({
              contents: [{ role: 'user', parts: [{ text: prompt }] }],
              generationConfig: { temperature: 0.2, maxOutputTokens: 1200, responseMimeType: 'application/json' },
            }),
          },
          { timeoutMs: 25000, retries: 0 },
        );
        await expectGoogleOk(res, 'YouTube search');
        const json = (await res.json()) as { candidates?: Array<{ content?: { parts?: Array<{ text?: string; thought?: boolean }> } }> };
        const text = (json.candidates?.[0]?.content?.parts ?? [])
          .filter((p) => !p.thought)
          .map((p) => p.text ?? '')
          .join('');
        return await this.verify(query, parseCandidates(text));
      } catch (err) {
        lastErr = err;
        if (!(err instanceof ServiceError) || !/HTTP (404|429|500|503|504)|timed out|timeout/i.test(err.message)) throw err;
      }
    }
    throw lastErr instanceof Error ? lastErr : new ServiceError('upstream_error', 'YouTube search failed', 502);
  }

  private async verify(query: string, cands: Candidate[]): Promise<{ videos: YoutubeVideo[]; suggested: number; embeddable: number }> {
    const seen = new Set<string>();
    const unique = cands.filter((c) => !seen.has(c.id) && seen.add(c.id)).slice(0, 8);
    let embeddable = 0;
    const checked = await Promise.all(
      unique.map(async (c) => {
        const v = await this.oembed(c.id);
        if (!v) return null;
        embeddable++;
        // The song must be in the real video TITLE (the channel alone is not
        // enough: an invented id may point to another video of the artist).
        return claimMatches(c, v.title, v.author) || matchesQuery(query, v.title, 2) ? v : null;
      }),
    );
    return { videos: checked.filter((v): v is YoutubeVideo => v !== null).slice(0, 5), suggested: unique.length, embeddable };
  }

  /** YouTube oEmbed answers 200 only for public videos that allow embedding. */
  async oembed(id: string): Promise<YoutubeVideo | null> {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 5000);
    try {
      const url = `https://www.youtube.com/watch?v=${id}`;
      const res = await this.fetchImpl(`https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(url)}`, { signal: ctrl.signal });
      if (res.status !== 200) return null;
      const j = (await res.json()) as { title?: string; author_name?: string; thumbnail_url?: string };
      if (!j.title) return null;
      return { id, title: j.title, author: j.author_name ?? '', thumbnail: j.thumbnail_url ?? `https://i.ytimg.com/vi/${id}/hqdefault.jpg`, url };
    } catch {
      return null;
    } finally {
      clearTimeout(t);
    }
  }
}

interface Candidate {
  id: string;
  title: string;
  artist: string;
}

export function parseCandidates(text: string): Candidate[] {
  const out: Candidate[] = [];
  try {
    const start = text.indexOf('{');
    const j = JSON.parse(start >= 0 ? text.slice(start, text.lastIndexOf('}') + 1) : text) as { videos?: Array<{ url?: string; title?: string; artist?: string }> };
    for (const v of j.videos ?? []) {
      const id = youtubeId(v.url ?? '');
      if (id) out.push({ id, title: v.title ?? '', artist: v.artist ?? '' });
    }
  } catch {
    // Not JSON: fall back to bare links (they then need a query match).
    for (const u of text.match(/https?:\/\/[^\s"')\]]+/g) ?? []) {
      const id = youtubeId(u);
      if (id) out.push({ id, title: '', artist: '' });
    }
  }
  return out;
}

export function youtubeId(u: string): string | null {
  const m = /(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|shorts\/|embed\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/.exec(u);
  return m ? m[1]! : null;
}

const norm = (x: string) =>
  x
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
const words = (x: string) => norm(x).split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 3 && !STOP.has(w));
const STOP = new Set(['the', 'and', 'official', 'video', 'music', 'audio', 'clip', 'feat', 'lyrics', 'avec', 'les', 'des']);

/** True when at least `need` meaningful words of the query appear in the text. */
export function matchesQuery(query: string, text: string, need = 1): boolean {
  const t = norm(text);
  const ws = words(query);
  const hits = ws.filter((w) => t.includes(w)).length;
  return ws.length > 0 && hits >= Math.min(need, ws.length);
}

/** The claimed song must be in the real title, the claimed artist in the title or channel. */
function claimMatches(c: Candidate, title: string, channel: string): boolean {
  const t = norm(title);
  const tc = norm(`${title} ${channel}`);
  const a = words(c.artist);
  const s = words(c.title);
  if (!a.length || !s.length) return false;
  return a.some((w) => tc.includes(w)) && s.some((w) => t.includes(w));
}

function decodeEntities(s: string): string {
  return s.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}
