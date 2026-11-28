import pathlib,subprocess,json,hashlib,sys,ast,re,importlib.util,datetime
R=pathlib.Path('/mnt/development/projects/worktrees/hanlin-wave1-shared-chat-actions-20261126')
G=['git','--git-dir','/mnt/development/projects/git-mirrors/hanlin-ai.git'];SHA='33f0eb3195406e98139e29dd94819d14e51853bd'
def read(p):return subprocess.check_output(G+['show',SHA+':'+p],text=True)
sys.path.insert(0,str(R/'Scripts/CI/IntegrationValidation'))
import verify_cache_app_tests as P
runner=read('Scripts/ProductSplit/run_paired_acceptance.py');tree=ast.parse(runner)
values={}
for n in tree.body:
 if isinstance(n,ast.Assign) and len(n.targets)==1 and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ['TEST_PLANS','SDK04_MINIAPPS_SELECTORS']:
  values[n.targets[0].id]=ast.literal_eval(n.value)
runtime=None
for n in ast.walk(tree):
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='runtime_selectors' for t in n.targets) and isinstance(n.value,ast.List):
  raw=ast.literal_eval(n.value)
  if len(raw)==17:runtime=raw
assert runtime
mini=runtime+[s for s in values['SDK04_MINIAPPS_SELECTORS'] if s not in runtime]
ai=values['TEST_PLANS']['miniapp_authoring'][0]+values['TEST_PLANS']['miniapp_sdk04'][0]
handoff=json.loads((R/'docs/composer-capabilities/evidence/wave1-integrated-20261126/native-handoff.json').read_text())
groups={
'original_miniapps_complete':mini,
'original_ai_complete':ai,
'cache_app':handoff['app_cache']['selectors'],
'composer_app_scope':handoff['composer']['app_scope']['selectors'],
'composer_native_engines':handoff['composer']['native_engines']['selectors'],
'composer_native_editor':handoff['composer']['native_editor']['selectors'],
'composer_ui_phone':handoff['composer']['ui']['device_selectors']['iPhone'],
'composer_ui_tablet':handoff['composer']['ui']['device_selectors']['iPad'],
'chat_ui':['AI_HLYUITests/AgentRuntimeConversationUITests/testUI02ClassicUserAndAssistantBubbleWithDirectActionButtons','AI_HLYUITests/AgentRuntimeConversationUITests/testUserBubbleLongPressKeepsNativeActionsAndOriginalMessage','AI_HLYUITests/AgentRuntimeConversationUITests/testHebrewNewChatAndNativeMessageActions','AI_HLYUITests/HanlinContextualTextToolsUITests/testOriginalTextToolsReceiveTheMessageWithoutReplacingTheConversation'],
'studio_workspace':['HanlinMiniAppsTests/MiniAppsDeveloperWorkspaceTests']
}
suites={s.split('/')[1] for group in groups.values() for s in group}
selected_methods={}
for group in groups.values():
 for selector in group:
  parts=selector.split('/');suite=parts[1]
  if len(parts)==2:selected_methods[suite]=None
  elif suite not in selected_methods:selected_methods[suite]={parts[2].split('(')[0]}
  elif selected_methods[suite] is not None:selected_methods[suite].add(parts[2].split('(')[0])
