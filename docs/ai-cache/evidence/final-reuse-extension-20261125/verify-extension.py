#!/usr/bin/env python3
"""Extend retained evidence by reading immutable Git inputs; never run tests/builds/resolution."""
from pathlib import Path
import datetime,gzip,hashlib,json,subprocess

REPO='/mnt/development/projects/worktrees/hanlin-ai-cache-integration-20261125'
BASE='6fbcf703dd9f40f5b1d42592d58a0a69573dcdfa'
TARGET='948bdb1fe75d31559dc8d65ae8d2e70fa69de276'
PREVIOUS=Path('/mnt/development/projects/artifacts/hanlin-ai-cache-final-reuse-20261125')
OUT=Path('/mnt/development/projects/artifacts/hanlin-ai-cache-final-reuse-extension-20261125')
PROOF='docs/ai-cache/evidence/standalone-lock-resolution-20261125/'
APP_LOCK='AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
OUT.mkdir(parents=True,exist_ok=True)

def digest(raw):return hashlib.sha256(raw).hexdigest()
def git(*args,repo=REPO):
    return subprocess.check_output(['git','-c','safe.directory='+repo,'-C',repo,*args])
def data(rev,path):return git('show',rev+':'+path)
def doc(rev,path):return json.loads(data(rev,path))
def tree(rev):return git('rev-parse',rev+'^{tree}').decode().strip()
def identity(rev,path):
    b=data(rev,path)
    return {'path':path,'source':rev,'sha256':digest(b),'git_blob':git('rev-parse',rev+':'+path).decode().strip(),'bytes':len(b)}
def local_ref(path):
    b=path.read_bytes()
    return {'path':str(path),'sha256':digest(b),'bytes':len(b)}

previous_index_bytes=(PREVIOUS/'index.json').read_bytes()
previous_index=json.loads(previous_index_bytes)
immutable=[]
for row in previous_index['files']:
    p=PREVIOUS/row['path'];b=p.read_bytes()
    assert digest(b)==row['sha256'] and len(b)==row['bytes'],p
    immutable.append({'path':row['path'],'sha256':digest(b),'bytes':len(b),'matches_previous_index':True})
core=json.loads((PREVIOUS/'core/core48-reuse.json').read_text())
local=json.loads((PREVIOUS/'local-js/receipt.json').read_text())
assert core['target_source']['commit']==local['target_commit']==BASE
core_rows=[]
for row in core['canonical_input_closure']['inputs']:
    path=row['path'];a=data(BASE,path);b=data(TARGET,path)
    match=a==b and digest(b)==row['recorded_sha256']
    assert match,path
    core_rows.append({'path':path,'original_recorded_sha256':row['recorded_sha256'],
                      'base_sha256':digest(a),'target_sha256':digest(b),'identical':match})
assert len(core_rows)==80
members=[]
for old in core['canonical_input_closure']['directory_membership']:
    path=old['path']
    a=git('ls-tree','-r','--name-only',BASE,'--',path).decode().splitlines()
    b=git('ls-tree','-r','--name-only',TARGET,'--',path).decode().splitlines()
    assert a==b and len(b)==old['recorded_count'],path
    members.append({'target':old['target'],'path':path,'original_recorded_count':old['recorded_count'],
                    'base_count':len(a),'target_count':len(b),'added':sorted(set(b)-set(a)),
                    'removed':sorted(set(a)-set(b))})
helpers=[]
for row in core['runner_and_generator']:
    path=row['path'];a=data(BASE,path);b=data(TARGET,path)
    assert a==b and digest(b)==row['original_sha256'],path
    helpers.append({'path':path,'sha256':digest(b),'byte_identical':True})
local_rows=[]
for row in local['checkpoint_comparisons']:
    path=row['path'];a=data(BASE,path);b=data(TARGET,path)
    assert a==b and digest(b)==row['target_sha256'],path
    local_rows.append({'path':path,'previous_verified_sha256':row['target_sha256'],
                       'base_sha256':digest(a),'target_sha256':digest(b),'byte_identical':True})
