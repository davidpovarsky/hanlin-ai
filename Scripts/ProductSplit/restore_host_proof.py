"""Restore an authenticated, unchanged Host archive; never reuse iOS/UI acceptance."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(os.environ['SPLIT_EVIDENCE'])


def output(*arguments):
    return subprocess.check_output(arguments, cwd=ROOT, text=True)


def summary(raw):
    return {key: int(value) for key, value in re.findall(
        r'(?m)^ℹ (tests|pass|fail|skipped) (\d+)\s*$', raw)}


def restore(run_id):
    repository = os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[1-9][0-9]*', run_id):
        raise ValueError('Invalid origin run ID')
    run = json.loads(output('gh', 'api', f'repos/{repository}/actions/runs/{run_id}'))
    if run['status'] != 'completed' or run['head_repository']['full_name'] != repository:
        raise ValueError('Origin must be a completed same-repository run')
    jobs = json.loads(output('gh', 'api', f'repos/{repository}/actions/runs/{run_id}/jobs?per_page=100'))['jobs']
    matching_jobs = [j for j in jobs if j['name'] == 'miniapps' or j['name'].endswith('/ miniapps')]
    if len(matching_jobs) != 1:
        raise ValueError('Original standalone Host job is missing or ambiguous')
    job = matching_jobs[0]
    steps = {s['name']: s['conclusion'] for s in job['steps']}
    for name in ['Verify actual Mac toolchain, disk and installed simulator tooling',
                 'Reproduce and verify affected package lifecycle on the actual Mac first',
                 'Prepare existing native dependencies and Runtime host']:
        if steps.get(name) != 'success':
            raise ValueError('Original Host prerequisite did not pass: '+name)
    artifacts = json.loads(output('gh', 'api', f'repos/{repository}/actions/runs/{run_id}/artifacts'))['artifacts']
    matches = [a for a in artifacts if a['name'] == 'app-split-'+run_id and not a['expired']]
    if len(matches) != 1:
        raise ValueError('Missing unique live original proof artifact')
    artifact = matches[0]
    with tempfile.TemporaryDirectory(prefix='hanlin-host-proof-', dir=os.environ['RUNNER_TEMP']) as temp:
        temp = Path(temp)
        archive = temp/'origin.zip'
        with archive.open('wb') as stream:
            subprocess.run(['gh','api',f'repos/{repository}/actions/artifacts/{artifact["id"]}/zip'],
                           cwd=ROOT, stdout=stream, check=True)
        digest = 'sha256:'+hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != artifact.get('digest'):
            raise ValueError('Original artifact outer checksum mismatch')
        host = temp/'host'
        host.mkdir()
        raw = {}
        with zipfile.ZipFile(archive) as packed:
            # Read only fixed known members: never extract arbitrary archive paths.
            for name in ['RuntimeHostResources.zip','host-metadata.json','runtime-host.sha256']:
                entry = packed.getinfo('runtime-host/'+name)
                if entry.file_size > 200_000_000:
                    raise ValueError('Oversized original Host artifact')
                (host/name).write_bytes(packed.read(entry))
            for name in ['preflight.log','package-lifecycle.log','native-dependencies.log']:
                raw[name] = packed.read('app-split-evidence/'+name).decode()
        current = output('sw_vers')+output('uname','-m')+output('xcodebuild','-version')
        if not ' '.join(raw['preflight.log'].split()).startswith(' '.join(current.split())+' '):
            raise ValueError('Mac OS/architecture/Xcode fingerprint changed')
        focused, complete = summary(raw['package-lifecycle.log']), summary(raw['native-dependencies.log'])
        if focused != {'tests':7,'pass':7,'fail':0,'skipped':0} or complete != {'tests':153,'pass':152,'fail':0,'skipped':1}:
            raise ValueError('Original exact Host case counts changed or were incomplete')
        fingerprint = output('node','-p','JSON.stringify({versions:process.versions,platform:process.platform,arch:process.arch})').strip()
        subprocess.run(['python3','Scripts/Runtime/runtime_host_archive.py','reuse',str(host),
                        '--node-fingerprint',fingerprint],cwd=ROOT,check=True)
        # The existing verifier checks every Host/test/fixture/build input,
        # complete Node fingerprint, archive checksum and actual packed modules.
        destination = ROOT/'build/runtime-host'
        destination.mkdir(parents=True,exist_ok=True)
        for source in host.iterdir():
            target = destination/source.name
            if target.exists() and target.read_bytes() != source.read_bytes():
                raise ValueError('Existing prepared Host output differs; kept original files')
        for source in host.iterdir():
            shutil.copy2(source,destination/source.name)
        proof = EVIDENCE/'reused-host-origin'/run_id
        proof.mkdir(parents=True,exist_ok=True)
        for name, text in raw.items():
            (proof/name).write_text(text)
        return {'status':'REUSED_VERIFIED_PASS','origin_run':run_id,'origin_sha':run['head_sha'],
                'origin_job':job['id'],'artifact_id':artifact['id'],'artifact_sha256':digest,
                'focused':focused,'host':complete,'scope':'Host prerequisites/archive only; UI NOT_RUN',
                'host_metadata':json.loads((host/'host-metadata.json').read_text())}



def foreground_inputs():
    """Mirror the authenticated runner's actual foreground source closure."""
    contracts = sorted(p for p in (ROOT/'Packages/HanlinPlatform/Sources/HanlinPlatformContracts').glob('*.swift')
                       if p.name != 'HanlinManifestSchema.swift')
    core = ROOT/'Packages/HanlinPlatform/Sources/HanlinMiniAppCore'
    split = sorted((ROOT/'Packages/HanlinProductSplit/Sources/HanlinProductSplit').glob('*.swift'))
    return contracts + [core/'HanlinMiniAppRequestBroker.swift', core/'HanlinCanonicalMiniAppCatalog.swift'] + split + [
        ROOT/'Packages/HanlinProductSplit/Tests/ForegroundSchemeTests.swift']


