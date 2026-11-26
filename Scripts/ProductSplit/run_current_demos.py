#!/usr/bin/env python3
"""Rebuild nine owned demo copies using one authenticated original SDK export."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import signal
import stat
import subprocess
import threading
import time
import traceback
import zipfile

REPOSITORY = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / 'Acceptance/Demos'
BASELINE_SHA256 = 'd61d8d2d41ceb7714b5c4f7b213a480e94c9742faa395f38609eb54b76500c35'
PREPARATION_SHA256 = 'b4f44056d95e3ec93537102ead7bf3570d4af7a72cd725f068cd18741044ec49'
TOOL_SOURCE = '462fe5c579e3fb3d6c394c8fd368faca8792bc6e'
ROOT = SDK = E = NODE = CLI = None


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def ref(path):
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}


def write_new(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def safe_path(value):
    p = PurePosixPath(value)
    if p.is_absolute() or '..' in p.parts or p.as_posix() != value:
        raise ValueError('Unexpected archive path: ' + value)
    return p


def verify_sdk(manifest):
    for row in manifest['files']:
        p = SDK / row['path']
        if p.stat().st_size != row['bytes'] or sha(p) != row['sha256']:
            raise ValueError('SDK payload differs: ' + row['path'])
    expected = {row['path'] for row in manifest['files']} | {'miniapp-sdk.json'}
    actual = {p.relative_to(SDK).as_posix() for p in SDK.rglob('*') if p.is_file()}
    if actual != expected:
        raise ValueError('SDK member set differs')


def main(argv=None):
    global ROOT, SDK, E, NODE, CLI
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', type=Path, default=REPOSITORY)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--producer-receipt', type=Path, required=True)
    args = parser.parse_args(argv)
    repository = args.repository.resolve()
    ROOT = args.output.resolve()
    ROOT.mkdir(parents=True, exist_ok=False)
    E, SDK = ROOT / 'evidence', ROOT / 'MiniAppSDK'
    for directory in (E, ROOT / 'projects', ROOT / 'artifacts', ROOT / 'temporary'):
        directory.mkdir()
    executable = shutil.which('node')
    if not executable:
        parser.error('The original Node 24.5.0 interpreter is required')
    NODE = Path(executable).resolve()
    CLI = repository / 'Scripts/MiniApps/miniapp.mjs'
    args.producer_state = args.producer_receipt
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=repository, text=True).strip()
    if len(source) != 40 or any(c not in '0123456789abcdef' for c in source):
        parser.error('An exact SDK producer Git SHA is required')
    began = time.monotonic()
    state = {'schema': 1, 'status': 'PREPARING', 'startedAt': now(), 'source': source,
             'nativeExecution': 'NOT_RUN', 'commands': [], 'errors': []}
    lock = threading.Lock()
    stop = threading.Event()

    def save():
        temporary = ROOT / 'state.next.json'
        temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2) + '\n')
        temporary.replace(ROOT / 'state.json')

    save()
    try:
        producer = json.loads(args.producer_state.read_text())
        assert producer['status'] == 'VERIFIED_HOST_SDK' and producer['sourceCommit'] == source
        assert producer['longJobs'] is True
        node_fingerprint = json.loads(subprocess.check_output([
            str(NODE), '-p', 'JSON.stringify({versions:process.versions,platform:process.platform,arch:process.arch})'],
            text=True))
        assert node_fingerprint == producer['node'] and node_fingerprint['platform'] == 'darwin'
        assert node_fingerprint['versions']['node'] == '24.5.0'
        args.host_archive = repository / producer['hostArchive']['path']
        args.host_sha256 = producer['hostArchive']['sha256']
        args.sdk_sha256 = producer['sdkManifest']['sha256']
        args.sdk_input = producer['sdkManifest']['inputSHA256']
        assert sha(args.host_archive) == args.host_sha256
        assert sha(repository / producer['shippingHostArchive']['path']) == args.host_sha256
        producer_inputs = repository / producer['sdkInputs']['path']
        assert sha(producer_inputs) == producer['sdkInputs']['sha256']
        sdk_source_inputs = json.loads(producer_inputs.read_text())
        assert sdk_source_inputs['sha256'] == args.sdk_input
        source_patch = subprocess.check_output(['git', 'diff', '--binary', 'HEAD'], cwd=repository)
        assert hashlib.sha256(source_patch).hexdigest() == producer['sourcePatch']['sha256']
        assert sha(FIXTURES / 'source-baseline.json') == BASELINE_SHA256
        assert sha(FIXTURES / 'preparation.json') == PREPARATION_SHA256
        baseline = json.loads((FIXTURES / 'source-baseline.json').read_text())
        preparation = json.loads((FIXTURES / 'preparation.json').read_text())
        assert baseline['canonicalSource'] == TOOL_SOURCE
        assert len(baseline['projects']) == 9 and sum(len(x['files']) for x in baseline['projects']) == 103
        assert len({x['id'] for x in baseline['projects']}) == 9
        shutil.copy2(FIXTURES / 'source-baseline.json', ROOT / 'source-baseline.json')
        shutil.copy2(FIXTURES / 'preparation.json', E / 'preparation.json')
        for project in baseline['projects']:
            assert len(safe_path(project['id']).parts) == 1
            for row in project['files']:
                relative = safe_path(row['path'])
                authored = FIXTURES / 'projects' / project['id'] / relative
                assert authored.stat().st_size == row['bytes'] and sha(authored) == row['sha256']
                copy = ROOT / 'projects' / project['id'] / relative
                copy.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(authored, copy)
        for row in preparation['originalTools']:
            assert sha(repository / row['path']) == row['sha256']
            current_blob = subprocess.check_output(['git', 'show', source + ':' + row['path']], cwd=repository)
            assert hashlib.sha256(current_blob).hexdigest() == row['sha256']
            row['verifiedUnchangedAtSDKProducerSource'] = source
        state['producerState'] = ref(args.producer_state)
        state['runner'] = ref(Path(__file__))
        state['fixtureBaseline'] = ref(FIXTURES / 'source-baseline.json')
        state['producerNodeFingerprint'] = node_fingerprint
        state['hostArchive'] = ref(args.host_archive)
        state['node'] = {**ref(NODE), 'version': subprocess.check_output([str(NODE), '--version'], text=True).strip()}
        state['diskBefore'] = shutil.disk_usage(ROOT)._asdict()
        SDK.mkdir(exist_ok=False)
        reused = []
        extracted = []
        with zipfile.ZipFile(args.host_archive) as archive:
            raw = archive.read('MiniAppSDK/miniapp-sdk.json')
            assert hashlib.sha256(raw).hexdigest() == args.sdk_sha256
            manifest = json.loads(raw)
            assert manifest['inputSHA256'] == args.sdk_input
            assert manifest['sourceInputs'] == sdk_source_inputs['files']
            for row in manifest['sourceInputs']:
                authored = repository / safe_path(row['path'])
                assert sha(authored) == row['sha256'], 'SDK producer source changed: ' + row['path']
            assert len({x['path'] for x in manifest['files']}) == len(manifest['files'])
            (SDK / 'miniapp-sdk.json').write_bytes(raw)
            for row in manifest['files']:
                rel = safe_path(row['path'])
                target = SDK / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                member = archive.getinfo('MiniAppSDK/' + row['path'])
                assert member.file_size == row['bytes']
                mode = (member.external_attr >> 16) & 0o777 or 0o644
                data = archive.read(member)
                assert hashlib.sha256(data).hexdigest() == row['sha256']
                target.write_bytes(data)
                target.chmod(mode)
                extracted.append(row['path'])
        verify_sdk(manifest)
        write_new(E / 'sdk-materialization.json', {'at': now(), 'manifest': ref(SDK / 'miniapp-sdk.json'),
            'inputSHA256': args.sdk_input, 'source': source, 'hostArchive': ref(args.host_archive),
            'unchangedVerifiedFilesHardlinked': reused, 'newOriginalFilesExtracted': extracted,
            'payloadFiles': len(manifest['files']), 'boundary': 'Byte-exact current Darwin producer SDK. Every payload member is extracted and verified from that ZIP; no alternate SDK or dependency installation.'})
        metadata_changes = []
        project_inputs = {}
        for project in baseline['projects']:
            p = ROOT / 'projects' / project['id']
            for row in project['files']:
                assert sha(p / row['path']) == row['sha256']
            package_path = p / 'package.json'
            package = json.loads(package_path.read_text())
            before = json.loads(package_path.read_text())
            engine = manifest['engines'][project['engine']]
            for name in package.get('dependencies', {}):
                if name in engine['packageVersions']:
                    package['dependencies'][name] = engine['packageVersions'][name]
            if project['engine'] == 'expo' and 'hanlinExpo' in package:
                contract = engine['hostContract']
                package['hanlinExpo'].update(runtimeVersion=contract['runtimeVersion'],
                    bridgeVersion=contract['bridgeVersion'], plugins=contract['plugins'])
                package['hanlinExpo'].setdefault('nativeApi', {}).update(
                    contractVersion=contract['nativeApiContractVersion'], abiIdentity=contract['nativeApiAbiIdentity'])
            if package != before:
                package_path.write_text(json.dumps(package, ensure_ascii=False, indent=2) + '\n')
                metadata_changes.append({'id': project['id'], 'path': 'package.json', 'before': before,
                                         'after': package, 'sha256': sha(package_path)})
            project_inputs[project['id']] = [{'path': x['path'], 'bytes': (p / x['path']).stat().st_size,
                'sha256': sha(p / x['path'])} for x in project['files']]
        write_new(E / 'metadata-changes.json', metadata_changes)
        write_new(E / 'current-source-inputs.json', project_inputs)
        state.update(status='BUILDING', sdkManifestSHA256=args.sdk_sha256, sdkInputSHA256=args.sdk_input,
                     sdkPayloadFiles=len(manifest['files']), packageVersions={k: v['packageVersions'] for k, v in manifest['engines'].items()})
        save()
        env = {'PATH': str(NODE.parent) + os.pathsep + os.environ.get('PATH', '/usr/bin:/bin'),
               'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8', 'TZ': 'UTC', 'CI': '1',
               'TERM': 'dumb', 'TMPDIR': str(ROOT / 'temporary')}
        if os.environ.get('DEVELOPER_DIR'):
            env['DEVELOPER_DIR'] = os.environ['DEVELOPER_DIR']

        def build(project):
            ident = project['id']
            if stop.is_set():
                return {'id': ident, 'status': 'NOT_RUN_AFTER_OTHER_FAILURE'}
            artifact = ROOT / 'artifacts' / Path(project['artifactDeliveryPath']).name
            report_path = E / (ident + '-build.json')
            argv = [str(NODE), str(CLI), 'build', '--sdk', str(SDK), '--engine', project['engine'],
                    '--project', str(ROOT / 'projects' / ident), '--archive', str(artifact), '--report', str(report_path)]
            record = {'id': ident, 'engine': project['engine'], 'argv': argv, 'cwd': str(ROOT),
                      'startedAt': now(), 'source': source, 'sdkManifestSHA256': args.sdk_sha256}
            timer = time.monotonic()
            try:
                with (E / (ident + '.stdout.log')).open('xb') as out, (E / (ident + '.stderr.log')).open('xb') as err:
                    process = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=out, stderr=err, start_new_session=True)
                    record['pid'] = process.pid
                    try:
                        record['exitCode'] = process.wait(timeout=300)
                    except BaseException:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                        raise
                report = json.loads(report_path.read_text())
                record.update(report=ref(report_path), typecheck=report.get('typecheck'), diagnostics=report.get('diagnostics'))
                assert record['exitCode'] == 0 and report['succeeded']
                assert not any(x.get('category') == 'error' for x in report['diagnostics'])
                assert report['sdk']['manifestSHA256'] == args.sdk_sha256
                assert report['typecheck']['strict'] is True
                record.update(status='EXECUTED_PASS', artifact=ref(artifact), compilerVersion=report['sdk']['compilerVersion'])
            except BaseException as error:
                record.update(status='FAILED', error=repr(error), traceback=traceback.format_exc())
                stop.set()
            finally:
                record.update(finishedAt=now(), actualElapsedSeconds=time.monotonic() - timer)
                write_new(E / (ident + '-command.json'), record)
                with lock:
                    state['commands'].append(record)
                    save()
            return record

        # Two independent compiler/Metro readers; every output and temporary project is owned here.
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(build, baseline['projects']))
        assert all(x.get('status') == 'EXECUTED_PASS' for x in results), 'At least one actual build failed or was not run'
        verify_sdk(manifest)
        assert sha(SDK / 'miniapp-sdk.json') == args.sdk_sha256
        assert sha(args.host_archive) == args.host_sha256
        assert subprocess.check_output(['git', 'diff', '--binary', 'HEAD'], cwd=repository) == source_patch
        for row in manifest['sourceInputs']:
            assert sha(repository / safe_path(row['path'])) == row['sha256']
        archives = []
        for project in baseline['projects']:
            ident = project['id']
            p = ROOT / 'projects' / ident
            for row in project_inputs[ident]:
                assert sha(p / row['path']) == row['sha256']
            for row in project['files']:
                if row['path'] != 'package.json':
                    assert sha(p / row['path']) == row['sha256'], 'Behavior source changed'
            artifact = ROOT / 'artifacts' / Path(project['artifactDeliveryPath']).name
            with zipfile.ZipFile(artifact) as archive:
                names = archive.namelist()
                assert len(names) == len(set(names)) and archive.testzip() is None
                for name in names:
                    safe_path(name)
                report = json.loads(archive.read('hanlin.validation.json'))
                assert report['succeeded'] and report['sdk']['manifestSHA256'] == args.sdk_sha256
                script = json.loads(archive.read('script.json'))
                assert script['hanlinRuntime'] == 'hanlin-' + project['engine'] and archive.read(script['entry'])
                for row in project_inputs[ident]:
                    data = archive.read('source/' + row['path'])
                    assert hashlib.sha256(data).hexdigest() == row['sha256']
                members = [{'path': x.filename, 'bytes': x.file_size,
                            'sha256': hashlib.sha256(archive.read(x)).hexdigest()} for x in archive.infolist()]
            archives.append({'id': ident, 'engine': project['engine'], **ref(artifact),
                'deliveryPath': project['artifactDeliveryPath'], 'sourceDeliveryPath': project['sourceDeliveryPath'],
                'previousArtifact': project['previousArtifact'], 'sdkManifestSHA256': args.sdk_sha256,
                'sdkInputSHA256': args.sdk_input, 'source': source, 'members': members,
                'sourceFiles': project_inputs[ident], 'typecheck': report['typecheck'], 'sdk': report['sdk'],
                'nativeExecution': 'NOT_RUN', 'status': 'EXECUTED_PASS_PORTABLE_BUILD'})
        write_new(E / 'archive-audit.json', {'schema': 1, 'archives': archives})
        summary = {'schema': 1, 'status': 'EXECUTED_PASS_PORTABLE_BUILD', 'completedAt': now(),
            'source': source, 'sdkManifestSHA256': args.sdk_sha256, 'sdkInputSHA256': args.sdk_input,
            'producerState': ref(args.producer_state), 'originalTools': preparation['originalTools'],
            'node': state['node'], 'commands': results,
            'archives': [{k: v for k, v in a.items() if k != 'members'} for a in archives],
            'metadataChanges': ref(E / 'metadata-changes.json'), 'archiveAudit': ref(E / 'archive-audit.json'),
            'checks': {'actualOriginalBuildInvocations': len(results), 'allStrict': True,
                'allAuthoredBehaviorFilesUnchanged': True, 'allRetainedSourceFilesVerified': True,
                'originalSDKPayloadUnchanged': len(manifest['files']), 'dependencyInstallation': False,
                'nativeExecution': 'NOT_RUN'},
            'boundary': 'Nine actual public CLI builds with their original compilers and final exported SDK. No native installation, OS execution or physical-device pass is inferred.'}
        write_new(E / 'verification-summary.json', summary)
        state.update(status='EXECUTED_PASS_PORTABLE_BUILD', summary=ref(E / 'verification-summary.json'))
    except BaseException as error:
        state.update(status='FAILED', error=repr(error), traceback=traceback.format_exc())
        state['errors'].append(repr(error))
    finally:
        state.update(finishedAt=now(), actualElapsedSeconds=time.monotonic() - began,
                     diskAfter=shutil.disk_usage(ROOT)._asdict())
        save()
        print(json.dumps({'status': state['status'], 'state': ref(ROOT / 'state.json'),
                          'summary': state.get('summary'), 'error': state.get('error')}), flush=True)
    return 0 if state['status'] == 'EXECUTED_PASS_PORTABLE_BUILD' else 1


if __name__ == '__main__':
    raise SystemExit(main())