assert len(local_rows)==36

canonical_bytes=data(TARGET,APP_LOCK)
canonical=doc(TARGET,APP_LOCK)
app_pins={p['identity']:p for p in canonical['pins']}
assert canonical_bytes==data(BASE,APP_LOCK)
consumed_core_pins=core['proof_graph']['resolved_pins']
assert all(app_pins[p['identity']]==p for p in consumed_core_pins)
lru=local['local_cache_accounting']['original_lru_pin']
assert app_pins['lrucache']==lru
npm=[]
for lock in local['dependencies']['consumed_npm_lock_entries']:
    path=lock['path'];current=doc(TARGET,path)
    entries=[]
    for entry in lock['consumed_entries']:
        actual=current['packages'][entry['package']]
        assert actual==entry['original_entry']==entry['target_entry'],entry['package']
        entries.append({'package':entry['package'],'actual_entry':actual,'matches_original_and_previous':True})
    npm.append({'path':path,'base_sha256':digest(data(BASE,path)),'target_sha256':digest(data(TARGET,path)),
                'whole_file_unchanged_since_previous_review':data(BASE,path)==data(TARGET,path),
                'consumed_entries':entries})

historical_evidence=[]
for row in core['proof_graph']['retained_evidence']+local['retained_evidence']:
    path=row['path'];b=data(TARGET,path)
    assert digest(b)==row['sha256'] and b==data(BASE,path),path
    historical_evidence.append(identity(TARGET,path))
producer=core['producer_fixtures']
assert digest(data(TARGET,producer['publication_receipt_path']))==producer['publication_receipt_sha256']
producer_rows=[]
for row in producer['fixtures']:
    b=git('show',producer['local_commit']+':'+row['path'],repo=producer['repository'])
    assert digest(b)==row['recorded_sha256'],row['path']
    producer_rows.append({'path':row['path'],'sha256':digest(b),'matches_historical_fixture':True})
assert git('rev-parse',producer['local_commit']+'^{tree}',repo=producer['repository']).decode().strip()==producer['local_tree']

resolution_receipt=doc(TARGET,PROOF+'receipt.json')
resolution_summary=doc(TARGET,PROOF+'original/summary.json')
resolution=doc(TARGET,PROOF+'original/resolution.json')
resolution_inputs=doc(TARGET,PROOF+'original/input-sha256.json')
storage=doc(TARGET,PROOF+'storage-index.json')
resolution_source=resolution_receipt['sourceSHA']
assert resolution_receipt['status']==resolution_summary['status']=='RESOLUTION_PASS'
assert resolution_receipt['exitCode']==0
assert resolution_receipt['sourceSHAAfter']==resolution_source and resolution_receipt['trackedStatusAfter']==''
assert resolution_summary==resolution_receipt['originalSummary']
assert resolution_summary['graphs']==len(resolution)==6
assert resolution_summary['builds']==resolution_summary['tests']==0
assert resolution_summary['unrelated_pins_changed'] is False
assert data(TARGET,PROOF+'original/source-commit.txt').decode().strip()==resolution_source
assert data(TARGET,PROOF+'original/canonical-app-Package.resolved')==canonical_bytes
assert digest(canonical_bytes)==resolution_summary['canonical_app_lock_sha256']
assert data(resolution_source,APP_LOCK)==canonical_bytes

storage_checks=[]
for row in storage['files']:
    path=PROOF+row['storedPath'];stored=data(TARGET,path)
    raw=gzip.decompress(stored) if path.endswith('.gz') else stored
    assert digest(stored)==row['storedSHA256'] and digest(raw)==row['originalSHA256'],path
    storage_checks.append({'path':path,'stored_sha256':digest(stored),'raw_sha256':digest(raw),
                           'stored_and_decompressed_hashes_match':True})
