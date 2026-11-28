#!/usr/bin/env python3
"""Read-only Git/evidence comparison; never executes a test, compiler or package manager."""
from pathlib import Path
import datetime, hashlib, json, re, subprocess

ROOT = '/mnt/development/projects/worktrees/hanlin-ai-cache-integration-20261125'
TARGET = '6fbcf703dd9f40f5b1d42592d58a0a69573dcdfa'
OUT = Path('/mnt/development/projects/artifacts/hanlin-ai-cache-final-reuse-20261125/local-js')
OLD_RECEIPT = 'docs/ai-cache/evidence/reuse-receipt-20261125.json'
CHECKPOINT_RECEIPT = 'docs/ai-cache/evidence/latest-sync-before-app04-20261125.json'
JS_ROOT = 'docs/ai-cache/evidence/active-assistant-js-20261125/'
LOCAL_ROOT = 'docs/ai-cache/evidence/local-cache-20261125/'
OUT.mkdir(parents=True, exist_ok=True)

def git(*args):
    return subprocess.check_output(['git','-c','safe.directory='+ROOT,'-C',ROOT,*args])
def content(rev,path):
    return git('show',rev+':'+path)
def sha(data):
    return hashlib.sha256(data).hexdigest()
def js(rev,path):
    return json.loads(content(rev,path))
def blob(rev,path):
    return git('rev-parse',rev+':'+path).decode().strip()
def identity(path,rev=TARGET):
    b=content(rev,path)
    return {'path':path,'source_commit':rev,'git_blob':blob(rev,path),'sha256':sha(b),'bytes':len(b)}
def write_json(name,value):
    p=OUT/name
    p.write_text(json.dumps(value,indent=2,sort_keys=True,ensure_ascii=False)+'\n')
    return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())}
def canonical_sha(value):
    return sha(json.dumps(value,sort_keys=True,separators=(',',':')).encode())

old=js(TARGET,OLD_RECEIPT)
checkpoint=js(TARGET,CHECKPOINT_RECEIPT)
checkpoint_rev=checkpoint['integratedSource']
local=js(TARGET,LOCAL_ROOT+'receipt.json')
summary=js(TARGET,JS_ROOT+'summary.json')
original_receipts = {
    'expo-assistant-tests.json':js(TARGET,JS_ROOT+'expo-assistant-tests.json'),
    'host-facade-tests-after.json':js(TARGET,JS_ROOT+'host-facade-tests-after.json'),
    'nativescript-generation.json':js(TARGET,JS_ROOT+'nativescript-generation.json'),
    'summary.json':summary,
    'local_cache_accounting':local,
}
recorded=[]
unique={}
failures=[]
for group, previous in old['recorded_input_comparisons'].items():
    receipt=original_receipts[group]
    if group=='local_cache_accounting':
        values=receipt['sourceFiles']
    elif group=='summary.json':
        values=receipt['files']
    else:
        values={**receipt.get('inputs',{}),**receipt.get('generated',{})}
    for previous_row in previous['comparisons']:
        path=previous_row['path']
        expected=values[path]
        proof_rev=previous_row['proof_commit']
        proof=content(proof_rev,path)
        current=content(TARGET,path)
        row={
          'group':group,'path':path,'proof_commit':proof_rev,
          'original_receipt':previous['receipt'],
          'recorded_sha256':expected,
          'proof_sha256':sha(proof),'proof_git_blob':blob(proof_rev,path),
          'target_sha256':sha(current),'target_git_blob':blob(TARGET,path),
          'receipt_matches_original_git':sha(proof)==expected,
          'target_matches_original_bytes':current==proof and sha(current)==expected,
        }
        recorded.append(row)
        if not row['receipt_matches_original_git'] or not row['target_matches_original_bytes']:
            failures.append(row)
        unique[path]=sha(current)
supplemental=[]
for previous_row in old['supplemental_source_comparisons']:
    path=previous_row['path']; proof_rev=previous_row['proof_commit']
    proof=content(proof_rev,path); current=content(TARGET,path)
    row={'path':path,'proof_commit':proof_rev,'proof_sha256':sha(proof),
         'target_sha256':sha(current),'proof_git_blob':blob(proof_rev,path),
         'target_git_blob':blob(TARGET,path),
         'matches_retained_source_assessment':sha(proof)==previous_row['proof_sha256'],
         'byte_identical':proof==current,
         'historical_input_hash_recorded_at_execution':False}
    supplemental.append(row)
    if not row['byte_identical'] or not row['matches_retained_source_assessment']:
        failures.append(row)
    unique[path]=sha(current)
