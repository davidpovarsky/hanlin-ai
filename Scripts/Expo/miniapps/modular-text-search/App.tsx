import React, { useEffect, useMemo, useRef, useState } from 'react';
import { View } from 'react-native';
import {
  Host, NavigationStack, NavigationLink, NavigationDestination,
  List, Section, Form, Text, Button, Link,
  Picker, Toggle, TextField, LabeledContent, DisclosureGroup,
  ContentUnavailableView, ProgressView, useNativeState,
  hostServices
} from '@hanlin/expo-ui';
import {
  navigationTitle, navigationBarTitleDisplayMode, listStyle, font,
  foregroundStyle, lineLimit, pickerStyle, tag, disabled
} from '@hanlin/expo-ui/modifiers';
import {
  getSearchEngine, listSearchEngines,
  cloneDefaultSearchOptions, cloneDefaultTextOptions
} from './src/engines/registry';
import { appendUniqueResults, groupSearchResults, versionLabel } from './src/logic/searchGrouping';
import { tFactory, getQuickQueries, formatNumber, versionModeOptions } from './src/logic/localization';
import { splitLooseList } from './src/logic/textUtils';

type SearchOptions = Record<string, any>;
type TextOptions = Record<string, any>;
type TextLoaderState = { loading: boolean; error: string; data: any | null };

const secondary = { type: 'hierarchical', style: 'secondary' } as const;