outer_raw=gzip.decompress(data(TARGET,PROOF+'original-resolution.log.gz'))
assert digest(outer_raw)==resolution_receipt['logSHA256']
subprocess.run(['git','-c','safe.directory='+REPO,'-C',REPO,'merge-base','--is-ancestor',storage['generatedCommit'],TARGET],check=True)

six=[]
for row in resolution:
    path=row['source_path'];current=data(TARGET,path);retained=data(TARGET,PROOF+'original/'+row['raw_file'])
    assert current==retained and digest(current)==row['sha256'],path
    after={p['identity']:p for p in json.loads(current)['pins']}
    before={p['identity']:p for p in doc(BASE,path)['pins']}
    added=sorted(set(after)-set(before));removed=sorted(set(before)-set(after))
    old_unchanged=all(before[k]==after[k] for k in before)
    assert added==['opentelemetry-swift-core','swift-atomics'] and not removed and old_unchanged,path
    assert row['previously_unlocked_existing_dependencies']==added
    assert all(after[p['identity']]==p for p in consumed_core_pins),path
    manifest=path.rsplit('/',1)[0]+'/Package.swift'
    mb=data(TARGET,manifest)
    assert digest(mb)==resolution_inputs[manifest] and mb==data(resolution_source,manifest),manifest
    six.append({'path':path,'sha256':digest(current),'retained_original_path':PROOF+'original/'+row['raw_file'],
                'equals_original_generated_bytes':True,'added_since_previous_review':added,
                'removed_since_previous_review':removed,'all_previous_pins_unchanged':old_unchanged,
                'all_four_core_proof_pins_match':True,'manifest_matches_actual_resolution_input':True})
for path in ['Scripts/CI/IntegrationValidation/resolve_agent_sdk_locks.sh',
             'Scripts/CI/IntegrationValidation/swift_ai_sdk_pin.py',APP_LOCK]:
    assert digest(data(TARGET,path))==resolution_inputs[path],path
    assert data(TARGET,path)==data(resolution_source,path),path

