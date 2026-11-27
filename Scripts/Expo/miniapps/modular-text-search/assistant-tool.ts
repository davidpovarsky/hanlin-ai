import type { HanlinAssistantToolHandler } from '@hanlin/assistant-tools';
import { search as searchSefaria } from './src/engines/sefaria/client.js';
import type { normalizeHit } from './src/engines/sefaria/client.js';

interface SearchArguments { query: string }
interface SearchConfiguration {
  filters: string[];
  field: 'naive_lemmatizer' | 'exact' | 'content';
  size: number;
}

/** Dedicated module: it imports the existing search engine, never App/index.
 * The user's catalog/field/limit snapshot comes from context, not model guesses.
 */
export const search: HanlinAssistantToolHandler<SearchArguments, SearchConfiguration> = async (
  arguments_, { configuration }
) => {
  const query = arguments_.query.trim();
  if (!query) throw new Error('A nonempty search query is required.');
  const options = {
    query,
    filters: configuration.filters,
    field: configuration.field,
    size: Math.floor(configuration.size),
    type: 'text',
    aggs: ['path']
  };
  const response = await searchSefaria(options);
  return {
    query,
    filters: configuration.filters,
    field: configuration.field,
    size: options.size,
    total: response.total,
    timedOut: response.timedOut,
    results: response.results.map((item: ReturnType<typeof normalizeHit>) => ({
      ref: item.ref,
      heRef: item.heRef,
      version: item.version,
      lang: item.lang,
      categories: item.categories,
      snippet: item.snippet
    }))
  };
};