pattern=r'(struct|class|extension) ('+'|'.join(sorted(suites))+r')\b'
paths=subprocess.check_output(G+['grep','-l','-E',pattern,SHA,'--','AI_HLYTests','AI_HLYUITests','HanlinMiniAppsTests','HanlinMiniAppsUITests'],text=True).splitlines()
sources={p.split(':',1)[1]:read(p.split(':',1)[1]) for p in paths}
filehash={p:hashlib.sha256(s.encode()).hexdigest() for p,s in sources.items()}
def methods(suite):
 candidates=[(p,s) for p,s in sources.items() if re.search(r'\b(?:struct|class|extension)\s+'+re.escape(suite)+r'\b',s)]
 assert candidates,suite
 result={}
 for path,source in candidates:
  t=P.swift_tokens(source);v=[x[1] for x in t]
  declarations=[i for i in range(len(t)-1) if v[i] in ['class','struct','extension'] and v[i+1]==suite]
  for declaration in declarations:
   start=next(k for k in range(declaration,len(t)) if v[k]=='{');end=P.closing_index(t,start)
   depth=1;index=start+1
   while index<end:
    kind=None;attrs=[];cursor=index
    if depth==1 and v[index:index+2]==['@','Test']:
     kind='SwiftTesting';cursor=index+2
     if v[cursor]=='(':
      closing=P.closing_index(t,cursor);attrs=t[cursor+1:closing];cursor=closing+1
     while v[cursor:cursor+2]==['@','MainActor']:cursor+=2
     assert v[cursor]=='func',(suite,v[cursor:cursor+6])
    elif depth==1 and v[index]=='func' and v[index+1].startswith('test'):
     kind='XCTest'
    if kind:
     name=v[cursor+1]
     if selected_methods[suite] is not None and name not in selected_methods[suite]:
      index+=1;continue
     params=cursor+2;assert v[params]=='('
     closing=P.closing_index(t,params);pv=v[params+1:closing]
     labels=[];current=[]
     for token in pv+[',']:
      if token==',':
       if current:
        assert ':' in current,(suite,name,current)
        labels.append(current[0]);current=[]
      else:current.append(token)
     signature=name+'('+''.join(x+':' for x in labels)+')'
     args=None;av=[x[1] for x in attrs]
     if 'arguments' in av:
      at=av.index('arguments');assert av[at+1:at+3]==[':', '['],(suite,name,av)
      last=P.closing_index(attrs,at+2);body=attrs[at+3:last]
      assert len(labels)==1,(suite,name,labels)
      args=[]
      for token in body:
       if token[1]==',':continue
       if token[0]=='string':args.append(P.literal_string(token))
       elif token[1] in ['true','false']:args.append(token[1]=='true')
       else:raise ValueError(('Unsupported argument token',suite,name,token))
      assert args
     item={'suite':suite,'method':name,'signature':signature,'kind':kind,'source':path,'line':source.count('\n',0,t[cursor][2])+1,'arguments':args,'expected_invocations':len(args) if args is not None else 1}
     if name not in result or kind=='SwiftTesting':result[name]=item
    if t[index][0]!='string':
     if v[index]=='{':depth+=1
     elif v[index]=='}':depth-=1
    index+=1
 assert result,suite
 return result
by_suite={s:methods(s) for s in suites}
report={'source_sha':SHA,'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_sha256':filehash,'runner_sha256':hashlib.sha256(runner.encode()).hexdigest(),'groups':{},'runner_declared_counts':{'original_miniapps_complete':25,'original_ai_complete':27}}
for name,selectors in groups.items():
 cases={}
 for selector in selectors:
  parts=selector.split('/');target,suite=parts[:2];ms=by_suite[suite]
  chosen=list(ms.values()) if len(parts)==2 else [ms[parts[2].split('(')[0]]]
  for m in chosen:
   m=dict(m);method=m['signature'] if m['kind']=='SwiftTesting' else m['method'];m['selector']=target+'/'+suite+'/'+method;cases[m['selector']]=m
 expanded=list(cases.values())
 report['groups'][name]={'source_supported_selectors':[m['selector'] for m in expanded],'source_method_count':len(expanded),'source_invocation_count':sum(m['expected_invocations'] for m in expanded),'cases':expanded,'input_selectors':selectors}
base_ai=set(report['groups']['original_ai_complete']['source_supported_selectors']);base_mini=set(report['groups']['original_miniapps_complete']['source_supported_selectors'])
for name,g in report['groups'].items():
 if name.startswith('original'):continue
 base=base_mini if name.startswith('studio') else base_ai
 g['overlap_with_original_paired']=[s for s in g['source_supported_selectors'] if s in base]
 g['additive_selectors']=[s for s in g['source_supported_selectors'] if s not in base]
out=R/'build/wave1-shared-ui/native-inventory-33f0eb31.json';out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'path':str(out),'source_sha':SHA,'groups':{k:{'methods':v['source_method_count'],'invocations':v['source_invocation_count'],'overlap':len(v.get('overlap_with_original_paired',[]))} for k,v in report['groups'].items()},'original_ai_cases':report['groups']['original_ai_complete']['source_supported_selectors'],'studio_workspace':report['groups']['studio_workspace']['source_supported_selectors']},indent=2))