report={
 'schema_version':1,'kind':'READ_ONLY_EXTENSION_OF_BOUNDED_EVIDENCE_REUSE',
 'generated_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'base_source':{'commit':BASE,'tree':tree(BASE)},
 'target_source':{'commit':TARGET,'tree':tree(TARGET)},
 'assessment':'UNCHANGED_CORE_AND_LOCAL_JS_INPUTS_WITH_ORIGINAL_STANDALONE_LOCK_GAP_RESOLVED',
 'new_test_execution':False,'new_build_execution':False,'new_package_resolution':False,
 'native_operations':False,'repository_files_or_refs_modified':False,
 'historical_reuse_files_modified':False,
 'previous_evidence':{
   'index':local_ref(PREVIOUS/'index.json'),'receipt':local_ref(PREVIOUS/'reuse-receipt.json'),
   'core':local_ref(PREVIOUS/'core/core48-reuse.json'),'local_js':local_ref(PREVIOUS/'local-js/receipt.json'),
   'all_nine_indexed_files_still_exact':immutable,
 },
 'retained_results':{
   'core':{'source':core['original_source']['commit'],'passed':44,'producer_passed':4,
           'status':'REUSED_VERIFIED_PASS','raw_log_sha256':core['historical_execution']['raw_log_sha256']},
   'local_accounting':{'source':local['local_cache_accounting']['original_source'],'passed':18,'status':'REUSED_VERIFIED_PASS'},
   'active_js':{'implementation_source':local['active_assistant_javascript']['original_implementation_source'],
                'generated_source':local['active_assistant_javascript']['original_generated_and_harness_source'],
                'passed':15,'status':'REUSED_VERIFIED_PASS'},
 },
 'core_closure':{'canonical_files':core_rows,'canonical_count':80,'complete_directory_membership':members,
                 'runner_and_generator':helpers,'original_producer_fixtures':producer_rows,
                 'published_producer':producer['published_commit'],'published_producer_tree':producer['local_tree']},
 'local_js_closure':{'unique_files':local_rows,'unique_count':36,'local_source_test_count':11,'javascript_source_fixture_count':25},
 'consumed_dependencies':{
   'canonical_app_lock':identity(TARGET,APP_LOCK),'whole_canonical_app_lock_unchanged_since_base':True,
   'core_proof_pins':consumed_core_pins,'core_pins_all_match_current_canonical_app_lock':True,
   'local_lru_pin':lru,'local_lru_matches_current_canonical_app_lock':True,
   'consumed_npm_entries':npm,
 },
 'actual_standalone_resolution':{
   'status':'EXECUTED_RESOLUTION_PASS_BY_ROOT','source':resolution_source,
   'generated_commit':storage['generatedCommit'],'generated_commit_is_ancestor_of_target':True,
   'started_at_utc':resolution_receipt['startedAtUTC'],'finished_at_utc':resolution_receipt['finishedAtUTC'],
   'command':resolution_receipt['command'],'developer_directory':resolution_receipt['developerDirectory'],
   'exit_code':0,'graphs':6,'builds':0,'tests':0,
   'receipt':identity(TARGET,PROOF+'receipt.json'),'storage_index':identity(TARGET,PROOF+'storage-index.json'),
   'raw_log_sha256':digest(outer_raw),'storage_verification':storage_checks,'locks':six,
   'all_four_core_proof_pins_match_each_actual_standalone_graph':True,
   'old_pin_drift':False,'canonical_app_lock_drift':False,
 },
 'prior_qualification_update':{
   'historical_statement':'At6fbc the standalone HanlinPlatform lock omitted OTel/Atomics; it was not the consumed core proof lock.',
   'current_statement':'Resolved at948 by the original Apple six-graph producer: all six checked-in locks equal its retained generated bytes and contain the exact canonical OTel2.6.0 and Atomics1.3.1 pins. All four consumed core proof pins now match both the current app lock and every one of these six standalone locks.',
   'scope':'This closes the specific standalone lock completeness gap. It does not claim every repository lock has an identical dependency graph or that resolution is a compile/test.',
   'historical_files_preserved':True,
 },
 'unchanged_historical_evidence_files':historical_evidence,
 'remaining_limits':[
  'No tests executed at948 during this review; original48core/producer,18local/accounting and15JS results are reused only for their unchanged bounded inputs.',
  'All original complete core target membership and recorded source hashes are verified, but a per-file attestation of every historical transitive checkout, compiler/SDK binary, intermediate and OS environment was not retained and is not invented here.',
  'The original Expo VM proof recorded TypeScript API6.0.3, not historical compiler/codec file hashes. Equal locked entries/integrities preserve the previously documented provenance boundary.',
  'Original standalone resolution executed no builds or tests. The separate App07 and current Host acceptance remain root-owned independent gates.',
  'Live provider cache hits, billing savings, paid explicit cache lifecycle and release acceptance are not established by these source or lock comparisons.',
 ],
}
(OUT/'reuse-extension.json').write_text(json.dumps(report,indent=2,sort_keys=True,ensure_ascii=False)+'\n')
assert (PREVIOUS/'index.json').read_bytes()==previous_index_bytes
for row in previous_index['files']:
    assert digest((PREVIOUS/row['path']).read_bytes())==row['sha256']
print(json.dumps({'target':TARGET,'core_files':len(core_rows),'local_js_files':len(local_rows),
                  'core_directory_counts':{m['target']:m['target_count'] for m in members},
                  'six_original_locks_exact':len(six),'core_proof_pins_match_each':True,
                  'old_pin_drift':False,'canonical_app_lock_unchanged':True,
                  'npm_whole_locks_unchanged_from6f':{r['path']:r['whole_file_unchanged_since_previous_review'] for r in npm},
                  'prior_lock_qualification':'RESOLVED_BY_ACTUAL_ORIGINAL_APPLE_PRODUCER',
                  'historical_files_unchanged':True,'new_tests_builds_resolves':False,
                  'receipt':str(OUT/'reuse-extension.json'),'receipt_sha256':digest((OUT/'reuse-extension.json').read_bytes())},indent=2))
