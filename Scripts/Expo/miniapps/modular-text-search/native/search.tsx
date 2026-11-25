import { getSearchEngine } from './src/engines/registry.js';
import { buildSnippetSearchModel, nextSnippetSize } from './src/intent/snippetViewModel.js';
import { makeSnippetTextOptions, SNIPPET_RESULT_LIMIT } from './src/intent/snippetDefaults.js';
import { isRtlLocale, normalizeLocale, tFactory } from './src/logic/localization.js';

type Result = {
  id: string; ref: string; heRef?: string; version?: string; snippet?: string;
  path?: string; lang?: string; score?: number; compDate?: number;
};
type Group = { id: string; primary: Result; versions: Result[]; versionCount: number };
type Model = {
  query: string; locale: string; engineId: string; total: number; groups: Group[];
  error?: string; took?: number | null; resultSize: number; hasMore: boolean;
};
type TextVersion = { id: string; versionTitle?: string; versionTitleInHebrew?: string; language?: string; license?: string; text?: string };
type TextResult = { categories?: string[]; versions?: TextVersion[]; error?: string };
type State = {
  model: Model; expandedVersions: Record<string, boolean>; expandedTexts: Record<string, TextResult>;
  loadMoreError?: string;
};
type Parameters = { query?: string; locale?: string; engineId?: string; size?: number; textOptions?: Record<string, unknown> };
type Presentation = {
  kind: 'snippet' | 'translationUI'; sessionID: string; inputText: string;
  parameters: Parameters; allowsReplacement: boolean;
};
type ActionEvent = { parameters: { id?: string; version?: string }; value?: boolean };
type SearchRequest = { query: string; locale: string; size: number; engineId: string };

const key = 'modular-search-presentation-v1';

function presentation(): Presentation {
  return $getenv('presentation') as unknown as Presentation;
}
function readState(): State | null {
  const value = $storage.getString(key);
  return value ? JSON.parse(value) as State : null;
}
function save(state: State): void {
  // The source response remains available while grouping/ranking. Persist only
  // fields used by the view, so copied raw HTTP trees do not multiply state.
  $storage.setString(key, JSON.stringify(state, (name, value) =>
    name === 'raw' || name === 'source' ? undefined : value));
}
function plain(value: unknown): string {
  return String(value ?? '').replace(/<[^>]*>/g, '')
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").trim();
}
function findResult(state: State, id?: string): Result | undefined {
  return state.model.groups.flatMap(group => [group.primary, ...group.versions]).find(result => result.id === id);
}
function label(locale: string, hebrew: string, english: string): string {
  return isRtlLocale(locale) ? hebrew : english;
}
function expandTranslation(): void {
  if (presentation().kind === 'translationUI') $presentation.expandSheet();
}

async function initialState(): Promise<State> {
  const input = presentation();
  const parameters = input.parameters || {};
  const query = String(input.inputText || parameters.query || '').trim();
  const locale = normalizeLocale(parameters.locale || (/[\u0590-\u05ff]/.test(query) ? 'he' : 'en'));
  const request: SearchRequest = {
    query, locale, size: parameters.size || (input.kind === 'translationUI' ? 5 : SNIPPET_RESULT_LIMIT),
    engineId: parameters.engineId || 'sefaria'
  };
  const model = await buildSnippetSearchModel(request) as Model;
  return { model, expandedVersions: {}, expandedTexts: {} };
}

export async function retry(): Promise<void> { save(await initialState()); }
export function toggleVersions(event: ActionEvent): void {
  const state = readState();
  if (!state || !event.parameters.id) return;
  state.expandedVersions[event.parameters.id] = !state.expandedVersions[event.parameters.id];
  save(state);
  expandTranslation();
}
export async function loadFullText(event: ActionEvent): Promise<void> {
  const state = readState();
  if (!state) return;
  const result = findResult(state, event.parameters.id);
  if (!result?.ref) return;
  try {
    const engine = getSearchEngine(state.model.engineId);
    state.expandedTexts[result.id] = await engine.getText(result.ref,
      makeSnippetTextOptions({engineId: engine.id, ...(presentation().parameters.textOptions || {})})) as TextResult;
  } catch (error) {
    state.expandedTexts[result.id] = { error: error instanceof Error ? error.message : String(error) };
  }
  save(state);
  expandTranslation();
}
export function closeFullText(event: ActionEvent): void {
  const state = readState();
  if (!state || !event.parameters.id) return;
  delete state.expandedTexts[event.parameters.id];
  save(state);
}
export async function loadMore(): Promise<void> {
  const state = readState();
  if (!state || !state.model.hasMore) return;
  try {
    const nextSize = nextSnippetSize(state.model.resultSize);
    const request: SearchRequest = {
      query: state.model.query, locale: state.model.locale, size: nextSize, engineId: state.model.engineId
    };
    const next = await buildSnippetSearchModel(request) as Model;
    if (next.error && !next.groups.length) state.loadMoreError = next.error;
    else { state.model = next; delete state.loadMoreError; }
  } catch (error) {
    state.loadMoreError = error instanceof Error ? error.message : String(error);
  }
  save(state);
  expandTranslation();
}
export function replaceText(event: ActionEvent): void {
  const state = readState();
  if (!state) return;
  const result = findResult(state, event.parameters.id);
  if (!result) return;
  const version = state.expandedTexts[result.id]?.versions?.find(item => item.id === event.parameters.version);
  $presentation.finish(plain(version?.text || result.snippet));
}