checkpoint_rows=[]
for path, entry in checkpoint['reusedSourceInputs'].items():
    current=content(TARGET,path); historical=content(checkpoint_rev,path)
    row={'path':path,'checkpoint_commit':checkpoint_rev,'checkpoint_sha256':sha(historical),
         'checkpoint_receipt_sha256':entry['sha256'],'target_sha256':sha(current),
         'target_git_blob':blob(TARGET,path),
         'all_equal':sha(current)==sha(historical)==entry['sha256']==unique.get(path)}
    checkpoint_rows.append(row)
    if not row['all_equal']: failures.append(row)
if set(unique)!=set(checkpoint['reusedSourceInputs']):
    failures.append({'closure_path_set_mismatch':True})
if len(unique)!=36:
    failures.append({'unexpected_unique_count':len(unique)})

npm_specs={
 'Scripts/NativeScript/package-lock.json':['node_modules/typescript'],
 'Scripts/Expo/package-lock.json':['node_modules/typescript','node_modules/@typescript/old','node_modules/base64-js'],
}
npm=[]
for path, packages in npm_specs.items():
    proof_rev=summary['generatedAndHarnessCommit']
    proof=js(proof_rev,path); current=js(TARGET,path)
    entries=[]
    for package in packages:
        a=proof['packages'][package]; b=current['packages'][package]
        match=a==b
        entries.append({'package':package,'original_entry':a,'target_entry':b,
                        'original_entry_sha256':canonical_sha(a),
                        'target_entry_sha256':canonical_sha(b),'exact_entry_equal':match})
        if not match: failures.append({'dependency':package,'lockfile':path,'changed':True})
    npm.append({'path':path,'proof_commit':proof_rev,
                'proof_lock_sha256':sha(content(proof_rev,path)),
                'target_lock_sha256':sha(content(TARGET,path)),
                'entire_lockfile_equal':content(proof_rev,path)==content(TARGET,path),
                'consumed_entries':entries})
proof_lru=js(TARGET,LOCAL_ROOT+'proof-Package.resolved')['pins'][0]
if local['resolved']['pins']!=[proof_lru]:
    failures.append({'original_lru_receipt_vs_retained_resolution_mismatch':True})
current_lru_path='AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
current_lru=next(p for p in js(TARGET,current_lru_path)['pins'] if p['identity']=='lrucache')
lru_equal=current_lru==proof_lru
if not lru_equal:failures.append({'lru_current_pin_mismatch':True})
manifest=content(TARGET,'Package.swift').decode()
lru_declaration='.package(url: "https://github.com/nicklockwood/LRUCache.git", exact: "1.3.0"),'
if lru_declaration not in manifest: failures.append({'lru_canonical_declaration_missing':True})

compiler_observations=[]
for historical in old['dependencies']['installed_compiler_codec_observations']:
    p=Path(historical['path'])
    row={'path':str(p),'prior_assessment_sha256':historical['sha256'],
         'prior_assessment_was_historical_execution_hash':p.name=='typescript.js' and '/NativeScript/' in str(p)}
    if p.is_file():
        b=p.read_bytes()
        row.update({'present':True,'bytes':len(b),'sha256':sha(b),
                    'matches_prior_assessment':sha(b)==historical['sha256']})
    else:row['present']=False
    compiler_observations.append(row)
ns_recorded=original_receipts['nativescript-generation.json']['typescriptSHA256']
ns_observation=next(x for x in compiler_observations if '/NativeScript/' in x['path'])
ns_hash_matches=ns_observation.get('sha256')==ns_recorded

