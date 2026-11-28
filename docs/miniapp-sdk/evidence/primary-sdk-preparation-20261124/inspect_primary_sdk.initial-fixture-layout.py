#!/usr/bin/env python3
"""Read-only artifact/Git reconciliation. Does not execute project generators or tests."""
import collections, datetime, difflib, gzip, hashlib, json, pathlib, re, shutil, subprocess, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[4]
OUT = pathlib.Path(__file__).resolve().parent
SNAP = pathlib.Path('/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt5')
BASE = '340018ddc9ea2395ffabedbf179369b5bdb791af'
CHECKPOINT = 'b3a7c56fa6b691503fff04a0ddd5a1eeb6f736be'
PRIOR = 'docs/miniapp-sdk/evidence/sdk05-shipping-main16-20261124/'
NS_PREFIX = 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/'
PREP = 'Scripts/NativeScript/prepare-ios-dependencies.mjs'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def emit(name, obj):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n')
    return {'path': name, 'bytes': path.stat().st_size, 'sha256': sha(path.read_bytes())}

cache = {}
def git(path, ref=BASE):
    key = (ref, path)
    if key not in cache:
        cache[key] = subprocess.check_output(['git', 'show', ref + ':' + path], cwd=ROOT)
    return cache[key]

def dump_raw(name, data):
    path = OUT / 'raw' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return {'path': str(path.relative_to(OUT)), 'bytes': len(data), 'sha256': sha(data)}

receipt_bytes = (SNAP/'receipt.json').read_bytes()
assert sha(receipt_bytes) == 'fbcae6ab65a1d090bf9470c81c8208ec44b38c36d4116433ad4944517e0121a4'
receipt = json.loads(receipt_bytes)
ledger_bytes = (SNAP/'tracked-delta.json').read_bytes()
assert sha(ledger_bytes) == 'b4381014062cca249740e1ff83c6d78d07680c2b27b51ac0569f2ea96e1a20ff'
ledger = json.loads(ledger_bytes)
overlay = {row['path']: row for row in ledger}
def current(path):
    return (SNAP/overlay[path]['contentFrom']).read_bytes() if path in overlay else git(path)

archive = SNAP/'files/build/runtime-host/RuntimeHostResources.zip'
archive_digest = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
assert archive_digest == '5d6d60076fc95165b7c3d330d4202388dc88c3084899291918c69fef3ba92c53'
z = zipfile.ZipFile(archive)
manifest_bytes = z.read('MiniAppSDK/miniapp-sdk.json')
assert manifest_bytes == (SNAP/'extracted-sdk/miniapp-sdk.json').read_bytes()
assert sha(manifest_bytes) == '1d51c86e55ca79792b6b31176de6363008e5874dec4f919e5ef96c789a6d53f9'
manifest = json.loads(manifest_bytes)
prior_manifest_bytes = gzip.decompress(git(PRIOR+'raw/miniapp-sdk.json.gz', CHECKPOINT))
prior_manifest = json.loads(prior_manifest_bytes)
assert sha(prior_manifest_bytes) == 'f84b79a3d9c4f7dc541d6912753cd1be95bfa3ed1876cc4d0ead365aadab12fc'
input_digest = sha(json.dumps(manifest['sourceInputs'], ensure_ascii=False, separators=(',', ':')).encode())
assert input_digest == manifest['inputSHA256'] == '5deb2605a46b128985a0f6bb59414aed8167d872cc09deaf24b49fd9ab4fce04'
previous_inputs = {r['path']:r for r in prior_manifest['sourceInputs']}
current_inputs = {r['path']:r for r in manifest['sourceInputs']}
previous_files = {r['path']:r for r in prior_manifest['files']}
current_files = {r['path']:r for r in manifest['files']}
assert previous_inputs.keys() == current_inputs.keys()
assert previous_files.keys() == current_files.keys()
source_changes = [{'path':p, 'before':previous_inputs[p], 'after':current_inputs[p]} for p in current_inputs if current_inputs[p] != previous_inputs[p]]
member_changes = []
for p in current_files:
    if current_files[p] == previous_files[p]:
        continue
    body = z.read('MiniAppSDK/'+p)
    assert sha(body) == current_files[p]['sha256'] and len(body) == current_files[p]['bytes']
    member_changes.append({'path':p, 'before':previous_files[p], 'after':current_files[p],
                           'actualMemberVerified':True, 'retained':dump_raw('changed-sdk/'+p, body)})
