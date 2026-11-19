export interface SearchResult {
  title: string;
  url: string;
  snippet: string;
  /** ISO date or provider "age" string, only when the provider supplies it */
  date?: string;
  /** 'search' = a Google Search suggestion link (shown, never cited as evidence). */
  kind?: 'web' | 'search';
}
export interface SearchProvider {
  readonly name: string;
  search(query: string, opts?: { freshness?: 'pd' | 'pw' | 'pm' | 'py'; country?: string; lang?: string }): Promise<SearchResult[]>;
}