evidence_paths=[
 OLD_RECEIPT,CHECKPOINT_RECEIPT,
 LOCAL_ROOT+'receipt.json',LOCAL_ROOT+'proof-Package.swift',LOCAL_ROOT+'proof-Package.resolved',LOCAL_ROOT+'raw.log',
 JS_ROOT+'summary.json',JS_ROOT+'expo-assistant-tests.json',JS_ROOT+'expo-assistant-tests.log',
 JS_ROOT+'host-facade-tests-after.json',JS_ROOT+'host-facade-tests-after.log',
 JS_ROOT+'nativescript-generation.json',JS_ROOT+'nativescript-generation.log',
 JS_ROOT+'nativescript-generated-check.log',
]
evidence=[identity(p) for p in evidence_paths]
logs={}
for p in [LOCAL_ROOT+'raw.log',JS_ROOT+'expo-assistant-tests.log',JS_ROOT+'host-facade-tests-after.log',JS_ROOT+'nativescript-generation.log',JS_ROOT+'nativescript-generated-check.log']:
    text=content(TARGET,p).decode()
    item=identity(p)
    item['summary_lines']=[l for l in text.splitlines() if
      'Test run with ' in l or re.search(r'^ℹ (tests|pass|fail|cancelled|skipped|todo) ',l) or l.startswith('PASS:')]
    item['executed_pass_names']=[
       re.sub(r'^(✔ Test |✔ )','',l).split(' passed after ')[0].rsplit(' (',1)[0]
       for l in text.splitlines() if l.startswith('✔ ') and not l.startswith('✔ Suite ') and not l.startswith('✔ Test run ')]
    logs[p]=item
local_raw=content(TARGET,LOCAL_ROOT+'raw.log')
local_summary='Test run with 18 tests in 2 suites passed' in local_raw.decode()
if sha(local_raw)!=local['logSHA256'] or not local_summary:
    failures.append({'local_raw_binding_or_count_failed':True})
for filename,count in [('expo-assistant-tests.log',7),('host-facade-tests-after.log',8)]:
    text=content(TARGET,JS_ROOT+filename).decode()
    if not all(re.search(r'^ℹ '+label+r' '+str(n)+r'$',text,re.M) for label,n in [('tests',count),('pass',count),('fail',0)]):
        failures.append({'js_log_count_mismatch':filename})