assert len(source_changes) == len(member_changes) == 4
source_binding = []
for p, row in current_inputs.items():
    body = current(p)
    actual = sha(body)
    source_binding.append({'path':p, 'expected':row['sha256'], 'actual':actual,
                           'source':'authenticated-prepared-overlay' if p in overlay else BASE,
                           'matches':actual == row['sha256']})
assert all(r['matches'] for r in source_binding)
emit('sdk-source-binding.json', {'base':BASE,'overlayLedgerSHA256':sha(ledger_bytes),
     'count':len(source_binding), 'allMatch':True, 'rows':source_binding})
raw = [dump_raw('snapshot-receipt.json', receipt_bytes), dump_raw('tracked-delta.json', ledger_bytes),
       dump_raw('miniapp-sdk.json.gz', gzip.compress(manifest_bytes, mtime=0))]
raw[-1]['uncompressedSHA256'] = sha(manifest_bytes)
raw[-1]['uncompressedBytes'] = len(manifest_bytes)

# Retain actual small preparation outputs, never duplicate SDK/native archive or payload tree.
for rel in ['build/app-split-evidence/miniapp-documentation-snippets.json',
            'build/app-split-evidence/prepared-native/native-artifacts.json',
            'build/primary-control/logs-attempt5/split-native-preparation.log',
            'build/primary-control/logs-attempt5/split-native-artifacts.log',
            'build/runtime-host/host-metadata.json']:
    raw.append(dump_raw(rel, (SNAP/'files'/rel).read_bytes()))
emit('retained-raw-files.json', raw)

doc_bytes = (SNAP/'files/build/app-split-evidence/miniapp-documentation-snippets.json').read_bytes()
doc = json.loads(doc_bytes)
old_doc = json.loads(git(PRIOR+'raw/app-split-evidence/miniapp-documentation-snippets.json', CHECKPOINT))
assert doc['status'] == 'EXECUTED_PASS'
assert doc['sourceBlockCount'] == 14 and doc['jsonBlockCount'] == 7 and len(doc['excluded']) == 8
guide_bindings = []
for row in doc['documentation']:
    p = row['path']
    body = z.read('MiniAppSDK/'+p)
    actual = sha(body)
    guide_bindings.append({'path':p, 'reported':row, 'actualMemberSHA256':actual,
                           'gitSHA256':sha(current(p)),
                           'sameAsMain16Member':current_files[p] == previous_files[p]})
    assert row['sha256'] == actual == sha(current(p))
    assert row['stagedSDKMatches'] is True
checker_bindings = []
for row in doc['checkerInputs']:
    actual = sha(current(row['path']))
    assert actual == row['sha256']
    checker_bindings.append({**row, 'currentSourceMatches':True})
projects = []
old_projects = {p['name']:p for p in old_doc['projects']}
for p in doc['projects']:
    v = p['validation']; old = old_projects[p['name']]
    assert v['succeeded'] and not v['diagnostics']
    assert v['sdk']['manifestSHA256'] == sha(manifest_bytes)
    same_contract = {
        'snippets':p['snippets'] == old['snippets'],
        'context':p['context'] == old['context'],
        'typecheck':v['typecheck'] == old['validation']['typecheck'],
        'compilerVersion':v['sdk']['compilerVersion'] == old['validation']['sdk']['compilerVersion'],
        'packageVersions':v['sdk']['packageVersions'] == old['validation']['sdk']['packageVersions']}
    assert all(same_contract.values())
    projects.append({'name':p['name'],'engine':p['engine'],'succeeded':v['succeeded'],
                     'diagnostics':v['diagnostics'],'compilerVersion':v['sdk']['compilerVersion'],
                     'typecheck':v['typecheck'], 'sameContractAsMain16':same_contract})
