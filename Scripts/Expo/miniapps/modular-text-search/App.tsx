import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Linking, View } from 'react-native';
import {
  Host, NavigationStack, List, Section, VStack, HStack, Text, Button,
  Toggle, Picker, TextField, PopoverPresentation,
  ProgressView, ScrollView, useNativeState, hostServices
} from '@hanlin/expo-ui';
import {
  navigationTitle, navigationBarTitleDisplayMode, listStyle, font,
  foregroundStyle, background, cornerRadius, frame, padding,
  buttonStyle, controlSize, pickerStyle, tag,
  multilineTextAlignment, textFieldStyle, disabled
} from '@hanlin/expo-ui/modifiers';
import {
  getSearchEngine, listSearchEngines,
  cloneDefaultSearchOptions, cloneDefaultTextOptions
} from './src/engines/registry';
import { appendUniqueResults, groupSearchResults, versionLabel } from './src/logic/searchGrouping';
import {
  tFactory, getQuickQueries, formatNumber, versionModeOptions, isRtlLocale
} from './src/logic/localization';
import { splitLooseList } from './src/logic/textUtils';

type SearchOptions = Record<string, any>;
type TextOptions = Record<string, any>;
type TextLoaderState = { loading: boolean; error: string; data: any | null };
const ink = '#22272D';
const muted = '#65717F';
const blue = '#007AFF';
const mutedSurface = '#F2F3F7';

