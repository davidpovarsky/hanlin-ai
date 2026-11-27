#!/usr/bin/env python3
"""Prepared root-owned combined native follow-host and binding publication.

The sole parent is actual published8b548. Preserve the frozen unexecuted19
proposal, add only the original G27 handle/test correction and original proof.
No source pin, materialization, build, test, dispatch or existing ref change.
Actual source whitespace is checked separately from original retained evidence.
"""
import base64
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import subprocess
import sys
import time


BARE = Path('/mnt/development/projects/git-mirrors/hanlin-ai.git')
WORKTREE = Path('/mnt/development/projects/worktrees/hanlin-pinkha-original-sdk-union-20261127')
PAYLOAD = Path('/var/lib/sentinelx/uploads/pinkha-sdk-native-follow-binding-payload.json.gz')
EVIDENCE = Path('/mnt/development/projects/evidence/pinkha-root-sdk-native-follow-binding-publication-20261127')
PRIVATE = Path('/tmp/pinkha-root-sdk-native-follow-binding-index-20261127')
OUT = Path('/tmp/pinkha-root-sdk-native-follow-binding-publication-20261127.json')
BASE = '8b548bbe5b1340a48e741191c41d6b30c73537df'
BASE_TREE = 'c381d5c97207b30dfd0494bd54b74919010c7b1e'
TREE = 'a52fdb359190930d23a76877baf2fe8fa25101d6'
BASE_REF = 'refs/heads/codex/pinkha-sdk-promise-metadata-intents-20261127'
REF = 'refs/heads/codex/pinkha-sdk-native-follow-binding-20261127'
WORKTREE_HEAD = '0ae1920d316b9592cbad0462bea96a07fd1ca351'
PAYLOAD_SHA = 'bf3abf99798e11ed06d3189d5fda105839400d03b39fda5169e358a2cd4d9bd5'
PACKED_SHA = 'a2582b4390c95047b63ed04df77cea720520c8f57cfb3ecc17c7601619d341e3'
PRE = ['sudo', '-n', '-u', 'ubuntu', '-g', 'chatgpt-agent']
AGENT = ['sudo', '-n', '-u', 'chatgpt-agent']
MAX_SECONDS = 300
MAX_LOG = 16 * 1024**2
PROVENANCE = 'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json'
HANDLER = 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/HanlinNativeServicesBridge.m'
WIRE = 'AI_HLYTests/NativeScriptRuntimeWireTests.swift'
PRODUCT = 'Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Scrolling/HanlinFollowLatestOverlay.swift'
PRODUCTS = ('AI_HLYTests/ChatScrollViewHandleTests.swift',
            'Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Scrolling/ChatScrollViewHandle.swift', PRODUCT)
PRIOR = Path('/tmp/pinkha-root-sdk-promise-metadata-intents-publication-20261127.json')


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def blob(raw):
    return hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()


def encoded(value):
    return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()


def no_symlinks(path):
    for part in [path, *path.parents]:
        require(not part.is_symlink(), 'Symbolic path component: ' + str(part))


def read_regular(path, maximum=MAX_LOG):
    no_symlinks(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NOATIME)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_size <= maximum, 'Nonregular or oversized input: ' + str(path))
        raw = stream.read(maximum + 1)
        require(len(raw) == before.st_size and os.fstat(stream.fileno()) == before, 'Input changed while read: ' + str(path))
        return raw


def exclusive(path, raw):
    no_symlinks(path)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def optional_file_identity(path):
    no_symlinks(path)
    if not path.exists():
        return {'path': str(path), 'absent': True}
    before = path.stat()
    raw = read_regular(path)
    return {'path': str(path), 'bytes': len(raw), 'sha256': sha(raw),
            'device': before.st_dev, 'inode': before.st_ino, 'mode': before.st_mode,
            'uid': before.st_uid, 'gid': before.st_gid,
            'mtime_ns': before.st_mtime_ns, 'ctime_ns': before.st_ctime_ns}


def resources():
    result = {}
    for name, path, floor, growth in [('root', Path('/'), 2 * 1024**3, 16 * 1024**2),
                                     ('development', BARE, 512 * 1024**2, 64 * 1024**2)]:
        v = os.statvfs(path)
        free = v.f_bavail * v.f_frsize
        require(free >= floor + growth, name + ' below source-only floor plus bounded growth')
        result[name] = {'freeBytes': free, 'floorBytes': floor, 'growthAllowanceBytes': growth}
    memory = dict(re.findall(r'^(\w+):\s+(\d+) kB$', Path('/proc/meminfo').read_text(), re.M))
    available = int(memory['MemAvailable']) * 1024
    require(available >= 256 * 1024**2, 'Available memory below256MiB')
    result['memoryAvailableBytes'] = available
    return result