registration = doc['registration']
assert sha(current(registration['nativePath'])) == registration['nativeSessionSHA256']
assert registration == old_doc['registration']
emit('documentation-execution-binding.json', {
    'actualReportSHA256':sha(doc_bytes),'status':doc['status'],
    'projectCount':len(projects),'diagnosticCount':0,'sourceFences':14,'jsonFences':7,
    'explicitNonAuthoringExclusions':len(doc['excluded']),'totalFences':29,
    'projects':projects,'guideBindings':guide_bindings,'checkerBindings':checker_bindings,
    'registration':registration,'boundary':doc['boundary'],
    'executionReused':'Original primary preparation; this inspection executed no compiler or checker.'})

# Bind shipped inventory and reachability to the actual execution source/overlay.
inventory = json.loads((SNAP/'files/docs/miniapp-sdk/source-inventory.json').read_text())
reachability = json.loads((SNAP/'files/docs/miniapp-sdk/extension-reachability.json').read_text())
provenance_bindings = []
for name, rows in [('inventory.sources',inventory['sources']),('reachability.sdkSources',reachability['sdkSources'])]:
    for row in rows:
        actual = sha(current(row['path']))
        assert actual == row['sha256'], (name,row['path'],actual,row['sha256'])
        provenance_bindings.append({'group':name,'path':row['path'],'sha256':actual})
def collect_refs(v, context='sourceRefs'):
    rows=[]
    if isinstance(v,dict):
        if isinstance(v.get('file'),str) and isinstance(v.get('sha256'),str):
            actual=sha(current(v['file']))
            assert actual == v['sha256'], (context,v['file'])
            rows.append({'context':context,'path':v['file'],'sha256':actual})
        for k,value in v.items():
            if isinstance(value,(dict,list)): rows.extend(collect_refs(value,context+'.'+k))
    elif isinstance(v,list):
        for i,value in enumerate(v): rows.extend(collect_refs(value,context+'.'+str(i)))
    return rows
refs=collect_refs(reachability['sourceRefs'])
assert inventory['sourceCommit'] == reachability['sourceCommit'] == BASE
emit('shipped-provenance-binding.json', {
    'sourceCommit':BASE,'inventorySourceCount':len(inventory['sources']),
    'reachabilitySDKSourceCount':len(reachability['sdkSources']),'sourceRefCount':len(refs),
    'allBoundHashesMatch':True,'sourceRows':provenance_bindings,'sourceRefs':refs,
    'inventoryUncommittedSourcePaths':inventory['uncommittedSourcePaths'],
    'reachabilityUncommittedSourcePaths':reachability['uncommittedSourcePaths'],
    'interpretation':'Empty uncommittedSourcePaths is scoped to each audit source set; it does not assert that all tracked preparation outputs are unchanged.'})

catalog = json.loads((SNAP/'files/build/app-split-evidence/prepared-native/native-artifacts.json').read_text())
native_inputs = []
for p, expected in catalog['inputSHA256'].items():
    actual=sha(current(p)); assert actual == expected
    native_inputs.append({'path':p,'sha256':actual})
emit('native-catalog-binding.json', {
    'catalogSHA256':sha((SNAP/'files/build/app-split-evidence/prepared-native/native-artifacts.json').read_bytes()),
    'state':catalog['state'],'sourceCommit':catalog['sourceCommit'],
    'contentSHA256':catalog['contentSHA256'],'inputBindings':native_inputs,
    'requiredTargets':catalog['requiredTargets'],'missingTargets':catalog['missingTargets'],
    'acceptance':catalog['acceptance'],
    'supportMetadata':[{'target':a['target'],'metadataTool':a.get('metadataTool')} for a in catalog['supportArtifacts']],
    'boundary':'Retained actual exporter catalog and bound input hashes only. Native archive binaries were not transferred or independently rehashed by this inspection; app compilation later failed.'})