function plainText(value: unknown): string {
  return String(value ?? '')
    .replace(/<[^>]*>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .trim();
}

function InputRow(props: {
  label: string; value: string;
  onChange: (value: string) => void; placeholder?: string; multiline?: boolean;
}) {
  const text = useNativeState(String(props.value ?? ''));
  useEffect(() => { text.set(String(props.value ?? '')); }, [text, props.value]);
  return <LabeledContent label={props.label}>
    <TextField text={text}
      axis={props.multiline ? 'vertical' : 'horizontal'}
      placeholder={props.placeholder}
      onTextChange={props.onChange}/>
  </LabeledContent>;
}

function Choice(props: {
  label: string; value: string;
  choices: Array<{ id: string; name: string }>;
  onChange: (value: string) => void;
  segmented?: boolean;
}) {
  return <Picker label={props.label}
    selection={props.value}
    onSelectionChange={(value: string) => props.onChange(String(value))}
    modifiers={[pickerStyle(props.segmented ? 'segmented' : 'menu')]}>
    {props.choices.map(option =>
      <Text key={option.id} modifiers={[tag(option.id)]}>{option.name}</Text>
    )}
  </Picker>;
}

function NativeSettings(props: {
  locale: string;
  engine: any; engines: any[]; engineId: string;
  onEngineChange: (id: string) => void;
  search: SearchOptions;
  setSearch: React.Dispatch<React.SetStateAction<SearchOptions>>;
  text: TextOptions;
  setText: React.Dispatch<React.SetStateAction<TextOptions>>;
  filters: string; setFilters: (value: string) => void;
  filterFields: string; setFilterFields: (value: string) => void;
  aggregations: string; setAggregations: (value: string) => void;
  customVersions: string; setCustomVersions: (value: string) => void;
  showPayload: boolean; setShowPayload: (value: boolean) => void;
  reset: () => void;
}) {
  const t = tFactory(props.locale);
  const meta = props.engine?.optionMetadata || {};
  const s = props.search;
  const tx = props.text;
  const setS = (patch: SearchOptions) => props.setSearch(old => ({...old, ...patch}));
  const setT = (patch: TextOptions) => props.setText(old => ({...old, ...patch}));
  const choices = (values: string[] = []) =>
    values.map(value => ({id: value, name: value}));
  const versionModes = versionModeOptions(t).map(entry => ({
    id: entry.value, name: entry.label
  }));

  return <Form modifiers={[navigationTitle(t('optionsTitle'))]}>
    <Section title={t('tabEngine')}>
      <Choice label={t('enginePicker')}
        value={props.engineId}
        choices={props.engines.map(item => ({id:item.id, name:item.label}))}
        onChange={props.onEngineChange}/>
      <Text modifiers={[foregroundStyle(secondary)]}>
        {String(props.engine?.description || '')}
      </Text>
    </Section>

    <Section title={t('tabSearch')}>
      <Choice label={t('searchType')} value={String(s.type)}
        choices={choices(meta.searchTypes)}
        segmented
        onChange={value => setS({type:value, field:meta.fieldByType?.[value] || s.field})}/>
      <Choice label={t('searchField')} value={String(s.field)}
        choices={choices(meta.searchFields)}
        onChange={value => setS({field:value})}/>
      <Choice label={t('resultCount')} value={String(s.size)}
        choices={choices(['10','20','50','100'])}
        onChange={value => setS({size:Number(value)})}/>
      <Choice label={t('slop')} value={String(s.slop)}
        choices={choices(['0','1','3','5','10','25','50'])}
        onChange={value => setS({slop:Number(value)})}/>
    </Section>

    <Section title={t('tabSort')}>
      <Choice label={t('sortMethod')} value={String(s.sort_method)}
        segmented choices={choices(meta.sortMethods)}
        onChange={value => setS({sort_method:value})}/>
      <Choice label={t('sortField')} value={String(s.sort_fields?.[0] || 'pagesheetrank')}
        choices={choices(meta.sortFields)}
        onChange={value => setS({sort_fields:[value]})}/>
      <Toggle label={t('reverseSort')} isOn={Boolean(s.sort_reverse)}
        onIsOnChange={value => setS({sort_reverse:value})}/>
      <InputRow label={t('scoreMissing')}
        value={String(s.sort_score_missing ?? '')}
        onChange={value => setS({sort_score_missing:Number(value)})}/>
    </Section>

    <Section title={t('tabFilters')}>
      <Toggle label={t('sourceProjection')} isOn={s.source_proj !== false}
        onIsOnChange={value => setS({source_proj:value})}/>
      <InputRow label={t('filters')} value={props.filters}
        onChange={props.setFilters} placeholder={t('filtersPrompt')} multiline/>
      {s.type === 'sheet' &&
        <InputRow label={t('filterFields')} value={props.filterFields}
          onChange={props.setFilterFields} placeholder={t('filterFieldsPrompt')} multiline/>}
      <InputRow label={t('aggregations')} value={props.aggregations}
        onChange={props.setAggregations} placeholder="path, group, topics"/>
      <Text modifiers={[foregroundStyle(secondary), font({textStyle:'footnote'})]}>
        {t('helpFilters')}
      </Text>
    </Section>

    <Section title={t('tabText')}>
      <Choice label={t('fullTextVersion')} value={String(tx.versionMode)}
        choices={versionModes}
        onChange={value => setT({versionMode:value})}/>
      {tx.versionMode === 'custom' &&
        <InputRow label={t('customVersion')} value={props.customVersions}
          onChange={props.setCustomVersions}
          placeholder={t('customVersionPrompt')} multiline/>}
      <Choice label={t('returnFormat')} value={String(tx.return_format)}
        choices={choices(meta.returnFormats)}
        onChange={value => setT({return_format:value})}/>
      <Toggle label={t('fillMissing')}
        isOn={tx.fill_in_missing_segments === '1'}
        onIsOnChange={value => setT({fill_in_missing_segments:value?'1':'0'})}/>
    </Section>

    <Section title={t('tabDebug')}>
      <Toggle label={t('showPayload')} isOn={props.showPayload}
        onIsOnChange={props.setShowPayload}/>
    </Section>
    <Section>
      <Button label={t('reset')} systemImage="arrow.counterclockwise" onPress={props.reset}/>
    </Section>
  </Form>;
}

function NativeTextVersion({version, locale}: {version:any; locale:string}) {
  const t = tFactory(locale);
  const heading = version.versionTitleInHebrew || version.versionTitle || t('untitledVersion');
  return <DisclosureGroup label={String(heading)}>
    {version.language &&
      <LabeledContent label={t('language')}><Text>{version.language}</Text></LabeledContent>}
    {version.license &&
      <LabeledContent label="License"><Text>{version.license}</Text></LabeledContent>}
    <Text>{plainText(version.text) || t('noVersionText')}</Text>
  </DisclosureGroup>;
}

function NativeFullText({entry, locale, onLoad}: {
  entry: any; locale: string; onLoad: (entry: any) => void;
}) {
  const t = tFactory(locale);
  return <>
    <Button label={t('fullText')} systemImage="book.pages"
      onPress={() => onLoad(entry)} modifiers={[disabled(!entry.ref)]}/>
  </>;
}

function NativeResultDetail(props: {
  group: any; locale: string; engine: any;
  expanded: Record<string,TextLoaderState>;
  onLoadFullText: (entry: any) => void;
}) {
  const {group,locale,engine,expanded,onLoadFullText} = props;
  const t = tFactory(locale);
  const primary = group.primary;
  const entries = [primary,...(group.variants || [])];
  const title = primary.heRef || primary.ref || t('unnamedResult');
  const sourceURL = typeof engine?.buildWebUrl === 'function' && primary.ref
    ? engine.buildWebUrl(primary.ref) : '';

  return <List modifiers={[listStyle('insetGrouped'), navigationTitle(String(title))]}>
    <Section title={t('source')}>
      <Text modifiers={[font({textStyle:'body'})]}>
        {plainText(primary.snippet) || t('noSnippet')}
      </Text>
      {primary.ref && primary.heRef &&
        <LabeledContent label="Reference"><Text>{primary.ref}</Text></LabeledContent>}
      {primary.path &&
        <LabeledContent label={t('path')}><Text>{primary.path}</Text></LabeledContent>}
      {primary.version &&
        <LabeledContent label={t('mainVersion')}><Text>{primary.version}</Text></LabeledContent>}
      {primary.score != null &&
        <LabeledContent label="Score"><Text>{Number(primary.score).toFixed(2)}</Text></LabeledContent>}
      {primary.compDate != null &&
        <LabeledContent label="Date"><Text>{String(primary.compDate)}</Text></LabeledContent>}
      {sourceURL &&
        <Link label={t('openInSource',{source:engine.sourceLabel||engine.label})}
          destination={String(sourceURL)}/>}
    </Section>

    <Section title={t('fullText')}>
      {entries.map((entry:any) => {
        const state = expanded[entry.id];
        const entryTitle = entry.version || entry.heRef || entry.ref || t('variantVersion');
        return <DisclosureGroup key={String(entry.id)} label={String(entryTitle)}>
          <NativeFullText entry={entry} locale={locale} onLoad={onLoadFullText}/>
          {state?.loading && <ProgressView/>}
          {state?.error && <Text modifiers={[foregroundStyle('red')]}>{state.error}</Text>}
          {state?.data?.categories?.length > 0 &&
            <Text modifiers={[foregroundStyle(secondary)]}>
              {state.data.categories.join(' / ')}
            </Text>}
          {state?.data?.versions?.length > 0
            ? state.data.versions.map((version:any) =>
                <NativeTextVersion key={String(version.id)} version={version} locale={locale}/>)
            : !state?.loading && state?.data &&
                <Text>{t('noVersions')}</Text>}
        </DisclosureGroup>;
      })}
    </Section>
  </List>;
}

function NativeResultRow({group,locale}: {group:any;locale:string}) {
  const t = tFactory(locale);
  const primary = group.primary;
  const title = primary.heRef || primary.ref || t('unnamedResult');
  const preview = plainText(primary.snippet).slice(0,205);
  const detail = [title, preview].filter(Boolean).join('\n');
  const extra = (group.variants || []).length;
  return <NavigationLink value={'result:' + String(group.id)}>
    <Text modifiers={[lineLimit(4)]}>
      {detail + (extra ? '\n' + t('moreVersions',{count:formatNumber(extra,locale)}) : '')}
    </Text>
  </NavigationLink>;
}

export default function App() {
  const [locale,setLocale] = useState('he');
  const t = useMemo(() => tFactory(locale),[locale]);
  const [path,setPath] = useState<string[]>([]);
  const [engineId,setEngineId] = useState('sefaria');
  const engine = useMemo(() => getSearchEngine(engineId),[engineId]);
  const engines = useMemo(() => listSearchEngines(),[]);
  const [query,setQuery] = useState('');
  const [submittedQuery,setSubmittedQuery] = useState('');
  const [searchOptions,setSearchOptions] = useState<SearchOptions>(()=>cloneDefaultSearchOptions('sefaria'));
  const [textOptions,setTextOptions] = useState<TextOptions>(()=>cloneDefaultTextOptions('sefaria'));
  const [filtersText,setFiltersText] = useState('');
  const [filterFieldsText,setFilterFieldsText] = useState('');
  const [aggsText,setAggsText] = useState('path');
  const [customVersionsText,setCustomVersionsText] = useState('');
  const [showPayload,setShowPayload] = useState(false);
  const [isLoading,setIsLoading] = useState(false);
  const [isLoadingMore,setIsLoadingMore] = useState(false);
  const [hasMore,setHasMore] = useState(false);
  const [error,setError] = useState('');
  const [diagnostic,setDiagnostic] = useState('');
  const [actionStatus,setActionStatus] = useState('');
  const [meta,setMeta] = useState<any>(null);
  const [lastSearchOptions,setLastSearchOptions] = useState<SearchOptions|null>(null);
  const [results,setResults] = useState<any[]>([]);
  const [expanded,setExpanded] = useState<Record<string,TextLoaderState>>({});
  const searching = useRef(false);
  const loadingPage = useRef(false);

  const groups = useMemo(() => groupSearchResults(results),[results]);
  const suggestions = useMemo(() => getQuickQueries(locale),[locale]);
  const effective = (q:string,start=0,size=searchOptions.size) => ({
    ...searchOptions, query:q, start, size,
    filters:splitLooseList(filtersText),
    filter_fields:splitLooseList(filterFieldsText),
    aggs:splitLooseList(aggsText)
  });

  const payload = useMemo(() => {
    try {
      return JSON.stringify(engine.buildSearchPayload(effective(query)), null, 2);
    } catch {
      return '';
    }
  },[engineId,query,searchOptions,filtersText,filterFieldsText,aggsText]);

  async function search(value?:string) {
    if(searching.current)return;
    const q = String(value ?? query).trim();
    if(!q){
      setError(t('noQueryError'));
      setMeta(null);
      setResults([]);
      setSubmittedQuery('');
      setHasMore(false);
      return;
    }
    searching.current = true;
    const options = effective(q,0);
    setIsLoading(true);
    setError('');
    setDiagnostic('');
    setExpanded({});
    setHasMore(false);
    try {
      const response = await engine.search(options);
      const incoming = Array.isArray(response?.results) ? response.results : [];
      const total = typeof response.total === 'object'
        ? Number(response.total.value||0)
        : Number(response.total||0);
      setResults(incoming);
      setMeta({...response,total});
      setSubmittedQuery(q);
      setLastSearchOptions(options);
      setHasMore(incoming.length>0 && incoming.length<total);
      if(incoming.length===0)setError(t('noResultsError'));
    } catch(e:any) {
      setError(e?.message || String(e));
      setResults([]);
      setMeta(null);
      setSubmittedQuery('');
      setHasMore(false);
    } finally {
      searching.current = false;
      setIsLoading(false);
    }
  }

  async function loadMore() {
    if(searching.current||loadingPage.current||isLoading||isLoadingMore||
       !hasMore||!submittedQuery)return;
    loadingPage.current = true;
    setIsLoadingMore(true);
    setError('');
    const base = lastSearchOptions || effective(submittedQuery);
    const options = {...base,query:submittedQuery,start:results.length,
      size:Math.max(1,Math.min(100,Number(base.size||20)))};
    try {
      const response = await engine.search(options);
      const merged = appendUniqueResults(results,response.results||[]);
      const total = typeof response.total === 'object'
        ? Number(response.total.value||0) : Number(response.total||0);
      setResults(merged.results);
      setMeta((current:any) => current
        ? {...current,took:response.took,total,aggregations:response.aggregations}
        : response);
      setHasMore(merged.added.length>0 && merged.results.length<total);
    } catch(e:any) {
      setError(e?.message||String(e));
    } finally {
      loadingPage.current = false;
      setIsLoadingMore(false);
    }
  }

  async function loadFullText(entry:any) {
    if(!entry?.ref)return;
    const id = String(entry.id);
    setExpanded(old=>({...old,[id]:{loading:true,error:'',data:null}}));
    try {
      const data = await engine.getText(entry.ref,{
        ...textOptions,customVersions:customVersionsText
      });
      setExpanded(old=>({...old,[id]:{loading:false,error:'',data}}));
    } catch(e:any) {
      setExpanded(old=>({...old,[id]:{loading:false,error:e?.message||String(e),data:null}}));
    }
  }

  async function checkConnection() {
    setDiagnostic(locale==='he'?'בודק חיבור ל־Sefaria…':'Checking Sefaria connection…');
    try {
      const nativeAllowed = await hostServices.hasCapability('ios-native-api');
      const networkAllowed = await hostServices.hasCapability('network');
      if(!nativeAllowed||!networkAllowed){
        const missing = [!nativeAllowed?'ios-native-api':null,!networkAllowed?'network':null]
          .filter(Boolean).join(', ');
        setDiagnostic((locale==='he'?'הרשאה חסרה: ':'Missing permission: ') + missing);
        return;
      }
      const probe = await engine.search({...effective('שבת',0,1),query:'שבת',size:1,start:0});
      const n = Array.isArray(probe?.results) ? probe.results.length : 0;
      setDiagnostic(n>0
        ? (locale==='he'?'החיבור תקין — נמצאה תוצאה ב־Sefaria.':'Connected — Sefaria returned a result.')
        : (locale==='he'?'החיבור תקין אך לא נמצאה תוצאת ניסיון.':'Connected, but no test result was found.'));
    } catch(e:any) {
      setDiagnostic((locale==='he'?'שגיאת חיבור: ':'Connection error: ')+
        String(e?.message||e).slice(0,320));
    }
  }

  function resetOptions() {
    setSearchOptions(cloneDefaultSearchOptions(engine.id));
    setTextOptions(cloneDefaultTextOptions(engine.id));
    setFiltersText('');
    setFilterFieldsText('');
    setAggsText('path');
    setCustomVersionsText('');
    setShowPayload(false);
  }

  function switchEngine(next:string) {
    const nextEngine = getSearchEngine(next);
    setEngineId(nextEngine.id);
    setSearchOptions(cloneDefaultSearchOptions(nextEngine.id));
    setTextOptions(cloneDefaultTextOptions(nextEngine.id));
    setFiltersText('');
    setFilterFieldsText('');
    setAggsText((nextEngine.defaultSearchOptions?.aggs||['path']).join(', '));
    setCustomVersionsText('');
    setResults([]);
    setExpanded({});
    setMeta(null);
    setSubmittedQuery('');
    setHasMore(false);
    setError('');
  }

  return <View style={{flex:1}}>
    <Host style={{flex:1}}
      layoutDirection={locale==='he'?'rightToLeft':'leftToRight'}>
      <NavigationStack path={path} onPathChange={setPath}
        modifiers={[navigationTitle(t('appTitle')),navigationBarTitleDisplayMode('large')]}>
        <List modifiers={[listStyle('insetGrouped')]}>
              <Section title={locale==='he'?'חיפוש':'Search'}>
                <InputRow label={t('searchPrompt')} value={query} onChange={setQuery}
                  placeholder={t('searchPrompt')}/>
                <Text modifiers={[foregroundStyle(secondary)]}>Hanlin Expo 1.1.2</Text>
                <Button label={t('searchNow')} systemImage="magnifyingglass"
                  onPress={()=>{
                    setActionStatus(locale==='he'?'לחיצה על חיפוש התקבלה.':'Search button pressed.');
                    void search(query);
                  }}
                  modifiers={[disabled(isLoading)]}/>
                <Button label={locale==='he'?'בדיקת חיבור':'Check connection'}
                  systemImage="network"
                  onPress={()=>{
                    setActionStatus(locale==='he'?'לחיצה על בדיקת חיבור התקבלה.':'Connection test button pressed.');
                    void checkConnection();
                  }}/>
                <NavigationLink value="settings">
                  <Text>{t('optionsTitle')}</Text>
                </NavigationLink>
                <Button label={locale==='he'?'English':'עברית'} systemImage="globe"
                  onPress={()=>setLocale(locale==='he'?'en':'he')}/>
                {Boolean(actionStatus) && <Text modifiers={[foregroundStyle(secondary)]}>{actionStatus}</Text>}
              </Section>
              {isLoading &&
                <Section>
                  <ProgressView><Text>{t('searching')}</Text></ProgressView>
                </Section>}
              {!!error &&
                <Section title={t('message')}>
                  <Text modifiers={[foregroundStyle('red')]}>{error}</Text>
                </Section>}
              {!!diagnostic &&
                <Section title={locale==='he'?'בדיקת חיבור':'Connection test'}>
                  <Text>{diagnostic}</Text>
                </Section>}
              {!!meta &&
                <Section title={t('resultSummary')}>
                  <LabeledContent label={t('shownResults',{count:formatNumber(groups.length,locale)})}>
                    <Text>{t('totalResults',{total:formatNumber(meta.total,locale)})}</Text>
                  </LabeledContent>
                  {meta.took != null && <Text modifiers={[foregroundStyle(secondary)]}>
                    {String(meta.took) + ' ms'}
                  </Text>}
                </Section>}
              {groups.length > 0 &&
                <Section title={t('resultsTitle')}>
                  {groups.map(group =>
                    <NativeResultRow key={String(group.id)} group={group} locale={locale}/>)}
                  {hasMore &&
                    <Button label={isLoadingMore?t('loadingMore'):t('moreResults')}
                      systemImage="arrow.down.circle"
                      onPress={()=>{void loadMore();}}
                      modifiers={[disabled(isLoadingMore)]}/>}
                  {isLoadingMore && <ProgressView/>}
                </Section>}
              {!meta && !isLoading && !error &&
                <Section>
                  <ContentUnavailableView title={t('emptyTitle')}
                    systemImage="text.magnifyingglass"
                    description={locale==='he'
                      ? 'הקלד מילה בשדה החיפוש למעלה ולחץ על חפש עכשיו.'
                      : 'Enter a term in the search field above and tap Search.'}/>
                </Section>}
              {!meta && !isLoading &&
                <Section title={t('quickExamples')}>
                  {suggestions.slice(0,5).map(value =>
                    <Button key={value} label={value} systemImage="magnifyingglass"
                      onPress={()=>{setQuery(value);void search(value);}}/>)}
                </Section>}
              {showPayload &&
                <Section title={t('payload')}>
                  <Text modifiers={[font({textStyle:'footnote'})]}>{payload}</Text>
                </Section>}
        </List>
        <NavigationDestination value="settings">
          <NativeSettings locale={locale} engine={engine}
            engines={engines} engineId={engineId}
            onEngineChange={switchEngine}
            search={searchOptions} setSearch={setSearchOptions}
            text={textOptions} setText={setTextOptions}
            filters={filtersText} setFilters={setFiltersText}
            filterFields={filterFieldsText} setFilterFields={setFilterFieldsText}
            aggregations={aggsText} setAggregations={setAggsText}
            customVersions={customVersionsText} setCustomVersions={setCustomVersionsText}
            showPayload={showPayload} setShowPayload={setShowPayload}
            reset={resetOptions}/>
        </NavigationDestination>
        {groups.map(group =>
          <NavigationDestination key={String(group.id)} value={'result:' + String(group.id)}>
            <NativeResultDetail group={group} locale={locale}
              engine={engine} expanded={expanded}
              onLoadFullText={loadFullText}/>
          </NavigationDestination>)}
      </NavigationStack>
    </Host>
  </View>;
}
