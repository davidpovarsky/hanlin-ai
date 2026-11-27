"""Exact local source/inverse projection only. No remote, Swift, build or test."""
from pathlib import Path
import copy
import difflib
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
WORK = HERE.parent
DONOR = 'abd1434f8674fd58129c93be5bf33933eda48e1d'
DONOR_PARENT = '2b9ef06cc0fdb89e43ef646e040346948a5ba36e'
HANDLE = 'Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Scrolling/ChatScrollViewHandle.swift'
TEST = 'AI_HLYTests/ChatScrollViewHandleTests.swift'
HOST = 'Modules/PinkhaAnyHanlin/Sources/PinkhaHanlinUI/PinkhaHanlinChatView.swift'
AUTOFOLLOW = WORK/'hanlin-scroll-producer-ownership-review/uikit20-complete-scope/originals/ChatAutoFollowTests.swift'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def git_blob(raw): return hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
def ident(raw): return {'bytes': len(raw), 'sha256': sha(raw), 'gitBlob': git_blob(raw)}
def encoded(value): return (json.dumps(value, indent=2, sort_keys=True)+'\n').encode()
def save(path, raw):
    assert not path.exists(), path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)


def inverse(before, after):
    """Closed literal line-range edits; reverse positions bind every old byte."""
    a, b = before.decode().splitlines(True), after.decode().splitlines(True)
    ops=[]
    for tag, i, j, k, l in difflib.SequenceMatcher(None,a,b,autojunk=False).get_opcodes():
        if tag == 'equal': continue
        ops.append({'beforeLineRange':[i,j], 'afterLineRange':[k,l],
                    'beforeText':''.join(a[i:j]), 'afterText':''.join(b[k:l])})
    restored=list(b)
    for op in reversed(ops):
        k,l=op['afterLineRange']; assert ''.join(restored[k:l])==op['afterText']
        restored[k:l]=op['beforeText'].splitlines(True)
    assert ''.join(restored).encode()==before
    return {'before':ident(before),'after':ident(after),'operations':ops,'completeOriginalRestored':True}


def methods(text):
    rows=[]
    for match in re.finditer(r'^    @Test func (\w+)\(',text,re.M):
        tail=text[match.start():]
        end=re.search(r'^    }\n',tail,re.M)
        assert end, match.group(1)
        raw=tail[:end.end()].encode()
        rows.append({'name':match.group(1),'declaration':ident(raw),
                     'expectations':raw.count(b'#expect('),'parameterized':False})
    return rows


commit=json.loads((HERE/'commit.original.json').read_bytes())
assert commit['sha']==DONOR and commit['commit']['tree']['sha']=='421e2209c6f76d6f7a6cfd730471d65bcc7f595c'
assert [p['sha'] for p in commit['parents']]==[DONOR_PARENT]
assert {p['filename'] for p in commit['files']}=={HANDLE,TEST,'AI_HLY/ChatView.swift'}
for row in commit['files']:
    raw=(HERE/'primary'/DONOR/row['filename']).read_bytes()
    assert git_blob(raw)==row['sha']

inverses={}; sources=[]
for path in (HANDLE, TEST):
    before=(HERE/'primary'/DONOR_PARENT/path).read_bytes()
    current=(WORK/'hanlin-scroll-producer-ownership-review/candidate'/path).read_bytes()
    assert before==current
    after=(HERE/'primary'/DONOR/path).read_bytes()
    save(HERE/'proposed-sdk'/path,after)
    inverses[path]=inverse(before,after)
    sources.append({'path':path,'before':ident(before),'after':ident(after),
                    'publishedDonorParentEqualsCanonical4cb':True,
                    'afterEqualsCompletePublishedDonor':True})

before=(WORK/'hanlin-native-follow-host2b9-review/primary/anytype919'/HOST).read_bytes()
assert sha(before)=='7942241949bb2f6b0ff7639e093791033712c88f2882856daab95f670eb05dec'
host=before.decode()
changes=[
('''        nativeViewport.whenReady(conversationID: sessionID) {''',
 '''        guard nativeViewport.layout(conversationID: sessionID) != nil else { return }
        let bindingGeneration = nativeViewport.bindingGeneration
        nativeViewport.whenReady(conversationID: sessionID,
                                 expectedBindingGeneration: bindingGeneration) {'''),
('''        nativeViewport.readPositionAfterLayout(conversationID: sessionID) { position in''',
 '''        guard nativeViewport.layout(conversationID: sessionID) != nil else { return }
        let bindingGeneration = nativeViewport.bindingGeneration
        nativeViewport.readPositionAfterLayout(conversationID: sessionID,
                                              expectedBindingGeneration: bindingGeneration) { position in'''),
('''        let generation = nativeViewport.generation
        autoFollow.scheduleScroll(animated: animated, force: force) { requestedAnimation in''',
 '''        let bindingGeneration = nativeViewport.bindingGeneration
        autoFollow.scheduleScroll(animated: animated, force: force) { requestedAnimation in'''),
('''                                        expectedGeneration: generation)?.hasScrollableContent == true else { return }''',
 '''                                        expectedBindingGeneration: bindingGeneration)?.hasScrollableContent == true else { return }''')]