# The 167 changed tracked runtime paths are compared to the original npm bodies
# actually present in the final SDK. This is data comparison, not generator replay.
prep_body = git(PREP)
raw.append(dump_raw('source-authority/prepare-ios-dependencies.mjs.gz', gzip.compress(prep_body,mtime=0)))
names=set(z.namelist())
ns_rows=[]; ns_diffs=[]; change_counts=collections.Counter(); origin_counts=collections.Counter(); tag_counts=collections.Counter()
for row in ledger:
    if not row['path'].startswith(NS_PREFIX):continue
    tail=row['path'][len(NS_PREFIX):]; new=(SNAP/row['contentFrom']).read_bytes(); before=git(row['path'])
    if before == new: change='identical-content-observed-mode-row'
    elif tail.endswith('.json'): change='json-values-equal' if json.loads(before)==json.loads(new) else 'json-values-changed'
    elif before.replace(b'\r\n',b'\n') == new.replace(b'\r\n',b'\n'): change='line-endings-only'
    else: change='javascript-body-changed'
    change_counts[change]+=1
    candidates=[tail]
    if tail.endswith('.mjs'): candidates.append(tail[:-4]+'.js')
    for t in list(candidates):
        if t.endswith('.js') and not t.endswith('.ios.js'): candidates.append(t[:-3]+'.ios.js')
    original_name=next('MiniAppSDK/nativescript/node_modules/'+t for t in candidates if 'MiniAppSDK/nativescript/node_modules/'+t in names)
    original=z.read(original_name)
    assert sha(original) == current_files[original_name[len('MiniAppSDK/'):]]['sha256']
    same=original==new
    origin_counts['exact-original-bytes' if same else 'original-plus-existing-preparation-transforms']+=1
    tags=[]
    if not same:
        text=new.decode(); prefix_lines=[]
        for line in text.splitlines(keepends=True):
            if re.fullmatch(r'const (__[A-Z_]+__) = globalThis\.\1 !== undefined \? globalThis\.\1 : [^\n]+;\n',line):
                prefix_lines.append(line)
            else:break
        if prefix_lines:tags.append({'name':'canonical-build-defines','sourceLines':[740,783]})
        core=tail.removeprefix('@nativescript/core/')
        if core.startswith(('color/color-utils.','css/css-tree-parser.','ui/core/properties/index.','ui/styling/css-selector.')):
            tags.append({'name':'external-package-relative-imports','sourceLines':[374,458]})
        if core.startswith('color/color-common.'):
            tags.append({'name':'existing-Color-cross-realm-and-UIColor-adaptation','sourceLines':[584,610]})
        if core.startswith('ui/page/index.'):
            tags.append({'name':'existing-child-view-controller-containment','sourceLines':[681,709]})
        if core.startswith('ui/styling/style-scope.'):
            tags.append({'name':'existing-session-app-config-provider-import','sourceLines':[283,289]})
        if core.startswith('ui/tab-view/index.'):
            tags.append({'name':'existing-embedded-TabView-and-layout-adaptation','sourceLines':[460,516,681,694]})
        if core.startswith('ui/text-base/index.'):
            tags.append({'name':'existing-Color-Font-native-value-unwrapping','sourceLines':[660,679]})
        assert tags, tail
        diff=''.join(difflib.unified_diff(original.decode().splitlines(True),new.decode().splitlines(True),
                     fromfile=original_name,tofile=row['path'],n=2))
        ns_diffs.append(diff)
    for tag in tags:tag_counts[tag['name']]+=1
    out={'path':row['path'],'beforeSHA256':sha(before),'afterSHA256':sha(new),
         'changeFromExecutionBase':change,'originalSDKMember':original_name,
         'originalSHA256':sha(original),'sameAsOriginalBytes':same,
         'copyAuthority':{'path':PREP,'lines':[220,249] if tail.startswith('@nativescript/core/') else [306,336]},
         'existingTransforms':tags}
    if tail.endswith('.mjs'):
        out['shadowCopyAuthority']={'path':PREP,'lines':[232,244]}
    if tail.endswith('.json'):
        oldjson=json.loads(before); newjson=json.loads(new)
        out['changedTopLevelValues']={k:{'before':oldjson.get(k),'after':newjson.get(k)}
             for k in sorted(oldjson.keys()|newjson.keys()) if oldjson.get(k)!=newjson.get(k)}
        out['packageFormattingAuthority']={'path':PREP,'lines':[801,821]}
    ns_rows.append(out)