def group_absent(pgid):
    try:
        os.killpg(pgid, 0)
        return False
    except ProcessLookupError:
        return True


def join_group(process, row):
    row['originalGroupAbsentAfterLeader'] = group_absent(process.pid)
    row['cleanupSignals'] = []
    if not row['originalGroupAbsentAfterLeader']:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            if group_absent(process.pid):
                break
            try:
                os.killpg(process.pid, sig)
                row['cleanupSignals'].append(sig.name)
            except ProcessLookupError:
                pass
            end = time.monotonic() + 5
            while not group_absent(process.pid) and time.monotonic() < end:
                try:
                    process.wait(timeout=0.05)
                except subprocess.TimeoutExpired:
                    pass
                time.sleep(0.05)
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    row['originalProcessGroupAbsent'] = group_absent(process.pid)
    require(row['originalProcessGroupAbsent'], 'Owned process group remains: ' + str(process.pid))


class Commands:
    def __init__(self, receipt):
        self.receipt = receipt
        self.deadline = time.monotonic() + MAX_SECONDS
        self.blocked = False
        self.in_cleanup = False
        self.interrupted_signal = None

    def run(self, label, argv, *, data=None, env=None, timeout=25):
        require(not self.blocked, 'No command after abnormal or unresolved custody')
        remaining = self.deadline - time.monotonic()
        require(remaining > 1, 'Publication live-time budget exhausted')
        row = {'label': label, 'argv': argv, 'startedAt': time.time(), 'timeoutSeconds': min(timeout, remaining)}
        self.receipt['commands'].append(row)
        stem = EVIDENCE / ('command-%03d-' % len(self.receipt['commands']) + label)
        out_path, err_path = Path(str(stem) + '.stdout'), Path(str(stem) + '.stderr')
        stdin = None
        if data is not None:
            require(len(data) <= MAX_LOG, 'Oversized closed command input')
            input_path = Path(str(stem) + '.stdin')
            exclusive(input_path, data)
            row['stdin'] = {'path': str(input_path), 'bytes': len(data), 'sha256': sha(data)}
            stdin = input_path.open('rb')
        process = None
        first = None
        try:
            with out_path.open('xb') as out, err_path.open('xb') as err:
                try:
                    process = subprocess.Popen(argv, stdin=stdin if stdin else subprocess.DEVNULL,
                                               stdout=out, stderr=err, start_new_session=True,
                                               env={**os.environ, 'GIT_TERMINAL_PROMPT': '0', 'GIT_OPTIONAL_LOCKS': '0',
                                                    'PYTHONDONTWRITEBYTECODE': '1', **(env or {})})
                    row.update({'pid': process.pid, 'pgid': process.pid})
                    row['exitCode'] = process.wait(timeout=row['timeoutSeconds'])
                    if row['exitCode'] != 0:
                        raise RuntimeError(label + ' exited ' + str(row['exitCode']))
                except BaseException as error:
                    first = error
                    row['firstFailure'] = {'type': type(error).__name__, 'message': str(error)}
                finally:
                    if process is not None:
                        self.in_cleanup = True
                        try:
                            join_group(process, row)
                        except BaseException as error:
                            row['cleanupFailure'] = {'type': type(error).__name__, 'message': str(error)}
                            if first is None:
                                first = error
                        finally:
                            self.in_cleanup = False
                        row['exitCode'] = process.returncode
                    row['finishedAt'] = time.time()
        finally:
            if stdin is not None:
                stdin.close()
        if self.interrupted_signal is not None:
            self.blocked = True
            if first is None:
                first = TimeoutError('Publication interrupted by signal ' + str(self.interrupted_signal))
        if row.get('cleanupSignals') or row.get('originalProcessGroupAbsent') is not True:
            self.blocked = True
            if first is None:
                first = RuntimeError(label + ': owned descendant cleanup required; command is not accepted')
        if first is not None and 'firstFailure' not in row:
            row['firstFailure'] = {'type': type(first).__name__, 'message': str(first)}
        try:
            for key, path in [('stdout', out_path), ('stderr', err_path)]:
                raw = read_regular(path)
                row[key] = {'path': str(path), 'bytes': len(raw), 'sha256': sha(raw)}
            exclusive(Path(str(stem) + '.json'), encoded(row))
        except BaseException as error:
            self.blocked = True
            row['receiptFailure'] = {'type': type(error).__name__, 'message': str(error)}
            if first is None:
                first = error
        if first is not None:
            raise first
        return read_regular(out_path)

    def git(self, label, *args, data=None, private=False, publish=False, timeout=25, worktree=False):
        prefix = AGENT if worktree else PRE
        repo = WORKTREE if worktree else BARE
        # These assignments must occur AFTER sudo: its existing environment
        # filtering must never discard the private index or prompt boundary.
        argv = prefix + ['env', 'GIT_TERMINAL_PROMPT=0', 'GIT_OPTIONAL_LOCKS=0', 'PYTHONDONTWRITEBYTECODE=1']
        if private:
            argv += ['GIT_INDEX_FILE=' + str(PRIVATE / 'index')]
        argv += ['git', '--no-optional-locks', '--no-replace-objects', '-c', 'gc.auto=0', '-C', str(repo)]
        if publish:
            argv += ['-c', 'remote.origin.mirror=false', '-c', 'credential.helper=!gh auth git-credential']
        return self.run(label, argv + list(args), data=data, timeout=timeout)