def file_record(path):
    path = Path(path)
    return {'path':str(path),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def validate_foreground(packed, origin_sha, platform, toolchain, compiler_tools):
    """Verify the original native execution, all current inputs, and raw lineage."""
    prefix = 'app-split-evidence/foreground/'
    def member(name):
        entries = [entry for entry in packed.infolist() if entry.filename == name]
        if len(entries) != 1 or entries[0].file_size > 20_000_000:
            raise ValueError('Missing, duplicate, or oversized foreground proof member: '+name)
        return packed.read(entries[0])

    report_bytes = member(prefix+'foreground-results.json')
    report = json.loads(report_bytes)
    if (report.get('status') != 'EXECUTED_PASS' or report.get('count') != 53
            or report.get('commit_base_at_execution') != origin_sha):
        raise ValueError('Original foreground53 report is incomplete or has the wrong source')
    preflight = member('app-split-evidence/preflight.log')
    if not ' '.join(preflight.decode().split()).startswith(' '.join(platform.split())+' '):
        raise ValueError('Foreground Mac OS/architecture/Xcode fingerprint changed')
    if report['toolchain'] != toolchain.strip() or report['compiler_tools'] != compiler_tools:
        raise ValueError('Foreground Swift version or actual compiler fingerprint changed')
    expected = {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                for p in foreground_inputs()}
    if len(expected) != 35 or report.get('source_sha256') != expected:
        raise ValueError('Foreground source/test closure or content changed')
    binaries = report.get('binaries', [])
    if len(binaries) != 1 or binaries[0].get('group') != 'foreground':
        raise ValueError('Missing unique original foreground binary lineage')
    binary = binaries[0]
    origin_root = Path(binary['compile_event']['cwd'])
    def relative(record):
        return Path(record['path']).relative_to(origin_root).as_posix()
    runners = report.get('runner_sources', [])
    runner_names = ['Scripts/ProductSplit/run_portable.py','Scripts/ProductSplit/provenance.py']
    if len(runners) != 2 or {relative(r) for r in runners} != set(runner_names):
        raise ValueError('Foreground runner/provenance source closure changed')
    for record in runners:
        current = file_record(ROOT/relative(record))
        if (current['bytes'],current['sha256']) != (record['bytes'],record['sha256']):
            raise ValueError('Foreground runner/provenance content changed')

    manifest_record = report['raw_evidence_manifest']
    raw_root = Path(manifest_record['path']).parent
    def checked(data, record):
        if len(data) != record['bytes'] or hashlib.sha256(data).hexdigest() != record['sha256']:
            raise ValueError('Original raw foreground proof checksum mismatch: '+record['path'])
        return data
    manifest_bytes = checked(member(prefix+'raw-origin/manifest.json'), manifest_record)
    manifest = json.loads(manifest_bytes)
    records = {}
    payload = {'foreground-results.json':report_bytes,'raw-origin/manifest.json':manifest_bytes}
    for record in manifest['files']:
        path = Path(record['path'])
        if path.parent != raw_root or path.name in records or path.name in ('','..'):
            raise ValueError('Ambiguous or escaped foreground raw manifest')
        records[path.name] = record
        payload['raw-origin/'+path.name] = checked(member(prefix+'raw-origin/'+path.name),record)
    def raw_record(record):
        name = Path(record['path']).name
        if records.get(name) != record:
            raise ValueError('Raw foreground lineage reference is absent from the manifest')
        return payload['raw-origin/'+name]
    def raw_json(name):
        if name not in records:
            raise ValueError('Missing original foreground lineage: '+name)
        return json.loads(payload['raw-origin/'+name])

    trace = [json.loads(line) for line in payload['raw-origin/commands.jsonl'].decode().splitlines()]
    invocations = [e for e in trace if e['kind'] == 'invocation']
    if len(invocations) != 1 or invocations[0].get('suite') != 'foreground':
        raise ValueError('Original trace is not a single foreground invocation')
    starts = [e for e in trace if e['kind'] == 'start']
    completed = [e for e in trace if e['kind'] == 'completed']
    labels = ['toolchain','compile-contracts','compile-core','link-foreground','tests-foreground','commit-base','working-tree']
    if [e['label'] for e in starts] != labels or len(completed) != len(labels):
        raise ValueError('Original foreground trace is incomplete')
    events = {}
    for start,event in zip(starts,completed):
        if event.get('exit_code') != 0 or event['argv'] != start['argv'] or event['cwd'] != str(origin_root):
            raise ValueError('Original foreground command failed or its trace changed')
        raw_record(event['stdout']); raw_record(event['stderr'])
        events[start['label']] = event
    def event_matches(actual, recorded):
        return {k:v for k,v in actual.items() if k != 'utc'} == recorded
    raw_result = json.loads(raw_record(events['tests-foreground']['stdout']))
    if (raw_result.get('status') != 'EXECUTED_PASS' or raw_result.get('count') != 53
            or len(raw_result.get('tests',[])) != 53 or len(set(raw_result['tests'])) != 53
            or report.get('groups') != [{**raw_result,'group':'foreground'}]
            or raw_record(events['tests-foreground']['stderr'])):
        raise ValueError('Actual original foreground test output does not prove 53 unique passes')
    if (raw_record(events['commit-base']['stdout']).decode().strip() != origin_sha
            or raw_record(events['toolchain']['stdout']).decode().strip() != report['toolchain']):
        raise ValueError('Original native source/toolchain trace disagrees with its report')

    linked = []
    canonical_sources = {}
    for name,key in [('contracts','contracts'),('core','catalog_request')]:
        entry = report['canonical_provenance'][key]
        if entry['status'] != 'FRESH_COMPILED_RECORDED_LINEAGE':
            raise ValueError('Foreground reuse requires the original fresh native canonical lineage')
        proof = json.loads(raw_record(entry['provenance']))
        descriptor = proof['inputs']
        if (proof['outputs'] != entry['outputs']
                or descriptor['compiler'] != compiler_tools[0]
                or descriptor['toolchain'].strip() != report['toolchain']
                or descriptor['dependency_outputs'] != compiler_tools+linked
                or not event_matches(events['compile-'+name],proof['compile_event'])):
            raise ValueError('Original canonical compiler/output lineage is inconsistent')
        for log in proof['origin_logs']:
            raw_record(log)
        for record in descriptor['sources']:
            path = relative(record)
            if path in canonical_sources:
                raise ValueError('Duplicate canonical source in foreground lineage')
            canonical_sources[path] = record['sha256']
        linked += proof['outputs']
    original_binary = raw_json('foreground-binary-provenance.json')
    if (original_binary != binary or binary['linked_canonical_outputs'] != linked
            or binary['compiler_tools'] != compiler_tools
            or not event_matches(events['link-foreground'],binary['compile_event'])
            or events['tests-foreground']['argv'][0] != binary['binary']['path']
            or len(events['tests-foreground']['argv']) != 2):
        raise ValueError('Original linked foreground binary does not match the executed test')
    compiled_sources = dict(canonical_sources)
    for record in binary['source_inputs']:
        path = relative(record)
        if path in compiled_sources:
            raise ValueError('Duplicate compiled source in foreground lineage')
        compiled_sources[path] = record['sha256']
    if compiled_sources != expected:
        raise ValueError('Compiled foreground source closure disagrees with current source')
    return report, payload, preflight


def restore_foreground(run_id):
    repository = os.environ['GITHUB_REPOSITORY']
    if not re.fullmatch(r'[1-9][0-9]*',run_id):
        raise ValueError('Invalid foreground origin run ID')
    run = json.loads(output('gh','api',f'repos/{repository}/actions/runs/{run_id}'))
    if (run['status'] != 'completed' or run['head_repository']['full_name'] != repository
            or run['path'] != '.github/workflows/validate-app-split.yml'):
        raise ValueError('Foreground origin must be a completed original same-repository workflow')
    jobs = json.loads(output('gh','api',f'repos/{repository}/actions/runs/{run_id}/jobs?per_page=100'))['jobs']
    matching = [j for j in jobs if j['name'] == 'miniapps' or j['name'].endswith('/ miniapps')]
    if len(matching) != 1:
        raise ValueError('Missing unique original native foreground job')
    job = matching[0]
    steps = {s['name']:s['conclusion'] for s in job['steps']}
    for name in ['Verify actual Mac toolchain, disk and installed simulator tooling',
                 'Execute strict foreground route and ledger cases on the actual Mac']:
        if steps.get(name) != 'success':
            raise ValueError('Original foreground prerequisite did not pass: '+name)
    artifacts = json.loads(output('gh','api',f'repos/{repository}/actions/runs/{run_id}/artifacts'))['artifacts']
    matching = [a for a in artifacts if a['name'] == 'app-split-'+run_id and not a['expired']]
    if len(matching) != 1:
        raise ValueError('Missing unique live original foreground artifact')
    artifact = matching[0]
    with tempfile.TemporaryDirectory(prefix='hanlin-foreground-proof-',dir=os.environ['RUNNER_TEMP']) as temp:
        archive = Path(temp)/'origin.zip'
        with archive.open('wb') as stream:
            subprocess.run(['gh','api',f'repos/{repository}/actions/artifacts/{artifact["id"]}/zip'],
                           cwd=ROOT,stdout=stream,check=True)
        digest = 'sha256:'+hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != artifact.get('digest') or archive.stat().st_size != artifact['size_in_bytes']:
            raise ValueError('Original foreground artifact checksum or size mismatch')
        compiler = shutil.which('swiftc')
        if not compiler:
            raise ValueError('Native Swift compiler is unavailable')
        frontend = Path(compiler).with_name('swift-frontend')
        compiler_tools = [file_record(compiler)]+([file_record(frontend)] if frontend.exists() else [])
        platform = output('sw_vers')+output('uname','-m')+output('xcodebuild','-version')
        toolchain = output(compiler,'--version')
        with zipfile.ZipFile(archive) as packed:
            report,payload,preflight = validate_foreground(packed,run['head_sha'],platform,toolchain,compiler_tools)
        destination = EVIDENCE/'foreground'
        if destination.exists():
            raise ValueError('Existing foreground proof preserved; refusing to replace it')
        # Stage only authenticated, fixed-prefix proof bytes; no binary is restored or executed.
        with tempfile.TemporaryDirectory(prefix='.foreground-proof-',dir=EVIDENCE) as staging:
            staged = Path(staging)/'foreground'
            for name,data in payload.items():
                target = staged/name
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(data)
            (staged/'origin-preflight.log').write_bytes(preflight)
            staged.rename(destination)
        return {'status':'REUSED_VERIFIED_PASS','origin_run':run_id,'origin_sha':run['head_sha'],
                'current_sha':output('git','rev-parse','HEAD').strip(),'origin_job':job['id'],
                'artifact_id':artifact['id'],'artifact_sha256':digest,'count':53,'source_files':35,
                'runner_sources':2,'toolchain':report['toolchain'],
                'scope':'Original native foreground prerequisites only; both products still build and paired UI NOT_RUN'}



def main():
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    run_id = os.environ.get('HOST_PROOF_RUN_ID','')
    result = {'status':'NOT_REQUESTED','scope':'Host prerequisites only'}
    reused = False
    if run_id:
        try:
            result = restore(run_id)
            reused = True
        except Exception as error:
            result = {'status':'INVALIDATED','origin_run':run_id,
                      'reason':str(error),'next':'Execute actual affected Host prerequisites'}
    (EVIDENCE/'host-reuse.json').write_text(json.dumps(result,indent=2)+'\n')
    with open(os.environ['GITHUB_OUTPUT'],'a') as stream:
        stream.write('reused='+str(reused).lower()+'\n')
    print(json.dumps(result))
    # The standalone workflow exposes the shared Host proof input while its
    # separate foreground input is wired only for the paired lane. Reuse the
    # same explicitly supplied origin through the full existing 53-case
    # source/toolchain/receipt verifier; an invalid origin still executes tests.
    foreground_id = os.environ.get('FOREGROUND_PROOF_RUN_ID','') or run_id
    foreground = {'status':'NOT_REQUESTED','scope':'Native foreground prerequisites only'}
    foreground_reused = False
    if foreground_id:
        try:
            foreground = restore_foreground(foreground_id)
            foreground_reused = True
        except Exception as error:
            foreground = {'status':'INVALIDATED','origin_run':foreground_id,
                          'reason':str(error),'next':'Execute actual foreground53 prerequisites'}
    (EVIDENCE/'foreground-reuse.json').write_text(json.dumps(foreground,indent=2)+'\n')
    with open(os.environ['GITHUB_OUTPUT'],'a') as stream:
        stream.write('foreground_reused='+str(foreground_reused).lower()+'\n')
    print(json.dumps(foreground))


if __name__ == '__main__':
    main()
