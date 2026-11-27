"""Local immutable source/inverse proof only; no Git writes or execution."""
from pathlib import Path
import copy
import hashlib
import json

ROOT = Path(__file__).resolve().parent
WORK = ROOT.parent
BASE = '4cb6454c1c6e110ead73179c06ada9e909bf250b'
PARENT = '08be9aa5e16b59094e2bc690c583f09f540c41bd'
DONOR = '2b9ef06cc0fdb89e43ef646e040346948a5ba36e'
PATH = 'Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Scrolling/HanlinFollowLatestOverlay.swift'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def git_hash(kind, raw):
    return hashlib.sha1(kind.encode() + b' ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()


def ident(raw):
    return {'bytes': len(raw), 'sha256': sha(raw), 'gitBlob': git_hash('blob', raw), 'mode': '100644'}


def write(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    assert not path.exists()
    path.write_bytes(raw)


api = json.loads((ROOT / 'primary-responses.original.json').read_bytes())
original = (ROOT / 'primary' / BASE / PATH).read_bytes()
parent = (ROOT / 'primary' / PARENT / PATH).read_bytes()
donor = (ROOT / 'primary' / DONOR / PATH).read_bytes()
for key, raw in [('base', original), ('parent', parent), ('candidate', donor)]:
    assert git_hash('blob', raw) == api[key]['sha']
    assert raw == api[key]['content'].encode()
manifest = (ROOT / 'primary' / DONOR / 'Packages/HanlinPresentationSDK/Package.swift').read_bytes()
assert git_hash('blob', manifest) == api['manifest']['sha']

start = donor.index(b'/// Give only the resolved control region its own native hosting boundary.')
end = donor.index(b'@MainActor\nprivate struct FollowLatestOverlayHost<Control: View>')
helper = donor[start:end]
assert helper.count(b'private struct ') == 2
host_start = b'@MainActor\nprivate struct FollowLatestOverlayHost<Control: View>'
call = b'                                control(guarded(request))\n'
wrapped_call = (b'                                FollowLatestHostedControl(control: control(guarded(request)))\n'
                b'                                    .frame(width: frame.width, height: frame.height)\n')
assert donor.count(wrapped_call) == 2 and parent.count(call) == 2 and original.count(call) == 1
changes = [(b'import SwiftUI\n', b'import SwiftUI\nimport UIKit\n'),
           (host_start, helper + host_start), (call, wrapped_call)]
candidate = original
ops = []
for before, after in changes:
    assert candidate.count(before) == 1
    candidate = candidate.replace(before, after, 1)
    ops.append({'oldText': before.decode(), 'newText': after.decode(), 'requiredOccurrences': 1})
restored = candidate
for row in reversed(ops):
    assert restored.count(row['newText'].encode()) == 1
    restored = restored.replace(row['newText'].encode(), row['oldText'].encode(), 1)
assert restored == original

# The original publication's own three4cb-applicable hunks are copied exactly.
commit = json.loads((ROOT / 'commit.original.json').read_bytes())
assert commit['sha'] == DONOR and [x['sha'] for x in commit['parents']] == [PARENT]
assert len(commit['files']) == 1 and commit['files'][0]['filename'] == PATH
assert commit['files'][0]['sha'] == git_hash('blob', donor)
full_expected = parent.replace(b'import SwiftUI\n', b'import SwiftUI\nimport UIKit\n', 1)
full_expected = full_expected.replace(host_start, helper + host_start, 1)
full_expected = full_expected.replace(call, wrapped_call)
assert full_expected == donor

# Existing public API and original action/current-selection implementation are exact.
original_public_tail = original[original.index(b'public extension View {'):]
candidate_public_tail = candidate[candidate.index(b'public extension View {'):]
assert candidate_public_tail == original_public_tail
guard_start = b'    private func currentRequest(in requests: [HanlinFollowLatestOverlayRequest])'
guard_end = b'\npublic extension View {'
assert candidate[candidate.index(guard_start):candidate.index(guard_end)] == original[original.index(guard_start):original.index(guard_end)]
assert candidate[:candidate.index(helper)].replace(b'import UIKit\n', b'', 1) == original[:original.index(host_start)]

packet = json.loads((WORK / 'hanlin-sdk-promise-metadata-intents-publication/payload.json').read_bytes())
assert PATH not in packet['files'] and packet['expectedTree'] == 'c381d5c97207b30dfd0494bd54b74919010c7b1e'
pkg = next(x for x in packet['packageClosure']['packages'] if x['package'] == 'Packages/HanlinPresentationSDK')
leaves = copy.deepcopy(pkg['completeProposedLeaves'])
relative = PATH.removeprefix(pkg['package'] + '/')
leaf = next(x for x in leaves if x['path'] == relative)
assert leaf == {'mode': '100644', 'path': relative, 'sha': git_hash('blob', original)}


def merkle(rows):
    root = {}
    for row in rows:
        node = root
        parts = row['path'].split('/')
        for name in parts[:-1]:
            node = node.setdefault(name, {})
        assert parts[-1] not in node
        node[parts[-1]] = (row['mode'], row['sha'])

    def walk(node):
        items = {name: ('40000', walk(value)) if isinstance(value, dict) else value for name, value in node.items()}
        names = sorted(items, key=lambda name: (name + ('/' if items[name][0] == '40000' else '')).encode())
        raw = b''.join(items[name][0].encode() + b' ' + name.encode() + b'\0' + bytes.fromhex(items[name][1]) for name in names)
        return git_hash('tree', raw)
    return walk(root)


assert merkle(leaves) == pkg['proposedTree'] == '3fdc8170b9a749797f4d97c796405306d21ed438'
leaf['sha'] = git_hash('blob', candidate)
new_tree = merkle(leaves)
assert len(leaves) == 455
old_manifest = WORK / 'hanlin-hosted-sdk-control/alias-prerequisites-original/Packages/HanlinPresentationSDK/Package.swift'
old_manifest_raw = old_manifest.read_bytes()
assert git_hash('blob', old_manifest_raw) == pkg['unchangedManifestsAndLocks']['Package.swift']
assert manifest != old_manifest_raw

consumer_path = 'Modules/PinkhaAnyHanlin/Sources/PinkhaHanlinUI/PinkhaHanlinChatView.swift'
consumer = (WORK / 'hanlin-sdk4cb-host-integration-prepared/after' / consumer_path).read_bytes()
assert consumer.count(b'.hanlinFollowLatestOverlayHost(selectedConversationID: Binding(') == 1
assert consumer.count(b'Button(action: request.perform)') == 1
assert b'.hanlinFollowLatestSceneOverlayHost' not in consumer and b'.hanlinFollowLatestOverlaySource' not in consumer
assert git_hash('blob', consumer) == '00108593ef058d881b522f606c8818bbaf974f0e'
assert sha(consumer) == '7942241949bb2f6b0ff7639e093791033712c88f2882856daab95f670eb05dec'
consumer_receipt_raw = (WORK / 'hanlin-sdk4cb-host-integration-prepared/integration.original.json').read_bytes()
assert sha(consumer_receipt_raw) == '7efdf7e39beecfdd701c382db1afa07167706cfd9822ec877f262353ee34f2a6'
consumer_receipt = json.loads(consumer_receipt_raw)
assert consumer_receipt['head'] == consumer_receipt['normalPushReadback'] == '919626d8a5a2701c2dfb56277a657fa593700b98'

write(ROOT / 'proposed' / PATH, candidate)
write(ROOT / 'primary' / BASE / 'Packages/HanlinPresentationSDK/Package.swift', old_manifest_raw)
proof = {
    'schema': 'pinkha-selective-original-native-follow-host-source-proof/v1',
    'state': 'SOURCE_PROPOSAL_ONLY_NOT_PUBLISHED_NOT_COMPILED_NOT_RUNTIME_ACCEPTANCE',
    'canonicalOriginal': BASE, 'accepted63CandidateTree': packet['expectedTree'], 'originalDonor': DONOR,
    'originalDonorParent': PARENT, 'originalDonorTree': commit['commit']['tree']['sha'],
    'path': PATH, 'before': ident(original), 'originalDonorFile': ident(donor), 'proposed': ident(candidate),
    'literalInverses': ops, 'all3InversesRestoreCompleteOriginalFile': True,
    'originalPublishedDeltaReconstruction': 'UIKit import + exact private helper pair + both original call substitutions reproduce every byte of2b9 from08be. Only the existing4cb host call is applicable to this consumer.',
    'publicAPIAndGuards': {'publicViewExtensionBytesRetained': True, 'requestPreferenceEnvironmentDeclarationsRetained': True,
                           'originalCurrentSelectionAndGuardedActionBytesRetained': True,
                           'ownerTokenIdentityAnimationAndFiniteGeometryChecksRetained': True},
    'packageProjection': {'beforeTree': pkg['proposedTree'], 'afterTree': new_tree, 'originalFiles':455,'proposedFiles':455,
                           'allOther454LeavesExact': True,'fourPackageTotalFiles':1010,
                           'fourPackageSourceBytes':39792490+len(candidate)-len(original),
                           'unchangedCurrentManifest':ident(old_manifest_raw), 'excludedDonorManifest':ident(manifest)},
    'explicitExclusions': ['No full2b9 branch adoption.', 'Do not import the differing donor Package.swift or dependency conditions.',
                           'The preceding08be scene-source/scene-host public API additions are not needed by the current Anytype modal and are not included.',
                           'No current scrolling owner/probe/generation/test/Composer/stream/permission/save/cancellation code changes.',
                           'Frozen63 publication packet and materializer988 remain unchanged.'],
    'consumer': {'path':consumer_path,**ident(consumer),'sourceReceipt':'919626d8a5a2701c2dfb56277a657fa593700b98',
                 'entry':'.hanlinFollowLatestOverlayHost outside the original NavigationStack',
                 'control':'Existing native SwiftUI Button(action: request.perform),44scaled points, same label, Material and Circle shape.',
                 'authority':'Selected conversation binding revalidates original presentation; transcript action rechecks current mounted session and uses original autoFollow/nativeViewport generation.',
                 'hostEditsRequired':0},
    'lifetimeReview': ['Each actual overlay frame has an anchor-sized hosting-controller view; the rest of the overlay has no added UIKit view.',
                       'The current guarded original Button and full EnvironmentValues are replaced on every update.',
                       'Dismantle replaces control with nil and the captured environment with a fresh value, releasing both.',
                       'safeAreaRegions is empty because the original measured anchor already accounts for keyboard/safe-area placement; no second inset is added.',
                       'No custom gesture, copied scroll policy, new runtime authority, cached CGRect, new package dependency or artificial tap is introduced.'],
    'ownerEvidenceScope': {'task':'1220927011075841','lastReportedAt':'2026-11-27T13:27:46Z',
                           'source':'270c1eb67bea1c425b49523f109385c4daa43e60','publishedEquivalent':DONOR,
                           'reported':'Focused file compile and G26 build passed; phone arrow passed; iPad passed click/manual-scroll stage then failed rotated keyboard viewport.',
                           'qualification':'Owner Asana report only in this audit; raw G26 receipts/products not independently admitted. This is not Pinkha or complete iPad acceptance.'},
    'futureAcceptance': ['Compile exact candidate in the common Anytype Apple host.',
                         'Existing20 original UIKit control methods remain NOT_RUN and unchanged; they do not alone prove this new UIViewControllerRepresentable overlay hit-routing.',
                         'Actual Anytype Hanlin follow button on iPhone/iPad must retain original live selection, touch, keyboard/rotation, environment, locale/RTL and teardown behavior. Owner rotated viewport failure remains open.'],
    'testsExecuted':0,'compilerInvocations':0,'remoteMutations':0,
}
write(ROOT / 'minimal-source-and-consumer-proof.json', (json.dumps(proof, indent=2, sort_keys=True)+'\n').encode())
print(json.dumps({'path':PATH,'before':ident(original),'proposed':ident(candidate),'proposedPresentationTree':new_tree,
                  'full4PackageSourceBytes':proof['packageProjection']['fourPackageSourceBytes']},indent=2))