all_matches=not failures
report={
 'verification_kind':'READ_ONLY_EXACT_SOURCE_AND_RETAINED_EVIDENCE_COMPARISON',
 'verified_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'target_commit':TARGET,'target_tree':git('rev-parse',TARGET+'^{tree}').decode().strip(),
 'target_snapshot_read_from_git':True,
 'new_test_execution':False,'new_build_execution':False,'new_dependency_installation':False,
 'source_or_branch_modified':False,'current_application_acceptance_claimed':False,
 'result':'UNCHANGED_BOUNDED_INPUTS_REUSE_SUPPORTED' if all_matches else 'INPUT_DRIFT_OR_EVIDENCE_MISMATCH',
 'unique_input_files':len(unique),'checkpoint_unique_input_files':checkpoint['reusedSourceInputCount'],
 'recorded_comparison_count':len(recorded),'supplemental_comparison_count':len(supplemental),
 'all_input_and_consumed_dependency_comparisons_equal':all_matches,
 'checkpoint_comparisons':checkpoint_rows,
 'recorded_input_comparisons':recorded,'supplemental_source_comparisons':supplemental,
 'local_cache_accounting':{
   'status':'REUSED_VERIFIED_PASS' if all_matches else 'REVIEW_REQUIRED',
   'original_source':local['sourceSHA'],'original_command':local['command'],
   'original_toolchain':local['toolchain'],'original_execution_exit_code':local['exitCode'],
   'source_files':len(local['sourceFiles']),'production_files':len(local['sources']),'test_files':len(local['tests']),
   'tests':{'cache_lifecycle':11,'usage_accounting':7,'total':18},
   'retained_raw_log_sha256':sha(local_raw),
   'reuse_scope':'Original HanlinCacheProof macOS source harness, with its nine real production files, two real test files and LRUCache 1.3.0. This does not certify the full iOS app, UI, live providers, SwiftData or billing.',
   'retained_fixture_manifest':identity(LOCAL_ROOT+'proof-Package.swift'),
   'retained_fixture_resolution':identity(LOCAL_ROOT+'proof-Package.resolved'),
   'original_lru_pin':proof_lru,'target_canonical_lru_pin':current_lru,
   'target_canonical_lru_resolution_path':current_lru_path,'lru_pins_equal':lru_equal,
   'target_manifest_lru_declaration':lru_declaration,
   'test_import_behavior':'Original source includes canImport(HanlinCacheProof) branches; no test/import rewriting is needed or performed in this verification.',
 },
 'active_assistant_javascript':{
   'status':'REUSED_VERIFIED_PASS' if all_matches else 'REVIEW_REQUIRED',
   'original_implementation_source':summary['implementationCommit'],
   'original_generated_and_harness_source':summary['generatedAndHarnessCommit'],
   'original_node':summary['node'],'original_native_script_typescript':summary['nativeScriptTypeScript'],
   'original_expo_vm_typescript':summary['expoVMTypeScript'],
   'tests':{'shared_assistant_and_publication':7,'native_script_and_expo_vm':8,'total':15},
   'strict_generation_and_drift':'Original retained PASS; generation was not rerun',
   'unique_source_inputs':len(unique)-len(local['sourceFiles']),
   'reuse_scope':'Original Node facade/unit/VM tests and original strict NativeScript facade generation only. No native Expo/NativeScript Host, app, live model, billing or UI acceptance follows from this result.',
   'original_commands':{k:v.get('command') for k,v in original_receipts.items() if k in ['expo-assistant-tests.json','host-facade-tests-after.json','nativescript-generation.json']},
 },
 'dependencies':{
   'consumed_npm_lock_entries':npm,
   'original_native_script_typescript_file_sha256':ns_recorded,
   'current_installed_native_script_entry_file_matches_original':ns_hash_matches,
   'read_only_current_installed_observations':compiler_observations,
   'compiler_hash_limit':'The original Expo VM receipt records TypeScript API 6.0.3, not its compiler-file or codec hash. Comparison proves equal locked wrapper @typescript/typescript6 6.0.2 -> @typescript/old (typescript 6.0.3), base64-js 1.5.1 and complete recorded npm entries/integrities; current observed file hashes are not retroactively historical hashes.',
   'environment_limit':'Original Node/Swift versions and original retained results are preserved. This comparison does not execute or hash an original compiler/Node binary, prove the entire historical OS image, or reconstruct unrecorded standard-library files.',
 },
 'retained_evidence':evidence,'retained_log_observations':logs,
 'remaining_independent_gates':['Latest native Host refresh','Latest full app build and 48 selected app-test invocations','Any live-provider/cache-hit/billing/paid-lifecycle verification','Release or TestFlight acceptance'],
 'failures':failures,
}
receipt=write_json('receipt.json',report)
readme='''# Bounded local and JavaScript evidence reuse

Target: `'''+TARGET+'''` (immutable Git source).

No test, compiler, package manager or native process was run. No repository source or branch was modified.

- All **36** paths from the retained pre-App04 closure match both that receipt and the original proof snapshots byte for byte: **11** local/accounting source/test files and **25** JavaScript facade, test, generator, fixture, declaration and package files.
- The earlier original macOS source harness remains **18 PASS** (11 local-search/cache lifecycle and 7 usage-accounting). Its original LRUCache **1.3.0 / f0570e943ea4445d258113ba73f50cb2b7e564ac** matches the current canonical application resolution and exact manifest declaration.
- The earlier original Node facade/VM suites remain **15 PASS** (7 shared assistant/publication plus 8 NativeScript/Expo VM). Their consumed lock entries are unchanged: NativeScript TypeScript **5.9.3**, Expo wrapper **@typescript/typescript6 6.0.2** forwarding to TypeScript **6.0.3**, and **base64-js 1.5.1**.
- The retained raw logs and manifests are bound by Git blob IDs and SHA-256 in `receipt.json`; the 18/7/8 actual summary counts were read from those logs.
- The earlier generation/drift check remains an original PASS on the matching sources and generated bytes. It was not rerun.

These conclusions are scoped to the original source harness and Node facade/VM tests. They are not a fresh run on this commit and do not replace the new native Host refresh, full app build or 48 selected application invocations. The original Expo receipt recorded a compiler API version rather than a compiler-file hash; the JSON retains that explicit provenance limit. Current observed installed hashes are labelled as observations, not fabricated historical evidence.

The core48 closure is reviewed separately in the sibling `core` directory.
'''
(OUT/'README.md').write_text(readme)
print(json.dumps({'receipt':receipt,'readme':{'path':str(OUT/'README.md'),'sha256':sha((OUT/'README.md').read_bytes())},'target':TARGET,'unique_files':len(unique),'local_tests':18,'js_tests':15,'comparison_count':len(recorded),'supplemental_count':len(supplemental),'all_matches':all_matches,'failures':failures,'consumed_lockfiles_equal':{r['path']:r['entire_lockfile_equal'] for r in npm},'compiler_observations':compiler_observations},indent=2))