def parse_leaves(raw):
    result = {}
    for line in raw.split(b'\0'):
        if not line:
            continue
        header, path = line.split(b'\t', 1)
        mode, kind, oid = header.decode().split()
        require(path.decode() not in result, 'Duplicate Git leaf')
        result[path.decode()] = {'mode': mode, 'type': kind, 'sha': oid}
    return result


def parse_refs(raw):
    result = {}
    for line in raw.decode().splitlines():
        name, oid = line.split()
        require(name not in result and re.fullmatch('[a-f0-9]{40}', oid), 'Malformed original ref inventory')
        result[name] = oid
    return result


def input_payload():
    packed = read_regular(PAYLOAD, 496226)
    require(len(packed) == 496226 and sha(packed) == PACKED_SHA, 'Wrong packed source payload')
    raw = gzip.decompress(packed)
    require(len(raw) == 2500802 and sha(raw) == PAYLOAD_SHA, 'Wrong source payload')
    payload = json.loads(raw)
    require(payload['base'] == BASE and payload['baseTree'] == BASE_TREE and payload['expectedTree'] == TREE, 'Wrong source tuple')
    require(payload['branch'] == REF.removeprefix('refs/heads/'), 'Wrong new branch')
    require(payload['publication'] == 'NOT_EXECUTED' and payload['runtime'] == 'NOT_RUN', 'Changed source-only scope')
    files = payload['files']
    require(len(files) == 47 and payload['reviewedSourceInputPaths'] == sorted(PRODUCTS)
            and payload['frozen19AllFilesRetained'] is True, 'Wrong finite combined path count')
    contents = {}
    for path, row in files.items():
        require(not path.startswith('/') and '..' not in PurePosixPath(path).parts and '\n' not in path and '\t' not in path,
                'Invalid closed source path')
        content = base64.b64decode(row['base64'], validate=True)
        identity = row['after']
        require(identity['mode'] in ('100644', '100755'), 'Unsupported source mode')
        require(len(content) == identity['bytes'] and sha(content) == identity['sha256'] and blob(content) == identity['gitBlob'],
                'Source bytes mismatch: ' + path)
        contents[path] = content
        if row['status'] == 'M':
            old = base64.b64decode(row['beforeBase64'], validate=True)
            require(row['before']['mode'] == identity['mode'], 'Existing source mode changed')
            require(len(old) == row['before']['bytes'] and sha(old) == row['before']['sha256'] and
                    blob(old) == row['beforeGitBlob'] == row['before']['gitBlob'], 'Original bytes mismatch: ' + path)
        else:
            require(row['status'] == 'A' and row['beforeGitBlob'] is None, 'Unsupported source status')
    require(sorted(path for path, row in files.items() if row['status'] == 'M') == payload['modifiedPaths'] and
            payload['modifiedPaths'] == sorted(PRODUCTS), 'Wrong exact three modified originals')
    require(PROVENANCE not in files and payload['provenanceRows'] == 227, 'Provenance must remain unchanged')
    protected = payload['protectedProvenance']
    original = base64.b64decode(protected['base64'], validate=True)
    require(len(original) == protected['bytes'] and sha(original) == protected['sha256'] and
            blob(original) == protected['gitBlob'] and len(json.loads(original)['files']) == 227,
            'Protected original227-row provenance identity differs')
    require(payload['originalGitModePreservation'] == [] and all(row['after']['mode'] == '100644' for row in files.values()),
            'No existing mode or executable-wrapper change is admitted')
    return payload, contents


