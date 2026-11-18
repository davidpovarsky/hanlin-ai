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


if __name__ == '__main__':
    main()