function ResultCard({result, state}: {result: Result; state: State}) {
  const model = state.model;
  const locale = model.locale;
  const engine = getSearchEngine(model.engineId);
  const t = tFactory(locale);
  const alignment = isRtlLocale(locale) ? 'trailing' : 'leading';
  const expanded = state.expandedTexts[result.id];
  return <vstack alignment={alignment} spacing={7} padding="10" background="#F2F2F7" corner="12">
    <text font="headline">{result.heRef || result.ref || t('unnamedResult')}</text>
    <text font="body">{plain(result.snippet)}</text>
    {result.version ? <text font="caption">{result.version}</text> : null}
    {result.path ? <text font="caption2">{result.path}</text> : null}
    <hstack spacing={12}>
      <button onClick={expanded ? 'closeFullText' : 'loadFullText'} actionParameters={{id: result.id}}>
        <text>{expanded ? label(locale, 'סגור טקסט', 'Close text') : label(locale, 'טקסט מלא', 'Full text')}</text>
      </button>
      <link url={engine.buildWebUrl(result.ref)}><text>{label(locale, 'פתח במקור', 'Open source')}</text></link>
    </hstack>
    {expanded?.error ? <text color="red">{expanded.error}</text> : null}
    {expanded?.categories?.length ? <text font="caption">{expanded.categories.join(' / ')}</text> : null}
    {(expanded?.versions || []).map(version => <vstack alignment={alignment} spacing={6}>
      <text font="headline">{version.versionTitleInHebrew || version.versionTitle || label(locale, 'גרסה', 'Version')}</text>
      {version.language ? <text font="caption">{version.language}</text> : null}
      {version.license ? <text font="caption2">{version.license}</text> : null}
      <text>{plain(version.text)}</text>
      {presentation().allowsReplacement ? <button onClick="replaceText" actionParameters={{id: result.id, version: version.id}}>
        <text>{label(locale, 'החלף את הטקסט הנבחר', 'Replace selected text')}</text>
      </button> : null}
    </vstack>)}
    {presentation().allowsReplacement && !expanded?.versions?.length ? <button onClick="replaceText" actionParameters={{id: result.id}}>
      <text>{label(locale, 'השתמש בתוצאה', 'Use this result')}</text>
    </button> : null}
  </vstack>;
}

export default async function render(): Promise<void> {
  const state = readState() || await initialState();
  save(state);
  const model = state.model;
  const locale = model.locale;
  const alignment = isRtlLocale(locale) ? 'trailing' : 'leading';
  $render(<vstack alignment={alignment} spacing={10}>
    <text font="headline">{label(locale, 'תוצאות עבור ', 'Results for ') + '“' + model.query + '”'}</text>
    <text font="caption">{model.total + label(locale, ' תוצאות · ', ' results · ') + model.groups.length +
      label(locale, ' מוצגות', ' shown') + (model.took != null ? ' · ' + model.took + 'ms' : '')}</text>
    {model.error ? <vstack spacing={6}>
      <text color="red">{model.error}</text>
      <button onClick="retry"><text>{label(locale, 'נסה שוב', 'Try again')}</text></button>
    </vstack> : null}
    {model.groups.map(group => <vstack alignment={alignment} spacing={7}>
      <ResultCard result={group.primary} state={state}/>
      {group.versionCount ? <button onClick="toggleVersions" actionParameters={{id: group.id}}>
        <text>{state.expandedVersions[group.id]
          ? label(locale, 'הסתר גרסאות', 'Hide versions')
          : group.versionCount + label(locale, ' גרסאות נוספות', ' more versions')}</text>
      </button> : null}
      {state.expandedVersions[group.id] ? group.versions.map(result =>
        <ResultCard result={result} state={state}/>) : null}
    </vstack>)}
    {model.hasMore ? <button onClick="loadMore">
      <text>{label(locale, 'טען עוד תוצאות', 'Load more results')}</text>
    </button> : model.groups.length ? <text font="caption">{label(locale, 'סוף התוצאות', 'End of results')}</text> : null}
    {state.loadMoreError ? <text color="red">{state.loadMoreError}</text> : null}
  </vstack>);
}