function SoftText({children, small = false}: {children: React.ReactNode; small?: boolean}) {
  return <Text modifiers={[font({size: small ? 12 : 14}), foregroundStyle(muted)]}>{children}</Text>;
}
function TitleText({children, large = false}: {children: React.ReactNode; large?: boolean}) {
  return <Text modifiers={[font({size: large ? 22 : 17, weight: 'semibold'}), foregroundStyle(ink)]}>{children}</Text>;
}
function Chip({children, color = muted}: {children: React.ReactNode; color?: string}) {
  return <Text modifiers={[
    font({size: 11, weight: 'semibold'}), foregroundStyle(color),
    padding({vertical: 5, horizontal: 8}),
    background('#F0F1F5'), cornerRadius(14)
  ]}>{children}</Text>;
}
function NativeCard({children, inset = false}: {children: React.ReactNode; inset?: boolean}) {
  return <VStack spacing={10} alignment="leading" modifiers={[
    padding({all: inset ? 12 : 14}),
    background(inset ? '#F4F5F8' : '#FFFFFF'),
    cornerRadius(17),
    frame({maxWidth: 980, alignment: 'leading'})
  ]}>{children}</VStack>;
}
function PillButton({label, onPress, primary = false, disabledValue = false}: {
  label: string; onPress: () => void; primary?: boolean; disabledValue?: boolean;
}) {
  return <Button label={label} onPress={onPress} modifiers={[
    buttonStyle(primary ? 'borderedProminent' : 'bordered'),
    controlSize('small'), disabled(disabledValue)
  ]}/>;
}
function EditableField({value, onChange, placeholder = '', multiline = false}: {
  value: string; onChange: (next: string) => void; placeholder?: string; multiline?: boolean;
}) {
  const state = useNativeState(String(value ?? ''));
  useEffect(() => { state.set(String(value ?? '')); }, [state, value]);
  return <TextField
    text={state} placeholder={placeholder} axis={multiline ? 'vertical' : 'horizontal'}
    onTextChange={onChange}
    modifiers={[textFieldStyle('roundedBorder')]}
  />;
}
function Choice({label, value, choices, onChange, segmented = false}: {
  label: string; value: string; choices: Array<{id: string; name: string}>;
  onChange: (id: string) => void; segmented?: boolean;
}) {
  return <Picker label={label} selection={value} onSelectionChange={(x: string) => onChange(String(x))}
    modifiers={[pickerStyle(segmented ? 'segmented' : 'menu')]}>
    {choices.map(item =>
      <Text key={item.id} modifiers={[tag(item.id)]}>{item.name}</Text>
    )}
  </Picker>;
}
function FieldRow({label, value, onChange, placeholder, multiline}: {
  label: string; value: string; onChange: (x: string) => void;
  placeholder?: string; multiline?: boolean;
}) {
  return <VStack alignment="leading" spacing={4}>
    <SoftText small>{label}</SoftText>
    <EditableField value={value} onChange={onChange} placeholder={placeholder}
      multiline={multiline}/>
  </VStack>;
}
function SearchOptionsPanel(props: {
  t: (key: string, params?: any) => string; locale: string;
  engine: any; engines: any[]; engineId: string;
  onEngineChange: (x: string) => void;
  search: SearchOptions; setSearch: React.Dispatch<React.SetStateAction<SearchOptions>>;
  text: TextOptions; setText: React.Dispatch<React.SetStateAction<TextOptions>>;
  filters: string; setFilters: (x: string) => void;
  filterFields: string; setFilterFields: (x: string) => void;
  aggs: string; setAggs: (x: string) => void;
  customVersions: string; setCustomVersions: (x: string) => void;
  showPayload: boolean; setShowPayload: (x: boolean) => void;
  onReset: () => void; onClose: () => void;
}) {
  const {t} = props;
  const [tabName, setTabName] = useState('search');
  const data = props.engine?.optionMetadata || {};
  const s = props.search;
  const tx = props.text;
  const setS = (part: any) => props.setSearch(old => ({...old, ...part}));
  const setT = (part: any) => props.setText(old => ({...old, ...part}));
  const opts = (items: string[]) => (items || []).map(x => ({id: x, name: x}));
  const modes = versionModeOptions(t).map(x => ({id: x.value, name: x.label}));
  return <VStack spacing={11} alignment="leading" modifiers={[
    frame({minWidth: 315, idealWidth: 365, maxWidth: 465, maxHeight: 630}),
    padding({all: 15})
  ]}>
    <TitleText>{t('optionsTitle')}</TitleText>
    <SoftText small>{t('optionsSubtitle')}</SoftText>
    <Choice label="" value={tabName} segmented onChange={setTabName} choices={[
      {id:'engine',name:t('tabEngine')}, {id:'search',name:t('tabSearch')},
      {id:'sort',name:t('tabSort')}, {id:'filters',name:t('tabFilters')},
      {id:'text',name:t('tabText')}, {id:'debug',name:t('tabDebug')}
    ]}/>
    <ScrollView>
      <VStack spacing={11} alignment="leading" modifiers={[padding({vertical: 8})]}>
        {tabName === 'engine' && <VStack spacing={10} alignment="leading">
          <Choice label={t('enginePicker')} value={props.engineId}
            choices={props.engines.map(e => ({id:e.id,name:e.label}))} onChange={props.onEngineChange}/>
          <TitleText>{props.engine?.label}</TitleText>
          <SoftText>{props.engine?.description}</SoftText>
          <HStack spacing={7}>
            {props.engine?.capabilities?.search && <Chip color={blue}>{t('capabilitySearch')}</Chip>}
            {props.engine?.capabilities?.fullText && <Chip color="#248847">{t('capabilityFullText')}</Chip>}
            {props.engine?.capabilities?.snippets && <Chip color="#A252B6">{t('capabilitySnippet')}</Chip>}
          </HStack>
        </VStack>}
        {tabName === 'search' && <VStack spacing={10} alignment="leading">
          <Choice label={t('searchType')} value={String(s.type)} segmented
            choices={opts(data.searchTypes)} onChange={x => setS({type:x,field:data.fieldByType?.[x] || s.field})}/>
          <Choice label={t('searchField')} value={String(s.field)}
            choices={opts(data.searchFields)} onChange={x=>setS({field:x})}/>
          <Choice label={t('resultCount')} value={String(s.size)}
            choices={opts(['10','20','50','100'])} onChange={x=>setS({size:Number(x)})}/>
          <Choice label={t('slop')} value={String(s.slop)}
            choices={opts(['0','1','3','5','10','25','50'])} onChange={x=>setS({slop:Number(x)})}/>
        </VStack>}
        {tabName === 'sort' && <VStack spacing={11} alignment="leading">
          <Choice label={t('sortMethod')} value={String(s.sort_method)} segmented
            choices={opts(data.sortMethods)} onChange={x=>setS({sort_method:x})}/>
          <Choice label={t('sortField')} value={String(s.sort_fields?.[0] || 'pagesheetrank')}
            choices={opts(data.sortFields)} onChange={x=>setS({sort_fields:[x]})}/>
          <Toggle label={t('reverseSort')} isOn={Boolean(s.sort_reverse)}
            onIsOnChange={x=>setS({sort_reverse:x})}/>
          <FieldRow label={t('scoreMissing')} value={String(s.sort_score_missing ?? '')}
            onChange={x=>setS({sort_score_missing: Number(x)})} placeholder="0.04"/>
        </VStack>}
        {tabName === 'filters' && <VStack spacing={11} alignment="leading">
          <SoftText>{t('activeFilters')}</SoftText>
          <SoftText small>{splitLooseList(props.filters).join(' · ') || t('noActiveFilters')}</SoftText>
          <Toggle label={t('sourceProjection')} isOn={s.source_proj !== false}
            onIsOnChange={x=>setS({source_proj:x})}/>
          <FieldRow label={t('filters')} value={props.filters} onChange={props.setFilters}
            multiline placeholder={t('filtersPrompt')}/>
          {s.type === 'sheet' && <FieldRow label={t('filterFields')} value={props.filterFields}
            onChange={props.setFilterFields} multiline placeholder={t('filterFieldsPrompt')}/>}
          <FieldRow label={t('aggregations')} value={props.aggs} onChange={props.setAggs}
            placeholder={data.aggregationFields?.join(', ') || 'path'}/>
          <SoftText small>{t('helpFilters')}</SoftText>
        </VStack>}
        {tabName === 'text' && <VStack spacing={11} alignment="leading">
          <Choice label={t('fullTextVersion')} value={String(tx.versionMode)}
            choices={modes} onChange={x=>setT({versionMode:x})}/>
          {tx.versionMode === 'custom' && <FieldRow label={t('customVersion')}
            value={props.customVersions} onChange={props.setCustomVersions}
            placeholder={t('customVersionPrompt')} multiline/>}
          <Choice label={t('returnFormat')} value={String(tx.return_format)}
            choices={opts(data.returnFormats)} onChange={x=>setT({return_format:x})}/>
          <Toggle label={t('fillMissing')} isOn={tx.fill_in_missing_segments === '1'}
            onIsOnChange={x=>setT({fill_in_missing_segments:x?'1':'0'})}/>
        </VStack>}
        {tabName === 'debug' && <VStack spacing={12} alignment="leading">
          <Toggle label={t('showPayload')} isOn={props.showPayload}
            onIsOnChange={props.setShowPayload}/>
          <SoftText>{t('payload')}</SoftText>
        </VStack>}
      </VStack>
    </ScrollView>
    <HStack spacing={12}>
      <PillButton label={t('reset')} onPress={props.onReset}/>
      <PillButton label={t('done')} primary onPress={props.onClose}/>
    </HStack>
  </VStack>;
}
function TextVersion({version, t}: {version:any; t:(key:string, params?:any)=>string}) {
  return <NativeCard inset>
    <TitleText>{version.versionTitleInHebrew || version.versionTitle || t('untitledVersion')}</TitleText>
    <HStack spacing={5}>
      {Boolean(version.language) && <Chip>{version.language}</Chip>}
      {Boolean(version.license) && <Chip>{version.license}</Chip>}
      {version.isSource && <Chip color={blue}>{t('source')}</Chip>}
      {version.isPrimary && <Chip color="#248847">{t('primary')}</Chip>}
    </HStack>
    <Text modifiers={[
      font({size:16}), foregroundStyle(ink),
      multilineTextAlignment(version.direction === 'rtl' ? 'trailing' : 'leading')
    ]}>{version.text || t('noVersionText')}</Text>
  </NativeCard>;
}
function ExpandedText({state, onClose, t}: {
  state?:TextLoaderState; onClose:()=>void; t:(key:string,params?:any)=>string
}) {
  if (!state) return null;
  if (state.loading) return <HStack spacing={9}><ProgressView/><SoftText>{t('loadingFullText')}</SoftText></HStack>;
  if (state.error) return <VStack spacing={8} alignment="leading">
    <Text modifiers={[foregroundStyle('#BF3030')]}>{t('fullTextError')}</Text>
    <SoftText>{state.error}</SoftText>
    <PillButton label={t('close')} onPress={onClose}/>
  </VStack>;
  const data=state.data;
  return <VStack spacing={10} alignment="leading">
    <HStack spacing={8}>
      <TitleText>{data?.heRef || data?.ref || ''}</TitleText>
      <PillButton label={t('close')} onPress={onClose}/>
    </HStack>
    <SoftText>{data?.categories?.join(' / ') || data?.title || ''}</SoftText>
    {Boolean(data?.warnings?.length) && <Text modifiers={[foregroundStyle('#AE7100')]}>
      {data.warnings.join(' · ')}
    </Text>}
    {data?.versions?.length ? data.versions.map((v:any) =>
      <TextVersion key={v.id} version={v} t={t}/>
    ) : <SoftText>{t('noVersions')}</SoftText>}
  </VStack>;
}
function SearchResult({group, locale, expanded, versionOpen,
  toggleVersions, loadFullText, closeFullText, engine}: {
  group:any;locale:string;expanded:Record<string,TextLoaderState>;
  versionOpen:boolean;toggleVersions:()=>void;loadFullText:(x:any)=>void;
  closeFullText:(x:string)=>void;engine:any
}) {
  const t=tFactory(locale);
  const primary=group.primary;
  const variants=group.variants || [];
  const subtitle=[primary.version,primary.path].filter(Boolean).join(' · ');
  const sourceURL=typeof engine?.buildWebUrl === 'function' && primary.ref
    ? engine.buildWebUrl(primary.ref) : null;
  return <NativeCard>
    <HStack spacing={6}>
      <Chip color={blue}>{t('mainVersion')}</Chip>
      {primary.lang && <Chip>{primary.lang}</Chip>}
    </HStack>
    <TitleText large>{primary.heRef || primary.ref || t('unnamedResult')}</TitleText>
    {primary.heRef && primary.ref && <SoftText small>{primary.ref}</SoftText>}
    <Text modifiers={[
      font({size:16}),foregroundStyle(ink),
      multilineTextAlignment(isRtlLocale(locale)?'trailing':'leading')
    ]}>{primary.snippet || t('noSnippet')}</Text>
    {Boolean(subtitle) && <SoftText small>{subtitle}</SoftText>}
    <HStack spacing={5}>
      {primary.score != null && <Chip>{'score '+Number(primary.score).toFixed(1)}</Chip>}
      {primary.compDate != null && <Chip>{String(primary.compDate)}</Chip>}
      {versionLabel(primary) && <Chip>{versionLabel(primary)}</Chip>}
    </HStack>
    <HStack spacing={8}>
      <PillButton label={expanded[primary.id] ? t('refreshFullText') : t('fullText')}
        primary onPress={()=>loadFullText(primary)} disabledValue={!primary.ref}/>
      {sourceURL && <PillButton label={t('openInSource',{source:engine.sourceLabel||engine.label})}
        onPress={()=>{Linking.openURL(sourceURL).catch(()=>{});}}/>}
    </HStack>
    <ExpandedText state={expanded[primary.id]} onClose={()=>closeFullText(primary.id)} t={t}/>
    {variants.length>0 && <>
      <PillButton label={versionOpen ? t('hideVersions') :
        t('moreVersions',{count:formatNumber(variants.length,locale)})} onPress={toggleVersions}/>
      {versionOpen && variants.map((variant:any)=>
        <NativeCard key={variant.id} inset>
          <HStack spacing={6}><Chip>{t('variantVersion')}</Chip>
            {variant.lang && <Chip color={blue}>{variant.lang}</Chip>}
          </HStack>
          <TitleText>{variant.version || t('variantVersion')}</TitleText>
          <SoftText small>{[variant.lang,variant.path].filter(Boolean).join(' · ')}</SoftText>
          <Text modifiers={[font({size:15}),multilineTextAlignment(isRtlLocale(locale)?'trailing':'leading')]}>
            {variant.snippet || t('noSnippet')}
          </Text>
          <HStack spacing={8}>
            <PillButton label={expanded[variant.id] ? t('refreshFullText') : t('fullText')}
              onPress={()=>loadFullText(variant)}/>
            {variant.ref && <PillButton label={t('openInSource',{source:engine.sourceLabel||engine.label})}
              onPress={()=>{Linking.openURL(engine.buildWebUrl(variant.ref)).catch(()=>{});}}/>}
          </HStack>
          <ExpandedText state={expanded[variant.id]} onClose={()=>closeFullText(variant.id)} t={t}/>
        </NativeCard>
      )}
    </>}
  </NativeCard>;
}
export default function App() {
  const [locale,setLocale]=useState('he');
  const t=useMemo(()=>tFactory(locale),[locale]);
  const [engineId,setEngineId]=useState('sefaria');
  const engine=useMemo(()=>getSearchEngine(engineId),[engineId]);
  const engines=useMemo(()=>listSearchEngines(),[]);
  const [query,setQuery]=useState('');
  const [submittedQuery,setSubmittedQuery]=useState('');
  const [searchOptions,setSearchOptions]=useState<SearchOptions>(()=>cloneDefaultSearchOptions('sefaria'));
  const [textOptions,setTextOptions]=useState<TextOptions>(()=>cloneDefaultTextOptions('sefaria'));
  const [filtersText,setFiltersText]=useState('');
  const [filterFieldsText,setFilterFieldsText]=useState('');
  const [aggsText,setAggsText]=useState('path');
  const [customVersionsText,setCustomVersionsText]=useState('');
  const [showOptions,setShowOptions]=useState(false);
  const [showPayload,setShowPayload]=useState(false);
  const [isLoading,setIsLoading]=useState(false);
  const [searchPhase,setSearchPhase]=useState<'idle'|'loading'|'ready'|'empty'|'failed'>('idle');
  const [diagnostic,setDiagnostic]=useState('');
  const [isLoadingMore,setIsLoadingMore]=useState(false);
  const [hasMore,setHasMore]=useState(false);
  const [error,setError]=useState('');
  const [meta,setMeta]=useState<any>(null);
  const [lastSearchOptions,setLastSearchOptions]=useState<SearchOptions|null>(null);
  const [results,setResults]=useState<any[]>([]);
  const [expanded,setExpanded]=useState<Record<string,TextLoaderState>>({});
  const [expandedVersions,setExpandedVersions]=useState<Record<string,boolean>>({});
  const searching=useRef(false);
  const loadingPage=useRef(false);
  const groups=useMemo(()=>groupSearchResults(results),[results]);
  const suggestions=useMemo(()=>getQuickQueries(locale),[locale]);
  const activeFilters=useMemo(()=>[
    ...splitLooseList(filtersText),
    ...(searchOptions.type==='sheet'?splitLooseList(filterFieldsText):[])
  ],[filtersText,filterFieldsText,searchOptions.type]);
  const effective=(q:string,start=0,size=searchOptions.size)=>({
    ...searchOptions,query:q,start,size,
    filters:splitLooseList(filtersText),
    filter_fields:splitLooseList(filterFieldsText),
    aggs:splitLooseList(aggsText)
  });
  const payload=useMemo(()=>{
    try{return JSON.stringify(engine.buildSearchPayload(effective(query)),null,2);}
    catch{return '';}
  },[engineId,query,searchOptions,filtersText,filterFieldsText,aggsText]);
  async function checkConnection() {
    setDiagnostic(locale==='he'?'בודק הרשאות ואת חיבור הרשת המקורי של iOS…':'Checking iOS native permissions and network…');
    try {
      const nativeAllowed=await hostServices.hasCapability('ios-native-api');
      const networkAllowed=await hostServices.hasCapability('network');
      if(!nativeAllowed||!networkAllowed) {
        const missing=[!nativeAllowed?'ios-native-api':null,!networkAllowed?'network':null]
          .filter(Boolean).join(', ');
        setDiagnostic((locale==='he'?'הרשאה חסרה: ':'Missing permission: ')+missing+
          (locale==='he'?' · יש לאשר בפרטי החבילה.':' · Approve in package details.'));
        return;
      }
      const probe=await engine.search({...effective('שבת',0,1),query:'שבת',start:0,size:1});
      const n=Array.isArray(probe?.results)?probe.results.length:0;
      if(n>0) {
        setDiagnostic(locale==='he'?'חיבור iOS ל־Sefaria תקין — נמצאה תוצאת ניסיון.':
          'iOS native Sefaria connection succeeded — test result found.');
      } else {
        setDiagnostic(locale==='he'?'החיבור פועל אך החיפוש הניסיוני לא החזיר תוצאות.':
          'Connected, but the test search returned no results.');
      }
    } catch(e:any) {
      setDiagnostic((locale==='he'?'שגיאת רשת iOS: ':'iOS network error: ')+
        (e?.message||String(e)).slice(0,300));
    }
  }
  async function search(override?:SearchOptions) {
    if(searching.current)return;
    const q=String(override?.query??query).trim();
    if(!q){
      setError(t('noQueryError'));setResults([]);setMeta(null);setSubmittedQuery('');setHasMore(false);
      setSearchPhase('failed');
      return;
    }
    searching.current=true;
    // Always retain the selected search settings. The previous implementation
    // discarded them when submitting a query via the native search field.
    const options={...effective(q,0),...(override||{}),query:q,start:0};
    setSearchPhase('loading');
    setIsLoading(true);setIsLoadingMore(false);setHasMore(false);setError('');
    setExpanded({});setExpandedVersions({});
    try{
      const response=await engine.search(options);
      const total=typeof response.total==='object'?Number(response.total.value||0):Number(response.total||0);
      const incoming=Array.isArray(response?.results)?response.results:[];
      setResults(incoming);
      setMeta({...response,total});
      setSubmittedQuery(q);
      setLastSearchOptions(options);
      setHasMore(incoming.length>0 && incoming.length<total);
      setSearchPhase(incoming.length>0?'ready':'empty');
      if(!incoming.length)setError(t('noResultsError'));
    }catch(e:any){
      setSearchPhase('failed');
      setError(e?.message||String(e));setResults([]);setMeta(null);setSubmittedQuery('');setHasMore(false);
    }finally{searching.current=false;setIsLoading(false);}
  }
  async function loadMore(){
    if(searching.current||loadingPage.current||isLoading||isLoadingMore||!hasMore||!submittedQuery)return;
    loadingPage.current=true;
    setIsLoadingMore(true);setError('');
    const base=lastSearchOptions||effective(submittedQuery);
    const options={...base,query:submittedQuery,start:results.length,
      size:Math.max(1,Math.min(100,Number(base.size||20)))};
    try{
      const response=await engine.search(options);
      const merged=appendUniqueResults(results,response.results||[]);
      const total=typeof response.total==='object'?Number(response.total.value||0):Number(response.total||0);
      setResults(merged.results);setMeta((current:any)=>current?{
        ...current,took:response.took,total,aggregations:response.aggregations
      }:response);
      setHasMore(merged.added.length>0 && merged.results.length<total);
    }catch(e:any){setError(e?.message||String(e));}
    finally{loadingPage.current=false;setIsLoadingMore(false);}
  }
  async function loadFullText(result:any){
    if(!result?.ref)return;
    const id=String(result.id);
    setExpanded(old=>({...old,[id]:{loading:true,error:'',data:null}}));
    try{
      const data=await engine.getText(result.ref,{...textOptions,customVersions:customVersionsText});
      setExpanded(old=>({...old,[id]:{loading:false,error:'',data}}));
    }catch(e:any){
      setExpanded(old=>({...old,[id]:{loading:false,error:e?.message||String(e),data:null}}));
    }
  }
  function resetSearchSettings(){
    setSearchOptions(cloneDefaultSearchOptions(engine.id));
    setTextOptions(cloneDefaultTextOptions(engine.id));
    setFiltersText('');setFilterFieldsText('');setAggsText('path');
    setCustomVersionsText('');setShowPayload(false);
  }
  function onEngineChange(next:string){
    const e=getSearchEngine(next);
    setEngineId(e.id);setSearchOptions(cloneDefaultSearchOptions(e.id));
    setTextOptions(cloneDefaultTextOptions(e.id));
    setFiltersText('');setFilterFieldsText('');setAggsText((e.defaultSearchOptions?.aggs||['path']).join(', '));
    setCustomVersionsText('');setResults([]);setExpanded({});setExpandedVersions({});
    setMeta(null);setSubmittedQuery('');setHasMore(false);setError('');
  }
  const searchPhaseLabel=(locale==='he'?{
    idle:'מוכן לחיפוש', loading:'מחפש במקורות…',
    ready:'החיפוש הושלם',empty:'לא נמצאו תוצאות',failed:'החיפוש נכשל'
  }:{
    idle:'Ready to search',loading:'Searching sources…',
    ready:'Search completed',empty:'No results found',failed:'Search failed'
  })[searchPhase];
  const showSearchSummary=!!meta;
  const searchResultsText=showSearchSummary
    ? t('searchResultsFor',{query:submittedQuery}):t('quickExamples');
  const totalsText=showSearchSummary
    ? t('totalResults',{total:formatNumber(meta.total,locale)}):t('emptyMessage');
  return <View style={{flex:1}}>
    <Host style={{flex:1}} layoutDirection={locale==='he'?'rightToLeft':'leftToRight'} seedColor={blue}>
      <NavigationStack modifiers={[
        navigationTitle(t('appTitle')),navigationBarTitleDisplayMode('large')
      ]}>
        <List modifiers={[listStyle('insetGrouped')]}>
            <Section>
              <NativeCard>
                <TitleText>{searchResultsText}</TitleText>
                <SoftText>{totalsText}</SoftText>
                <EditableField value={query} onChange={setQuery} placeholder={t('searchPrompt')}/>
                <SoftText small>{searchPhaseLabel}</SoftText>
                {Boolean(error) && <Text modifiers={[font({size:14}),foregroundStyle('#BC3535')]}>
                  {error}
                </Text>}
                {!showSearchSummary && <HStack spacing={7}>
                  {suggestions.slice(0,3).map(q=><PillButton key={q} label={q}
                    onPress={()=>{setQuery(q);search({query:q});}}/>)}
                </HStack>}
                <HStack spacing={8}>
                  <PillButton label={isLoading?t('searching'):t('searchNow')} primary
                    disabledValue={isLoading||isLoadingMore} onPress={()=>{search({query});}}/>
                  <PopoverPresentation isPresented={showOptions} onPresentedChange={setShowOptions}
                    onDismiss={()=>setShowOptions(false)}
                    presented={<SearchOptionsPanel
                      locale={locale} t={t} engine={engine} engines={engines} engineId={engineId}
                      onEngineChange={onEngineChange}
                      search={searchOptions} setSearch={setSearchOptions}
                      text={textOptions} setText={setTextOptions}
                      filters={filtersText} setFilters={setFiltersText}
                      filterFields={filterFieldsText} setFilterFields={setFilterFieldsText}
                      aggs={aggsText} setAggs={setAggsText}
                      customVersions={customVersionsText} setCustomVersions={setCustomVersionsText}
                      showPayload={showPayload} setShowPayload={setShowPayload}
                      onReset={resetSearchSettings} onClose={()=>setShowOptions(false)}
                    />}>
                    <PillButton label={activeFilters.length?
                      t('filtersButtonWithCount',{count:formatNumber(activeFilters.length,locale)})
                      :t('filtersButton')} onPress={()=>setShowOptions(true)}/>
                  </PopoverPresentation>
                  <PillButton label={locale==='he'?'בדיקת חיבור':'Check connection'}
                    onPress={()=>{void checkConnection();}}/>
                  <PillButton label={locale==='he'?'English':'עברית'}
                    onPress={()=>setLocale(locale==='he'?'en':'he')}/>
                </HStack>
                {Boolean(diagnostic) && <Text modifiers={[
                  font({size:12}),foregroundStyle(muted)
                ]}>{diagnostic}</Text>}
              </NativeCard>
            </Section>
            {showPayload && <Section title={t('payload')}>
              <SoftText small>{payload}</SoftText>
            </Section>}
            {isLoading && <Section>
              <HStack spacing={9}><ProgressView/>
                <SoftText>{t('searchingSource',{source:engine.sourceLabel||engine.label})}</SoftText>
              </HStack>
            </Section>}

            {showSearchSummary && <Section title={t('resultSummary')}>
              <HStack spacing={8}>
                <SoftText>{t('shownResults',{count:formatNumber(groups.length,locale)})}</SoftText>
                <SoftText>{t('fromTotal',{total:formatNumber(meta.total,locale)})}</SoftText>
                {meta.took!=null && <SoftText small>{'· '+String(meta.took)+'ms'}</SoftText>}
              </HStack>
            </Section>}
            {groups.length>0 ? <Section title={t('resultsTitle')}>
              {groups.map((group:any)=><SearchResult key={group.id}
                group={group} locale={locale} expanded={expanded}
                versionOpen={!!expandedVersions[group.id]} engine={engine}
                toggleVersions={()=>setExpandedVersions(old=>({...old,[group.id]:!old[group.id]}))}
                loadFullText={loadFullText}
                closeFullText={(id)=>setExpanded(old=>{const n={...old};delete n[id];return n;})}
              />)}
              {hasMore && <VStack spacing={8} modifiers={[padding({all:12})]}>
                {isLoadingMore && <ProgressView/>}
                <SoftText>{isLoadingMore?t('loadingMore'):t('loadingMoreHint')}</SoftText>
                <Button label={t('moreResults')} onPress={loadMore}
                  modifiers={[buttonStyle('bordered')]}/>
              </VStack>}
              {!hasMore && !isLoadingMore && <SoftText>{t('endOfResults')}</SoftText>}
            </Section> : !isLoading&&!error ? <Section>
              <VStack spacing={8} modifiers={[padding({all:24})]}>
                <TitleText>{t('emptyTitle')}</TitleText>
                <SoftText>{t('emptyMessage')}</SoftText>
              </VStack>
            </Section> : null}
        </List>
      </NavigationStack>
    </Host>
  </View>;
}