for old,new in changes:
    assert host.count(old)==1
    host=host.replace(old,new,1)
restored=host
for old,new in reversed(changes):
    assert restored.count(new)==1
    restored=restored.replace(new,old,1)
assert restored.encode()==before
after=host.encode();save(HERE/'proposed-anytype'/HOST,after)
inverses[HOST]=inverse(before,after)
inverses[HOST]['orderedWholeLiteralOperations']=[{'beforeText':a,'afterText':b} for a,b in changes]
start=before.index(b'private final class PinkhaHanlinNativeIdleWitness')
end=before.index(b'private struct PinkhaHanlinConnectionView',start)
witness=before[start:end]
assert witness in after
assert before[before.index(b'private struct PinkhaHanlinConnectionView'):]==after[after.index(b'private struct PinkhaHanlinConnectionView'):]

old_test=(HERE/'primary'/DONOR_PARENT/TEST).read_text()
new_test=(HERE/'primary'/DONOR/TEST).read_text()
old_methods=methods(old_test); new_methods=methods(new_test)
assert len(old_methods)==18 and len(new_methods)==21
assert new_methods[:18]==old_methods
assert old_test.endswith('}\n') and new_test.startswith(old_test[:-2])
new_names=[m['name'] for m in new_methods[18:]]
assert new_names==['bindingBoundReadsDeliverTheLatestResizeOnceWithoutAnotherNotification',
                   'bindingBoundWorkStillRejectsEveryNativeOwnerReplacement',
                   'coalescedFollowUsesFreshSameBindingLayoutWithoutResumingManualReading']
payload20=json.loads((WORK/'hanlin-scroll-producer-ownership-review/uikit20-complete-scope/proposed-uikit20-dispatch-payload.json').read_bytes())
old_selectors=payload20['inputs']['exact_test_selector'].split(',')
assert len(old_selectors)==20
added=['AI_HLYTests/ChatScrollViewHandleTests/'+name+'()' for name in new_names]
selectors=old_selectors+added
auto=AUTOFOLLOW.read_bytes();assert sha(auto)=='f035c0ad0df4abf9888189273738b7054d99e21d98fc3ee0c68456d8e8a71597'
autodecls={x['name']:x for x in methods(auto.decode())}
for selector in old_selectors[18:]: assert selector.rsplit('/',1)[1][:-2] in autodecls
inventory={'schema':'hanlin-original-uikit23-source-inventory/v1','status':'NOT_RUN',
 'originalDonor':DONOR,'originalDonorTree':commit['commit']['tree']['sha'],
 'canonicalCandidateCommit':None,'sourceProjectionOnly':True,
 'originalTarget':'AI_HLYTests','originalImportedModule':'AI_Hanlin',
 'sameTwoCompilerSourceFiles':True,'selectedMethods':23,'selectedCases':23,
 'original20OrderedPrefixUnchanged':True,'all18PreviousHandleDeclarationsByteIdentical':True,
 'allOtherAutoFollowSourceByteIdentical':True,'parameterizedCases':False,
 'internalLoopsAreNotSeparateSwiftTestingCases':True,'selectors':selectors,
 'newMethods':new_methods[18:],'handleMethods':new_methods,
 'autoFollowSelectedMethods':[autodecls[s.rsplit('/',1)[1][:-2]] for s in old_selectors[18:]],
 'sourceFiles':[{'path':TEST,'originalLocalPath':str(HERE/'primary'/DONOR/TEST),**ident(new_test.encode())},
                {'path':'AI_HLYTests/ChatAutoFollowTests.swift','originalLocalPath':str(AUTOFOLLOW),**ident(auto)}],
 'futureAnytypeAdaptation':'Apple lane owns only exact two import substitutions plus original HanlinChatUI product linkage and closed actual compiler/result admission. No runtime acceptance inferred here.'}
save(HERE/'original-uikit23-source-inventory.json',encoded(inventory))