assert len(ns_rows)==167
assert origin_counts['exact-original-bytes']==105 and origin_counts['original-plus-existing-preparation-transforms']==62
assert change_counts == {'javascript-body-changed':154,'line-endings-only':3,'identical-content-observed-mode-row':1,'json-values-equal':8,'json-values-changed':1}
emit('nativescript-prepared-source-classification.json',{
    'sourceAuthority':{'path':PREP,'commit':BASE,'sha256':sha(prep_body)},
    'originalAuthority':'Exact original npm member bytes in authenticated final RuntimeHostResources.zip / MiniAppSDK',
    'countsByDelta':dict(change_counts),'countsByOriginalIdentity':dict(origin_counts),
    'transformTagCounts':dict(tag_counts),'rows':ns_rows,
    'boundaries':['No preparation code was executed or modified.',
                  '105 paths equal the mapped original body; .mjs and iOS aliases may copy a differently named original source.',
                  '62 paths carry existing Hanlin preparation adaptations; these are not described as unmodified upstream bytes.',
                  'The tracked Core package moves from9.1.0 to resolved9.1.4 and adds its original semver dependency.',
                  'This classification establishes source provenance, not app/native behavior.']})
dump_raw('nativescript-original-to-prepared.diff.gz',gzip.compress(''.join(ns_diffs).encode(),mtime=0))

# Classify all materialization categories without copying the 17MB source payload.
groups=collections.Counter()
for r in ledger:
    if r['path'].startswith(NS_PREFIX): group='nativescript-prepared-runtime'
    elif r['path'].endswith('.hanlinExpo'): group='actual-generated-expo-fixture-archive'
    elif r['path'].endswith('/Package.resolved'): group='resolved-Swift-package-lock'
    elif r['path'].endswith('original-runtime-receipt.json'): group='original-Expo-Widgets-preparation-receipt'
    elif r['path'].startswith('docs/miniapp-sdk/'): group='shipped-source-provenance'
    else:raise AssertionError(r['path'])
    groups[group]+=1
fixture_pairs=[]
for r in ledger:
    p=r['path']
    if p.startswith('Fixtures/') and p.endswith('.hanlinExpo'):
        mirror='AI_HLYUITests/'+p
        other=overlay[mirror]
        assert r['sha256']==other['sha256']
        fixture_pairs.append({'source':p,'mirror':mirror,'sha256':r['sha256'],
                              'interpretation':'Actual preparation output copied by existing producer; no import/render acceptance claimed.'})
widget_path=next(r['path'] for r in ledger if r['path'].endswith('original-runtime-receipt.json'))
before_widget=json.loads(git(widget_path)); after_widget=json.loads(current(widget_path))
widget_changes={k:{'before':before_widget.get(k),'after':after_widget.get(k)}
    for k in sorted(before_widget.keys()|after_widget.keys()) if before_widget.get(k)!=after_widget.get(k)}
assert set(widget_changes)=={'inputSHA256','packageLockSHA256'}
emit('materialization-category-advice.json',{
    'exactExecutionBase':BASE,'evidenceBase':CHECKPOINT,'payloadRoot':str(SNAP),
    'ledgerPath':str(SNAP/'tracked-delta.json'),'ledgerSHA256':sha(ledger_bytes),
    'counts':dict(groups),'fixturePairs':fixture_pairs,
    'widgetRuntimeReceipt':{'path':widget_path,'beforeSHA256':sha(git(widget_path)),
        'afterSHA256':sha(current(widget_path)),'changedValues':widget_changes},
    'applyPolicy':'Use only authenticated contentFrom paths, require destination before SHA from ledger, preserve unrelated source and AGENTS. No production source application was performed in this lane.',
    'modeBoundary':'One identical-content css-tree/lib/data.js row has observed transferred0755 versus Git100644. The ledger has no original mode field; do not invent authenticated chmod provenance.',
    'reasonAllCategoriesMatter':'The native preparation materialized current original Core bodies and real fixture archives beyond the four SDK-member delta. Limiting publication to shipped docs would leave the Git checkpoint different from the prepared execution.'})