def worktree_snapshot(commands, label):
    head = commands.git(label + '-head', 'rev-parse', 'HEAD', 'HEAD^{tree}', worktree=True).decode().splitlines()
    require(head[0] == WORKTREE_HEAD, 'Historical original source worktree advanced; stop for explicit rebind')
    status = commands.git(label + '-status', 'status', '--porcelain=v1', '-z', '--untracked-files=all', worktree=True)
    paths = commands.git(label + '-admin-paths', 'rev-parse', '--path-format=absolute', '--git-path', 'index',
                         '--git-path', 'info/sparse-checkout', '--git-path', 'HEAD', worktree=True).decode().splitlines()
    require(len(paths) == 3, 'Original source admin path cardinality')
    admin = {}
    for name, path in zip(['index', 'sparse', 'HEAD'], paths):
        p = Path(path)
        no_symlinks(p)
        if p.exists():
            before = p.stat()
            raw = read_regular(p)
            admin[name] = {'path': path, 'bytes': len(raw), 'sha256': sha(raw),
                           'device': before.st_dev, 'inode': before.st_ino, 'mode': before.st_mode,
                           'uid': before.st_uid, 'gid': before.st_gid,
                           'mtime_ns': before.st_mtime_ns, 'ctime_ns': before.st_ctime_ns}
        else:
            admin[name] = {'path': path, 'absent': True}
    return {'head': head[0], 'tree': head[1], 'statusBytes': len(status), 'statusSHA256': sha(status), 'admin': admin}


def verify_package_inventory(payload, leaves):
    total = 0
    for package in payload['packageClosure']['packages']:
        prefix = package['package'] + '/'
        actual = [{'mode': value['mode'], 'path': path[len(prefix):], 'sha': value['sha']}
                  for path, value in leaves.items() if path.startswith(prefix)]
        require(all(value['type'] == 'blob' for path, value in leaves.items() if path.startswith(prefix)), 'Non-blob package leaf')
        actual.sort(key=lambda value: value['path'])
        expected = sorted(package['completeProposedLeaves'], key=lambda value: value['path'])
        require(actual == expected and len(actual) == package['proposedBlobCount'], 'Complete package inventory differs: ' + prefix)
        total += len(actual)
        for path, oid in package['unchangedManifestsAndLocks'].items():
            require(leaves[prefix + path]['sha'] == oid, 'Original package manifest/lock changed')
    require(total == 1010, 'Wrong complete4-package leaf count')


def positive_base_receipt():
    raw = read_regular(PRIOR, 208809)
    require(len(raw) == 208809 and sha(raw) == '3afc5bbe91fee176fab2ba0323ad7be5381e1b3c068335716c95f1ab4a723c4f',
            'Actual original63 publication receipt differs')
    prior = json.loads(raw)
    require(prior['schema'] == 'pinkha-root-original-sdk-new-ref-publication/v1' and
            prior['state'] == 'PASS_SOURCE_ONLY_NEW_REF_PUBLISHED', 'Prior source publication is not positive')
    require(prior['candidateCommit'] == prior['normalPushReadback'] == BASE and
            prior['candidateTree'] == BASE_TREE and prior['base'] == '4cb6454c1c6e110ead73179c06ada9e909bf250b',
            'Prior actual source ancestry/tree mismatch')
    require(prior['ref'] == BASE_REF and prior['normalPushCompleted'] is True and
            prior['originalSourceWorktreePreserved'] is True and prior['commandCustodyBlocked'] is False and
            prior['firstFailure'] is None, 'Prior publication/preservation/custody was not accepted')
    require(prior['controllerSHA256'] == '78287bad76049927f80a136e9683abbe6f6c9ad9af8efb44f7c8619bf1b814eb' and
            prior['payloadSHA256'] == '58db8c8ca969099d07f83c9509049cbc09c0fa519f590244e81c0360e622fce7',
            'Prior source controller/payload mismatch')
    require(all(prior[key] == 0 for key in ('compilerInvocations', 'testsExecuted', 'workflowDispatches', 'materializations')),
            'Prior source-only scope mismatch')
    require(len(prior['commands']) == 110 and all(row['exitCode'] == 0 and row['originalProcessGroupAbsent'] is True and
            row['cleanupSignals'] == [] and not row.get('firstFailure') and not row.get('receiptFailure') for row in prior['commands']),
            'Original110 command receipts are not all successful and drained')
    return raw