frozen=json.loads((WORK/'hanlin-sdk-native-follow-host-publication/payload.json').read_bytes())
closure=copy.deepcopy(frozen['packageClosure'])
for p in closure['packages']:
    if p['package']!='Packages/HanlinPresentationSDK':continue
    relative=HANDLE.removeprefix(p['package']+'/'); leaves=p['completeProposedLeaves']
    row=next(x for x in leaves if x['path']==relative)
    assert row['sha']==inverses[HANDLE]['before']['gitBlob']
    row['sha']=inverses[HANDLE]['after']['gitBlob']
    node={}
    for leaf in leaves:
        parts=leaf['path'].split('/');current=node
        for part in parts[:-1]:current=current.setdefault(part,{})
        assert parts[-1] not in current;current[parts[-1]]=leaf
    def tree(entries):
        values={n:{'mode':v['mode'],'sha':v['sha']} if 'mode' in v else {'mode':'40000','sha':tree(v)} for n,v in entries.items()}
        names=sorted(values,key=lambda n:(n+('/' if values[n]['mode']=='40000' else '')).encode())
        raw=b''.join(values[n]['mode'].encode()+b' '+n.encode()+b'\0'+bytes.fromhex(values[n]['sha']) for n in names)
        return hashlib.sha1(b'tree '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
    presentation={'beforeTree':p['proposedTree'],'afterTree':tree(node),'files':len(leaves),
                  'unchangedLeaves':len(leaves)-1,'onlyChangedLeaf':relative}
    assert presentation['beforeTree']=='2baee0bb044274da5adc395677dec54fc1342862'
save(HERE/'source-full-inverses.json',encoded({'schema':'hanlin-g27-exact-source-inverses/v1','files':inverses,'allCompleteOriginalsRestored':True}))
sdkpatch=''.join(''.join(difflib.unified_diff((HERE/'primary'/DONOR_PARENT/path).read_text().splitlines(True),
 (HERE/'primary'/DONOR/path).read_text().splitlines(True),fromfile='canonical/'+path,tofile='proposed/'+path)) for path in (HANDLE,TEST))
save(HERE/'minimal-sdk-and-test.patch',sdkpatch.encode())
save(HERE/'minimal-anytype-host.patch',''.join(difflib.unified_diff(before.decode().splitlines(True),after.decode().splitlines(True),fromfile='current794224/'+HOST,tofile='proposed/'+HOST)).encode())
report={'schema':'hanlin-g27-original-binding-source-review/v1','status':'SOURCE_ONLY_PROPOSED_NOT_PUBLISHED_OR_COMPILED',
 'repository':'davidpovarsky/hanlin-ai','publishedDonor':DONOR,'publishedDonorParent':DONOR_PARENT,
 'publishedDonorTree':commit['commit']['tree']['sha'],'originalLocalSourceClaim':'5c9d7c723eabf6d7a184eb2cf14fd53308c6b936',
 'sdkFiles':sources,'anytypeHost':{'path':HOST,'before':ident(before),'after':ident(after),
     'changedFunctions':['scheduleWhenReady','scheduleNativePositionRead','scheduleFollow'],
     'literalChanges':4,'completeInverseVerified':True,'foregroundNativeIdleWitnessUnchanged':ident(witness),
     'accountSessionMountSourceRunComposerSaveStopAndDrainUnchanged':True},
 'packageProjection':{'frozen19BaseTree':frozen['expectedTree'],'beforeFiles':1010,'afterFiles':1010,
     'beforeSourceBytes':39794445,'afterSourceBytes':39794445+inverses[HANDLE]['after']['bytes']-inverses[HANDLE]['before']['bytes'],
     'presentation':presentation,'allOtherPackagesUnchanged':True,'allManifestsLocks227RowsAndHandlerWireUnchanged':True},
 'findings':[
    'The exact parent handle and test file equal canonical4cb; both can be taken whole from the published donor without importing other branch ancestry.',
    'The original generation remains strict for viewport APIs. The new optional binding token admits latest geometry only for the same view/producer/window/conversation/activation lifetime.',
    'Refresh checks ownership both before and after observing UIKit. Window movement changes the binding token, invalidates tasks and rejects stale work.',
    'Explicitly binding-bound queued work survives only bounds/inset changes. Manual-reading and interaction state remain owned by the unchanged original AutoFollow controller.',
    'Current Pinkha794224 still uses strict generation at all three deferred sites, so merely installing the new SDK would not close its resize gap. The proposed host adopts the original API only at these sites.',
    'The weak foreground idle witness remains strict and byte-identical; actual native idle is still required before ending an interrupted gesture.',
    'All old18 Handle declarations, all AutoFollow source and original20 selector prefix remain exact;3 original nonparameterized methods extend selection to23.',
    'Original App ChatView is reference evidence only. Its unrelated UI and the excluded donor package manifest are not part of this proposal.'
 ],
 'runtime':{'all23Methods':'NOT_RUN','newOverlayAndResizeHostBehavior':'NOT_RUN','owner80PlannedMethods':'NOT_RUN per13:53 task notes, not independently executed',
     'ownerG26PhonePass':'Owner-reported original source scope only; not Pinkha acceptance',
     'ownerG26IPadRotatedKeyboardViewport':'Original failure preserved; no fix acceptance inferred from source',
     'original4cbUIKit20':'Build failed before original validator/runtime. No original20 result promoted.'},
 'actions':{'remoteReadsOnly':True,'remoteMutations':0,'SwiftCompilers':0,'runtimeTests':0,'workflowDispatches':0,'materializations':0}}
save(HERE/'review.json',encoded(report))
print(json.dumps({'report':ident(encoded(report)),'hostAfter':ident(after),'presentationProjection':presentation,'methods':23},indent=2))
