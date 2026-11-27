import subprocess,json,hashlib,ast,re,tomllib,datetime,posixpath,sys
from pathlib import Path
import yaml
r=Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip())
a='7f6af7536db3d2aa9ecc9eb51ec82293fc5db3bc';m='595e9953e39e2d704f82bd2de31d2d7b369e68c8'
def git(*args,raw=False):
 out=subprocess.check_output(['git','-C',str(r),*args])
 return out if raw else out.decode()
def smap(ref):
 out={}
 for row in git('ls-tree','-rz','--full-tree',ref,raw=True).split(b'\0'):
  if not row:continue
  h,p=row.split(b'\t',1);mode,kind,oid=h.decode().split();out[p.decode()]={'mode':mode,'type':kind,'oid':oid}
 return out
candidate=sys.argv[1] if len(sys.argv)>1 else None
tree=git('rev-parse',candidate+'^{tree}').strip() if candidate else git('write-tree').strip()
def text_path(p):
 rel=p.relative_to(r).as_posix() if isinstance(p,Path) else p
 return git('show',tree+':'+rel)
before=smap(a);after=smap(tree);main=smap(m)
all_changed=[p for p in sorted(set(before)|set(after)) if before.get(p)!=after.get(p)]
evidence_prefix='docs/integration/main-reconciliation-20261126/'
changed=[p for p in all_changed if not p.startswith(evidence_prefix)]
expected=[
'.agents/rules/ai-team-router.md','.agents/skills/asana-team-coordination/SKILL.md',
'.github/workflows/dispatch-runtime-dependency-updates.yml','.github/workflows/live-activity-bridge.yml',
'.github/workflows/lorvex-apple-account-preflight.yml','.github/workflows/lorvex-apple-provision-profiles.yml',
'.github/workflows/lorvex-apple-register-identifiers.yml','.github/workflows/lorvex-beta-internal.yml',
'.github/workflows/lorvex-secure-secret-transfer.yml','.github/workflows/lorvex-signed-testflight.yml',
'.github/workflows/lorvex-tester-account-probe.yml','.github/workflows/upstream-candidate-proof.yml',
'AGENTS.md','GEMINI.md','docs/ai-team/ASANA_POLICY.md','docs/ai-team/PLATFORMS.md',
'docs/ai-team/PROJECT_ASSIGNMENTS.md','docs/ai-team/TASK_HANDOFF_TEMPLATE.md','docs/ai-team/TEAM.md',
'docs/ai-team/VALIDATION.md','tools/ai-team/ensure-team.ps1']
assert changed==sorted(expected),(changed,expected)
preserved_before={p:v for p,v in before.items() if p not in expected and not p.startswith(evidence_prefix)}
preserved_after={p:v for p,v in after.items() if p not in expected and not p.startswith(evidence_prefix)}
assert preserved_before==preserved_after
manifest=json.dumps(preserved_before,sort_keys=True,separators=(',',':')).encode()
base_map=smap(git('merge-base',a,m).strip())
main_only=[p for p in main if p not in before and p not in base_map]
assert all(after[p]==main[p] for p in main_only)
original=['CLAUDE.md','PROJECT_BOARD.md','PROJECT_AGENT_GUIDANCE.md','.github/workflows/build-ios26-unsigned-ipa.yml','.github/workflows/check-runtime-dependency-updates.yml']
assert all(before[p]==after[p] for p in original)
workflow_paths=[p for p in expected if p.startswith('.github/workflows/')]
workflows={}
for p in workflow_paths:
 data=yaml.load(text_path(p),Loader=yaml.BaseLoader)
 assert isinstance(data.get('jobs'),dict) and 'on' in data,p
 python_count=0;bash_count=0
 for j,v in data['jobs'].items():
  for i,step in enumerate(v.get('steps',[])):
   run=step.get('run')
   if not run:continue
   shell=step.get('shell','')
   if shell.startswith('python'):
    ast.parse(run,filename=p+':'+j+':'+str(i));python_count+=1
   elif shell in ('bash','sh') or not shell:
    check=subprocess.run(['bash','-n'],input=run,text=True,capture_output=True)
    assert check.returncode==0,(p,j,i,check.stderr)
    bash_count+=1
 workflows[p]={'events':sorted(data['on']) if isinstance(data['on'],dict) else data['on'],'jobs':sorted(data['jobs']),'python_steps_parsed':python_count,'shell_steps_syntax_checked':bash_count}