def exact_package_bytes(commands, payload, leaves):
    paths = [row['package'] for row in payload['packageClosure']['packages']]
    raw = commands.git('exact1010-package-byte-inventory', 'ls-tree', '-r', '-l', '-z', TREE, '--', *paths)
    count = 0
    size = 0
    for entry in raw.split(b'\0'):
        if not entry:
            continue
        header, path = entry.split(b'\t', 1)
        mode, kind, oid, length = header.decode().split()
        require(kind == 'blob' and mode == '100644' and
                leaves[path.decode()] == {'mode': mode, 'type': kind, 'sha': oid}, 'Actual package size row identity mismatch')
        count += 1
        size += int(length)
    require(count == 1010 and size == 39797368, 'Actual final1010-package count/bytes differ')
    return {'files': count, 'sourceBytes': size, 'gitInventorySHA256': sha(raw)}


def publish(commands, receipt, payload, contents):
    files = payload['files']
    prior_raw = positive_base_receipt()
    exclusive(EVIDENCE / 'base63-publication.original.json', prior_raw)
    receipt['positiveBasePublicationReceiptSHA256'] = sha(prior_raw)
    require(commands.git('base-identities', 'rev-parse', BASE, BASE + '^{tree}').decode().splitlines() == [BASE, BASE_TREE],
            'Immutable original base absent or changed; no automatic fetch')
    refs = parse_refs(commands.git('refs-before', 'for-each-ref', '--format=%(refname) %(objectname)'))
    require(REF not in refs, 'Candidate local ref already exists')
    remote = commands.git('remote-preflight', 'ls-remote', '--heads', 'origin', BASE_REF, REF, publish=True, timeout=45).decode().splitlines()
    require(remote == [BASE + '\t' + BASE_REF], 'Original remote base changed or new remote ref already exists')
    before_wt = worktree_snapshot(commands, 'source-before')
    receipt['originalSourceWorktreeBefore'] = before_wt
    config = read_regular(BARE / 'config')
    bare_head = read_regular(BARE / 'HEAD')
    bare_index = optional_file_identity(BARE / 'index')
    receipt['originalBareIndexBefore'] = bare_index
    receipt['originalBareConfigurationSHA256'] = sha(config)
    receipt['originalBareHEADSHA256'] = sha(bare_head)
    leaves = parse_leaves(commands.git('complete-base-leaves', 'ls-tree', '-r', '-z', BASE))
    for path, row in files.items():
        expected = {'mode': row['before']['mode'], 'type': 'blob', 'sha': row['beforeGitBlob']} if row['status'] == 'M' else None
        require(leaves.get(path) == expected, 'Actual full-tree preimage or absence mismatch: ' + path)
    originals = [path for path in sorted(files) if files[path]['status'] == 'M']
    batch = commands.git('three-original-byte-readback', 'cat-file', '--batch',
                         data=''.join(files[path]['beforeGitBlob'] + '\n' for path in originals).encode())
    cursor = 0
    for path in originals:
        end = batch.index(b'\n', cursor)
        oid, kind, size = batch[cursor:end].decode().split()
        size = int(size)
        raw = batch[end + 1:end + 1 + size]
        require(oid == files[path]['beforeGitBlob'] and kind == 'blob' and raw == base64.b64decode(files[path]['beforeBase64']),
                'Original Git bytes differ: ' + path)
        require(batch[end + 1 + size:end + 2 + size] == b'\n', 'Original Git batch framing')
        cursor = end + 2 + size
    require(cursor == len(batch), 'Extra original Git batch bytes')
    require(leaves[HANDLER]['sha'] == '7bbc804da241fe31d6e860eaedd064a192b97e49' and
            leaves[WIRE]['sha'] == 'ab113355ec8b87b34bc07216806b08f005dc1c36', 'Original explicit-handler source identity changed')
    for key, oid in payload['protectedTrees'].items():
        actual = commands.git('protected-base-' + str(len(receipt['commands'])), 'rev-parse', BASE + ':' + key).decode().strip()
        require(actual == oid, 'Protected original subtree mismatch: ' + key)
    before_packages = sum(sum(path.startswith(package['package'] + '/') for path in leaves)
                          for package in payload['packageClosure']['packages'])
    require(before_packages == 1010, 'Original package count differs')
    require(leaves[PROVENANCE]['sha'] == payload['protectedProvenance']['gitBlob'], 'Original227-row provenance changed')
    predicted = dict(leaves)
    for path, row in files.items():
        predicted[path] = {'mode': row['after']['mode'], 'type': 'blob', 'sha': row['after']['gitBlob']}
    verify_package_inventory(payload, predicted)
    receipt['sourcePreflight'] = {'fullBaseLeaves': len(leaves), 'modified': 3, 'added': 44,
                                  'originalPackages': 1010, 'candidatePackages': 1010,
                                  'provenanceRows': 227, 'provenanceHashChanges': 0}
    receipt['resourceBeforeObjectWrites'] = resources()
    commands.run('create-exclusive-private-index-directory', PRE + ['python3', '-B', '-c',
                 'import os,sys;os.mkdir(sys.argv[1],0o700)', str(PRIVATE)])
    require(PRIVATE.stat().st_uid == 1001 and PRIVATE.stat().st_gid == 1002 and stat.S_IMODE(PRIVATE.stat().st_mode) == 0o700,
            'New private index directory owner/mode mismatch')
    commands.git('read-full-original-tree-into-private-index', 'read-tree', BASE, private=True)
    for position, path in enumerate(sorted(files), 1):
        oid = commands.git('write-reviewed-blob-%03d' % position, 'hash-object', '-w', '--stdin', data=contents[path]).decode().strip()
        require(oid == files[path]['after']['gitBlob'], 'Git wrote a different reviewed blob: ' + path)
    index = b''.join((files[path]['after']['mode'] + ' ' + files[path]['after']['gitBlob'] + '\t' + path).encode() + b'\0'
                     for path in sorted(files))
    commands.git('apply-only47-private-index-entries', 'update-index', '-z', '--index-info', data=index, private=True)
    actual_tree = commands.git('write-private-full-tree', 'write-tree', private=True).decode().strip()
    require(actual_tree == TREE, 'Complete candidate tree mismatch')
    actual_leaves = parse_leaves(commands.git('complete-candidate-leaves', 'ls-tree', '-r', '-z', TREE))
    require(actual_leaves == predicted, 'Candidate changes a source path outside the closed47')
    verify_package_inventory(payload, actual_leaves)
    actual_diff = commands.git('exact47-path-diff', 'diff', '--name-status', '--no-renames', BASE, TREE).decode().splitlines()
    require(actual_diff == [files[path]['status'] + '\t' + path for path in sorted(files)], 'Unexpected complete source diff')
    # Preserve the exact original source/patch evidence diagnostics. This is NOT a
    # whole-diff PASS; any different failure or unresolved custody still stops.
    try:
        commands.git('ordinary-whole-diff-check', 'diff', '--check', BASE, TREE)
    except RuntimeError:
        row = receipt['commands'][-1]
        require(row['label'] == 'ordinary-whole-diff-check' and row.get('exitCode') == 2 and
                row.get('originalProcessGroupAbsent') is True and row.get('cleanupSignals') == [] and
                not row.get('receiptFailure') and not commands.blocked and commands.interrupted_signal is None,
                'Ordinary diff failure is not the retained raw-evidence diagnostic')
        stdout = read_regular(Path(row['stdout']['path']))
        stderr = read_regular(Path(row['stderr']['path']))
        require(sha(stdout) == '11934f25a50be1c8c4e42662b11f807eebcfac260412d46bfd94af9870c96a4d' and stderr == b'',
                'Ordinary diff differs from exactly8 raw-patch and67 original donor-source evidence warnings')
        receipt['ordinaryDiffCheck'] = {'exitCode': 2, 'stdoutSHA256': sha(stdout), 'stderrSHA256': sha(stderr),
                                        'classification': 'EXACT_75_ORIGINAL_EVIDENCE_DIAGNOSTICS_PRESERVED_NOT_PASS',
                                        'rawPatchContextWarnings': 8, 'originalDonorEvidenceWhitespaceWarnings': 67}
    else:
        raise ValueError('Original raw-patch diagnostics unexpectedly disappeared')
    commands.git('actual-three-source-diff-check', 'diff', '--check', BASE, TREE, '--', *PRODUCTS)
    receipt['productDiffCheck'] = {'exitCode': 0, 'scope': 'The two changed original SDK Swift products and one original UIKit test file only'}
    receipt['actualPackageByteInventory'] = exact_package_bytes(commands, payload, actual_leaves)
    for key, oid in payload['protectedTrees'].items():
        require(commands.git('protected-candidate-' + str(len(receipt['commands'])), 'rev-parse', TREE + ':' + key).decode().strip() == oid,
                'Protected source/workflow tree changed: ' + key)
    for package in payload['packageClosure']['packages']:
        require(commands.git('package-root-' + str(len(receipt['commands'])), 'rev-parse', TREE + ':' + package['package']).decode().strip() ==
                package['proposedTree'], 'Candidate package Merkle root differs')
    require(worktree_snapshot(commands, 'source-precommit') == before_wt, 'Original source worktree changed')
    require(read_regular(BARE / 'config') == config and read_regular(BARE / 'HEAD') == bare_head, 'Bare configuration/HEAD changed')
    require(optional_file_identity(BARE / 'index') == bare_index, 'Original bare index changed')
    require(parse_refs(commands.git('refs-precommit', 'for-each-ref', '--format=%(refname) %(objectname)')) == refs,
            'Existing refs advanced during preparation; stop without overwriting')
    message = ('Preserve native follow control ownership across final viewport resize\n\n'
               'Combine the original private UIKit control host with the original G27 native binding token. '
               'Keep strict default viewport APIs, producer/window/conversation ownership, complete environment and manual-follow policy. '
               'Append only three original regression methods while retaining all previous UIKit tests and all other SDK source. '
               'Preserve the frozen unexecuted19 proposal and original failure/source evidence. Current Apple/runtime acceptance remains pending.\n\n'
               'Original parent: ' + BASE + '\n'
               'Original overlay donor: 2b9ef06cc0fdb89e43ef646e040346948a5ba36e\n'
               'Original binding donor: abd1434f8674fd58129c93be5bf33933eda48e1d\n')
    candidate = commands.git('create-sole-parent-source-commit', '-c', 'user.name=ChatGPT', '-c', 'user.email=chatgpt@openai.com',
                             'commit-tree', TREE, '-p', BASE, '-F', '-', data=message.encode()).decode().strip()
    require(re.fullmatch('[a-f0-9]{40}', candidate), 'Invalid created commit ID')
    require(commands.git('created-commit-readback', 'rev-list', '--parents', '-n', '1', candidate).decode().split() == [candidate, BASE],
            'Created commit does not have exactly the original sole parent')
    require(commands.git('created-tree-readback', 'rev-parse', candidate + '^{tree}').decode().strip() == TREE, 'Created commit tree mismatch')
    receipt['candidateCommit'] = candidate
    receipt['candidateTree'] = TREE
    exclusive(EVIDENCE / 'candidate-before-ref.json', encoded({'commit': candidate, 'tree': TREE, 'parent': BASE, 'ref': REF}))
    # A positive final remote check precedes creating the only new local ref.
    remote = commands.git('remote-before-new-ref', 'ls-remote', '--heads', 'origin', BASE_REF, REF, publish=True, timeout=45).decode().splitlines()
    require(remote == [BASE + '\t' + BASE_REF], 'Remote changed before publication')
    commands.git('create-exclusive-new-local-ref', 'update-ref', REF, candidate, '0' * 40)
    receipt['localNewRefCreated'] = True
    expected_refs = {**refs, REF: candidate}
    require(parse_refs(commands.git('new-local-ref-readback', 'for-each-ref', '--format=%(refname) %(objectname)')) == expected_refs,
            'Unexpected local ref change')
    receipt['resourceBeforeNormalPush'] = resources()
    commands.git('normal-new-ref-push', 'push', '--porcelain', '--no-follow-tags', 'origin', candidate + ':' + REF,
                 publish=True, timeout=90)
    receipt['normalPushCompleted'] = True
    remote = commands.git('remote-exact-readback', 'ls-remote', '--heads', 'origin', BASE_REF, REF, publish=True, timeout=45).decode().splitlines()
    require(sorted(remote) == sorted([BASE + '\t' + BASE_REF, candidate + '\t' + REF]), 'Remote exact source readback failed')
    require(parse_refs(commands.git('final-local-refs', 'for-each-ref', '--format=%(refname) %(objectname)')) == expected_refs,
            'Unexpected final local ref change')
    require(worktree_snapshot(commands, 'source-final') == before_wt, 'Original source worktree changed after publication')
    require(read_regular(BARE / 'config') == config and read_regular(BARE / 'HEAD') == bare_head, 'Bare configuration/HEAD changed')
    require(optional_file_identity(BARE / 'index') == bare_index, 'Original bare index changed after publication')
    receipt['originalSourceWorktreePreserved'] = True
    receipt['normalPushReadback'] = candidate
    receipt['state'] = 'PASS_SOURCE_ONLY_NEW_REF_PUBLISHED'