reuse_groups={}
for group,predicate in [
    ('declarations',lambda p: p.endswith(('.d.ts','.d.mts','.d.cts'))),
    ('examples',lambda p: p.startswith('examples/')),
    ('public-docs',lambda p: p.startswith('docs/')),
    ('original-compilers',lambda p: p in ['expo/node_modules/typescript/lib/typescript.js','nativescript/node_modules/typescript/lib/typescript.js'])]:
    paths=[p for p in current_files if predicate(p)]
    reuse_groups[group]={'members':len(paths),'unchanged':sum(current_files[p]==previous_files[p] for p in paths),
                         'changed':[p for p in paths if current_files[p]!=previous_files[p]]}
host=json.loads((SNAP/'files/build/runtime-host/host-metadata.json').read_text())
assert host['archiveSha256']==archive_digest
emit('sdk-reconciliation.json',{
    'executionSource':BASE,'evidenceBase':CHECKPOINT,'archivePath':str(archive),
    'archiveBytes':archive.stat().st_size,'archiveSHA256':archive_digest,
    'manifestSHA256':sha(manifest_bytes),'manifestBytes':len(manifest_bytes),
    'inputSHA256':manifest['inputSHA256'],'sourceInputCount':len(current_inputs),'fileCount':len(current_files),
    'prior':{'source':'7d1efaa6ada43dd80c57133c09e6a8fb327075cf','evidencePath':PRIOR,
        'manifestSHA256':sha(prior_manifest_bytes),'inputSHA256':prior_manifest['inputSHA256']},
    'sourceInputs':{'changed':source_changes,'unchanged':len(current_inputs)-len(source_changes),'added':[],'removed':[]},
    'members':{'changed':member_changes,'unchanged':len(current_files)-len(member_changes),'added':[],'removed':[]},
    'reuseGroups':reuse_groups,'upstream':manifest['upstream'],
    'toolchains':{k:{'typescript':v.get('typescript'),'installationInputs':v.get('installation',{}).get('inputs'),
                    'typeCheckingPolicy':v.get('typeCheckingPolicy')} for k,v in manifest['engines'].items()},
    'hostMetadata':host,'phaseReceipts':receipt['phaseReceipts'],
    'nativeBoundary':{'miniAppsBuild':'FAILED','miniAppsExitCode':65,'miniAppsFinishedAt':'2026-11-24T20:09:11Z',
        'miniAppsElapsedSecondsApprox':202.4,'statusAuthority':'Parent correction after owner read terminal result; root owns exact native failure receipt.',
        'aiBuild':'NOT_RUN','selected52AppCases':'NOT_RUN','physicalDevice':'NOT_RUN',
        'rawSnapshotAppAcceptance':receipt['appAcceptance'],
        'supersedes':'The raw snapshot RUNNING text was stale at capture; preserve it as raw and do not use it as current status.'},
    'inspectionBoundary':['No compiler, generator, app build, test, CI poll, network request, or SDK staging was executed.',
        'Archive inspected in place; no SDK/archive/payload duplicate created.',
        'Four changed SDK bodies and six guide bodies were read; this is not a new112-member audit.',
        'Unchanged previous member proof reused only for exact matching manifest entries; no native OS semantic success inferred.']})
print(json.dumps({'status':'PASS','manifestSHA256':sha(manifest_bytes),'inputSHA256':input_digest,
      'sourceInputs':len(current_inputs),'files':len(current_files),'changedInputs':len(source_changes),
      'changedMembers':len(member_changes),'docProjects':len(projects),'diagnostics':0,
      'nativeScriptDelta':dict(change_counts),'originalIdentity':dict(origin_counts),
      'materializationGroups':dict(groups),'reuseGroups':reuse_groups},indent=2))