dispatch=yaml.load(text_path('.github/workflows/dispatch-runtime-dependency-updates.yml'),Loader=yaml.BaseLoader)
old_dispatch=yaml.load(git('show',m+':.github/workflows/check-runtime-dependency-updates.yml'),Loader=yaml.BaseLoader)
assert 'schedule' not in dispatch['on']
assert dispatch['jobs']==old_dispatch['jobs']
assert dispatch['permissions']==old_dispatch['permissions']
assert dispatch['on']['workflow_dispatch']==old_dispatch['on']['workflow_dispatch']
producer=yaml.load(text_path('.github/workflows/check-runtime-dependency-updates.yml'),Loader=yaml.BaseLoader)
assert producer['on']['schedule']==old_dispatch['on']['schedule']
frontmatter=[]
for p in [*r.glob('.agents/agents/*.md'),*r.glob('.agents/rules/*.md'),*r.glob('.agents/skills/*/SKILL.md')]:
 s=text_path(p)
 assert s.startswith('---\n'),str(p)
 data=yaml.safe_load(s.split('---',2)[1])
 assert isinstance(data,dict),str(p)
 if '/rules/' in str(p):
  assert data.get('trigger') in ['always_on','model_decision','glob','manual']
  assert len(s.encode())<=24576
 frontmatter.append(str(p.relative_to(r)))
tomls=[]
for p in r.glob('.codex/agents/*.toml'):
 tomllib.loads(text_path(p));tomls.append(str(p.relative_to(r)))
links=[]
for p in [r/'AGENTS.md',r/'GEMINI.md',*r.glob('docs/ai-team/*.md')]:
 for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)',text_path(p)):
  if ':' in target or target.startswith('#'):continue
  target=target.split('#')[0]
  resolved=posixpath.normpath(posixpath.join(str(p.relative_to(r).parent),target))
  assert resolved in after,(str(p),resolved)
  links.append({'source':str(p.relative_to(r)),'target':resolved})
required=['AGENTS.md','GEMINI.md','.agents/rules/ai-team-router.md','.agents/skills/asana-team-coordination/SKILL.md']+['docs/ai-team/'+p+'.md' for p in ['TEAM','PROJECT_ASSIGNMENTS','ASANA_POLICY','TASK_HANDOFF_TEMPLATE','PLATFORMS','BRANCH_INTEGRATION','VALIDATION']]
for role in ['eitan','noam','maya','roni','tomer','yael','dana']:
 required += ['.agents/agents/'+role+'.md','.agents/roles/'+role+'.md','.codex/agents/'+role+'.toml']
assert all(p in after for p in required)
for p in ['AGENTS.md','docs/ai-team/TEAM.md','docs/ai-team/ASANA_POLICY.md','.agents/skills/asana-team-coordination/SKILL.md']:
 s=text_path(p);assert '2026-11-26' in s or 'current authorization' in s
for phrase in ['**No false completion is permitted.**','**Physical Hardware Gate**','Every item in the task','Idempotency & Secret Protection']:
 assert phrase in text_path('docs/ai-team/ASANA_POLICY.md'),phrase
impact=git('show',a+':AGENTS.md').split('## Impact-aware validation and authentic evidence reuse',1)[1].split('## CI Caching',1)[0]
assert impact in text_path('AGENTS.md')
subprocess.run(['git','-C',str(r),'diff','--check',a,candidate] if candidate else ['git','-C',str(r),'diff','--cached','--check'],check=True)
assert not git('diff','--name-only').strip()
receipt={
 'schemaVersion':1,'observedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'rootSource':a,'mainSource':m,'mergeBase':git('merge-base',a,m).strip(),'candidateTree':tree,'candidateRef':candidate or 'INDEX',
 'scope':'Policy/CI reconciliation only; no product input changes and no native tests executed by this reconciliation',
 'changedPaths':changed,'evidencePaths':[p for p in all_changed if p.startswith(evidence_prefix)],'preservedInputCount':len(preserved_before),'preservedInputManifestSHA256':hashlib.sha256(manifest).hexdigest(),
 'allOtherTrackedInputsIdentical':True,'originalRootFilesByteIdentical':{p:after[p] for p in original},
 'mainOnlyFilesByteIdentical':{p:after[p] for p in sorted(main_only)},
 'workflowSyntax':workflows,
 'dispatcher':{'jobsIdenticalToMain':True,'manualInputsIdenticalToMain':True,'permissionsIdenticalToMain':True,'manualOnly':True,'soleWeeklyProducer':'.github/workflows/check-runtime-dependency-updates.yml'},
 'teamStaticChecks':{'yamlFrontmatter':frontmatter,'toml':tomls,'requiredFilesPresent':len(required),'relativeMarkdownLinks':links},
 'nativeExecution':'NOT_RUN: product, dependency, fixture and original native CI inputs unchanged from the root source',
 'independentReview':'PENDING_ROOT: wave2 agent is occupied by a concrete native runtime defect and is not counted as reviewer'
}
build=r/'build/main-reconciliation';build.mkdir(parents=True,exist_ok=True);(build/'validation.json').write_text(json.dumps(receipt,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({'status':'PASS','changed_path_count':len(changed),'preserved_input_count':len(preserved_before),'preserved_manifest_sha256':receipt['preservedInputManifestSHA256'],'main_only_unchanged':sorted(main_only),'workflow_count':len(workflows),'yaml_frontmatter_count':len(frontmatter),'toml_count':len(tomls),'required_team_files':len(required),'index_tree':tree,'receipt':str(build/'validation.json')},ensure_ascii=False))