def main():
    require(os.geteuid() == 0 and sys.platform.startswith('linux'), 'Existing Oracle root context required')
    for name in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
                 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS'):
        require(not os.environ.get(name), 'Unexpected inherited Git override: ' + name)
    for path in (EVIDENCE, PRIVATE, OUT):
        no_symlinks(path)
        require(not path.exists(), 'Exclusive publication path already exists; inspect original outcome, do not repeat: ' + str(path))
    payload, contents = input_payload()
    resource = resources()
    EVIDENCE.mkdir(mode=0o700)
    receipt = {'schema': 'pinkha-root-native-follow-binding-new-ref-publication/v1', 'state': 'RUNNING',
               'startedAt': time.time(), 'base': BASE, 'baseTree': BASE_TREE, 'expectedTree': TREE, 'ref': REF,
               'controllerSHA256': sha(read_regular(Path(__file__))), 'payloadSHA256': PAYLOAD_SHA,
               'packedPayloadSHA256': PACKED_SHA, 'commands': [], 'resourcesBefore': resource,
               'files': {path: {key: row[key] for key in ('status', 'after', 'beforeGitBlob')} for path, row in payload['files'].items()},
               'protectedTrees': payload['protectedTrees'], 'originalGitModePreservation': payload['originalGitModePreservation'],
               'scope': 'Source-only two-product/one-original-test/44-evidence new-ref publication. Original23 UIKit methods and current Anytype native overlay/resize behavior remain NOT_RUN; original4cb failure and owner G26 rotated-viewport failure stay separately scoped.' ,
               'compilerInvocations': 0, 'testsExecuted': 0, 'workflowDispatches': 0, 'materializations': 0,
               'firstFailure': None}
    exclusive(EVIDENCE / 'started.json', encoded(receipt))
    commands = Commands(receipt)
    def interrupted(signum, frame):
        commands.interrupted_signal = signum
        commands.blocked = True
        if not commands.in_cleanup:
            raise TimeoutError('Publication interrupted by signal ' + str(signum))
    old_handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGALRM, signal.SIGTERM, signal.SIGINT)}
    for sig in old_handlers:
        signal.signal(sig, interrupted)
    signal.setitimer(signal.ITIMER_REAL, MAX_SECONDS)
    first = None
    try:
        publish(commands, receipt, payload, contents)
    except BaseException as error:
        first = error
        receipt['state'] = 'FAILED_PRESERVED_FOR_INSPECTION'
        receipt['firstFailure'] = {'type': type(error).__name__, 'message': str(error)}
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
        receipt['finishedAt'] = time.time()
        receipt['commandCustodyBlocked'] = commands.blocked
        try:
            raw = encoded(receipt)
            exclusive(EVIDENCE / 'receipt.json', raw)
            exclusive(OUT, raw)
        except BaseException as error:
            receipt['terminalReceiptFailure'] = {'type': type(error).__name__, 'message': str(error)}
            if first is None:
                first = error
                receipt['firstFailure'] = receipt['terminalReceiptFailure']
                receipt['state'] = 'FAILED_TERMINAL_RECEIPT'
            try:
                exclusive(EVIDENCE / 'terminal-receipt-failure.json', encoded(receipt))
            except BaseException:
                pass
        print(json.dumps({'state': receipt['state'], 'candidateCommit': receipt.get('candidateCommit'),
                          'tree': receipt.get('candidateTree'), 'receipt': str(OUT),
                          'firstFailure': receipt['firstFailure'], 'commandCustodyBlocked': commands.blocked}), flush=True)
    if first is not None:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
