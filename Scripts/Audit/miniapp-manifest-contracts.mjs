// Describes existing readers; this source inventory is not another validator.
import {createHash} from 'node:crypto';
export const manifestSources = {
  manifest: 'Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinPackageContracts.swift',
  analyzer: 'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift',
  versions: 'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinMiniAppHostVersions.swift',
  versionPolicy: 'Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinPreparedRuntimeVersion.swift',
  registration: 'Packages/HanlinPlatform/Sources/HanlinScriptStore/HanlinStoredPackageSnapshot+MiniAppRegistration.swift',
  platform: 'AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift',
  presentation: 'Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinNativePresentationMetadata.swift',
  widgetCompiler: 'Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/HanlinWidgetCompiler.swift',
  widgetProgram: 'Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinWidgetProgram.swift',
  nsSession: 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift',
  expoSession: 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoSession.swift',
  authoring: 'AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs',
  widgetSchema: 'Scripts/MiniApps/scriptwidget/widget-manifest.schema.json',
  widgetGenerator: 'Scripts/MiniApps/generate-scriptwidget-manifest.mjs',
  widgetValidator: 'Scripts/MiniApps/scriptwidget/manifest-validation.mjs',
  widgetMetadata: 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Common/ScriptMetadata.swift',
  widgetPackage: 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Common/ScriptWidgetPackage.swift',
  widgetNetworkPolicy: 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeFetch.swift',
  widgetControls: 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/HanlinOriginalScriptWidgetControls.swift',
  canonicalSchema: 'Packages/HanlinPlatform/Sources/HanlinPlatformContracts/Resources/HanlinAppManifest.schema.json',
};
const sorted = values => [...new Set(values)].sort();
const digest = value => createHash('sha256').update(value).digest('hex');
function requireMatch(record, expression, label) {
  const match = record.text.match(expression);
  if (!match) throw new Error('Manifest source anchor changed: ' + record.path + ': ' + label);
  return match;
}
function ref(record, anchor, symbol) {
  const index = record.text.indexOf(anchor);
  if (index < 0) throw new Error('Manifest source anchor changed: ' + record.path + ': ' + anchor);
  return {path: record.path, sha256: record.sha256,
    line: (record.lineOffset ?? 0) + record.text.slice(0, index).split('\n').length,
    ...(symbol ? {symbol} : {})};
}
function between(record, start, end) {
  const a = record.text.indexOf(start), b = record.text.indexOf(end, a + start.length);
  if (a < 0 || b < 0) throw new Error('Manifest source scope changed: ' + record.path + ': ' + start);
  return {...record, text: record.text.slice(a, b),
    lineOffset: (record.lineOffset ?? 0) + record.text.slice(0, a).split('\n').length - 1};
}
function declaration(record, name) {
  const match = requireMatch(record, new RegExp('(?:struct|enum) ' + name + '\\b[^\\{]*\\{([\\s\\S]*?)^\\}', 'm'), name);
  return {...record, text: match[0],
    lineOffset: (record.lineOffset ?? 0) + record.text.slice(0, match.index).split('\n').length - 1};
}
function assertKeys(actual, expected, label) {
  const a = sorted(actual), e = sorted(expected);
  if (JSON.stringify(a) !== JSON.stringify(e))
    throw new Error('Unmapped manifest field drift: ' + label + '; actual=' + a.join(',') + '; mapped=' + e.join(','));
}
function reads(record, variable) {
  return sorted([...record.text.matchAll(new RegExp('\\b' + variable + '\\??\\["([^"]+)"\\]', 'g'))].map(m => m[1]));
}
function storedMembers(record, name) {
  const scope = declaration(record, name);
  return [...scope.text.matchAll(/^    (?:public )?(?:let|var) (\w+): ([^\n={]+)(?: = [^\n]+)?$/gm)].map(match => ({
    name: match[1], type: match[2].trim(), optional: match[2].trim().endsWith('?'),
    source: ref(scope, match[0], name + '.' + match[1]),
  }));
}
function field(field, type, required, semantics, sources, extra = {}) {
  return {field, type, required,
    status: semantics.startsWith('Metadata:') || semantics.startsWith('Compatibility:') ? 'partial' : 'supported',
    semantics, sources, ...extra};
}
function addDictionary(rows, record, variable, prefix, entries) {
  assertKeys(reads(record, variable), Object.keys(entries), record.path + ':' + prefix);
  for (const [key, [type, required, note]] of Object.entries(entries))
    rows.push(field(prefix + key, type, required, note, [ref(record, variable + '["' + key + '"]')]));
}
function addRecord(rows, record, name, prefix, notes, optionalDefaults = {}) {
  const members = storedMembers(record, name);
  assertKeys(members.map(item => item.name), Object.keys(notes), name);
  for (const item of members)
    rows.push(field(prefix + item.name, item.type, !(item.optional || item.name in optionalDefaults),
      notes[item.name], [item.source], item.name in optionalDefaults ? {decoderDefault: optionalDefaults[item.name]} : {}));
}
const scriptNotes = {
  name: 'Decoded display name; registration uses package ID if blank.',
  version: 'Decoded version; package analysis/installation supplies the semantic version contract.',
  description: 'Decoded summary; registration falls back to display name if absent or blank.',
  localizedNames: 'Locale/name dictionary; defaults empty; registration merges nonblank values.',
  localizedDescriptions: 'Locale/summary dictionary; defaults empty; registration merges nonblank values.',
  author: 'Author object; name required when the object is present.',
  contributors: 'Metadata: author-shaped contributors; absent array defaults empty.',
  icon: 'Nonempty system symbol takes precedence over iconImage.',
  iconImage: 'Package resource icon used when no nonempty system symbol exists.',
  color: 'Accent metadata; registration trims whitespace and adds a leading # when absent.',
  entry: 'Canonical existing package-relative source path; discovery and each engine impose additional rules below.',
  runInApp: 'Compatibility: defaults false; legacy registration fallback when analyzed entrypoints are absent. Modern builders set true; no custom-home entry is added.',
  intentInputTypes: 'Metadata: string array, default empty; alone it neither registers actions nor grants access.',
  remoteResource: 'Metadata: retained remote descriptor; registration advertises remoteUpdates when present, without proving automatic update execution.',
  hanlinAppID: 'Valid canonical app identity; registration otherwise falls back to stored package identity.',
  hanlinRuntime: 'Active foreground values hanlin-expo/hanlin-nativescript. ScriptWidget retains scripting-jsc as compatibility metadata while widgetEngine selects the original renderer.',
};
const extraNotes = {
  capabilities: ['string[]', 'Metadata: collects valid capability IDs; not an additional grant or approval prompt.'],
  widgetEngine: ['HanlinWidgetEngine', 'Explicit renderer; expo requires hanlin-expo, scriptwidget conflicts with hanlin-expo. legacy is compatibility-only.'],
  widget_engine: ['HanlinWidgetEngine', 'widgetEngine alias; all supplied declarations must agree exactly.'],
  engine: ['HanlinWidgetEngine', 'widgetEngine alias; all supplied declarations must agree exactly.'],
  kind: ['string', 'widget suppresses foreground discovery and requires entry; other values do not enable a new surface.'],
  entrypoints: ['object[]', 'Explicit modern exposures in addition to discovered foreground/widget entries.'],
  nativePresentations: ['record<string, HanlinNativePresentationMetadata>', 'Renderer declarations keyed by analyzed entrypoint ID, with source separate from foreground bundles.'],
  hanlinWidget: ['HanlinWidgetPackageMetadata', 'Required metadata for non-legacy widget compilation; decoded fields below.'],
  supportedExposures: ['string[]', 'Metadata: catalog exposure descriptors, not fabricated executable entries; takes precedence over exposures.'],
  exposures: ['string[]', 'Metadata: supportedExposures alias; no connected-executor proof.'],
  category: ['HanlinAppCategory', 'Metadata: recognized category, otherwise utilities.'],
  isBeta: ['boolean', 'Metadata: appearance flag, default false.'],
  actions: ['object[]', 'Metadata: canonical actions; invalid IDs omitted; execution still needs installed declared handlers.'],
  skills: ['object[]', 'Metadata: canonical skills; invalid IDs omitted; instructions and aliases below.'],
};

export async function auditManifestContracts({source}) {
  const records = Object.fromEntries(await Promise.all(Object.entries(manifestSources).map(async ([key, file]) => {
    const value = await source(file);
    if (!value.sha256 || value.sha256 !== digest(value.text)) throw new Error('Manifest source identity mismatch: ' + file);
    return [key, value];
  })));
  const r = records, rows = [];
  const knownBlock = requireMatch(r.manifest, /private static let knownKeys: Set<String> = \[([\s\S]*?)\]/, 'knownKeys')[1];
  const knownKeys = [...knownBlock.matchAll(/"([^"]+)"/g)].map(m => m[1]);
  assertKeys(knownKeys, Object.keys(scriptNotes), 'script.json knownKeys');
  const decoder = between(r.manifest, '    public init(from decoder: Decoder) throws {', '    public func encode(to encoder: Encoder) throws {');
  const decoded = [...decoder.text.matchAll(/\b(decode|decodeIfPresent)\(\s*([\s\S]*?)\.self,\s*forKey:\s*key\("([^"]+)"\)\s*\)/g)];
  assertKeys(decoded.map(item => item[3]), knownKeys, 'script.json decoder keys');
  for (const item of decoded)
    rows.push(field(item[3], item[2].trim(), item[1] === 'decode', scriptNotes[item[3]],
      [ref(decoder, item[0], 'HanlinScriptingManifest.init(from:)')]));
  const authorNotes = {name: 'Required author name.', email: 'Metadata: optional contact email.', homepage: 'Optional homepage, used for canonical author website.'};
  addRecord(rows, r.manifest, 'HanlinScriptingAuthor', 'author.', authorNotes);
  addRecord(rows, r.manifest, 'HanlinScriptingAuthor', 'contributors[].', {
    name: 'Metadata: required contributor name when object is present.', email: 'Metadata: optional contributor email.',
    homepage: 'Metadata: optional contributor homepage; current registration reads the primary author, not contributors.',
  });
  addRecord(rows, r.manifest, 'HanlinScriptingRemoteResource', 'remoteResource.', {
    url: 'Metadata: required remote URL string.', autoUpdateInterval: 'Metadata: optional interval; decoding alone schedules no updates.',
    hash: 'Metadata: optional source hash, not publisher identity.'});
  const consumers = [r.manifest, r.analyzer, r.registration, r.presentation, r.widgetCompiler, r.platform];
  assertKeys(sorted(consumers.flatMap(record => reads(record, 'unknownFields')).filter(key => !knownKeys.includes(key))),
    Object.keys(extraNotes), 'script.json retained extension consumers');
  for (const [key, [type, note]] of Object.entries(extraNotes))
    rows.push(field(key, type, false, note, consumers.filter(record => reads(record, 'unknownFields').includes(key))
      .map(record => ref(record, 'unknownFields["' + key + '"]'))));
  const prepared = between(r.analyzer, '    private static func preparedEntrypoints(', '    private func discoverEntrypoints(');
  addDictionary(rows, prepared, 'fields', 'entrypoints[].', {
    id: ['string', true, 'Unique nonempty ID, excluding reserved app/widget.'],
    kind: ['appIntent | embeddedResult | share | translationUI | liveActivity', true, 'Only these modern explicit kinds are accepted; engine-specific source requirements still apply.'],
    sourcePath: ['string', true, 'Existing normalized package path; embeddedResult must use discovered foreground bundle.'],
    exportedSymbol: ['string', false, 'Optional exported symbol; non-string/absent values resolve to nil.'],
  });
  addRecord(rows, r.presentation, 'HanlinNativePresentationMetadata', 'nativePresentations.*.', {
    engine: 'Original expo/scriptwidget renderer; preparePresentation rejects legacy.',
    sourcePath: 'Normalized existing source path; compilation scoped to its source directory.',
    sourceFormat: 'jsx, tsx, javascript, or expo-layout; expo-layout is an original Expo expression.',
    actions: 'Native presentation actions; absent array decodes empty.',
    input: 'Optional native input metadata; nested fields required only when present.',
  }, {actions: []});
  addRecord(rows, r.presentation, 'HanlinNativePresentationInput', 'nativePresentations.*.input.', {
    title: 'Required input title.', placeholder: 'Optional placeholder.', submitTitle: 'Required submit button title.'});
  addRecord(rows, r.widgetCompiler, 'HanlinWidgetPackageMetadata', 'hanlinWidget.', {
    abiVersion: 'Must equal HanlinWidgetProgram.abiVersion; Swift initializer defaults are not JSONDecoder defaults.',
    sourceFormat: 'Declared jsx, tsx, javascript, or expo-layout.',
    actions: 'Required synthesized Codable field, although the Swift initializer defaults empty.',
    families: 'Supported family strings for the prepared native widget.',
  });
  for (const prefix of ['hanlinWidget.actions[].', 'nativePresentations.*.actions[].'])
    addRecord(rows, r.widgetProgram, 'HanlinWidgetActionDeclaration', prefix, {
      id: 'Declared action identity.', kind: 'expoCallback, function, setValue, or reload; program validation imposes engine-specific execution.',
      handler: 'Optional function/callback handler.', stateKey: 'Optional state mutation key.'});
  addDictionary(rows, r.registration, 'actionObj', 'actions[].', {
    id: ['HanlinActionID', true, 'Metadata: valid ID required to create descriptor; invalid items omitted.'],
    title: ['string', false, 'Metadata: title defaults to ID.'],
    capability: ['HanlinCapabilityID', false, 'Metadata: defaults/falls back to inter-app.share, without a new grant gate.'],
    handler: ['string', false, 'Metadata: preferred handler; installed source path matched directly or with source/ prefix.'],
    entrypoint: ['string', false, 'Metadata: handler alias.'],
  });
  addDictionary(rows, r.registration, 'skillObj', 'skills[].', {
    id: ['HanlinSkillID', true, 'Metadata: valid ID required; invalid items omitted.'],
    title: ['string', false, 'Metadata: defaults to ID.'], summary: ['string', false, 'Metadata: preferred summary, then description, then title.'],
    description: ['string', false, 'Metadata: summary alias.'],
    instructions: ['string | object', false, 'Metadata: inline text or instructions object; defaults to empty inline text.'],
    resource: ['string', false, 'Metadata: fallback when instructions has no usable value.'],
    keywords: ['string[]', false, 'Metadata: retains strings; defaults empty.'],
    triggerHints: ['string[]', false, 'Metadata: preferred trigger strings.'], examples: ['string[]', false, 'Metadata: triggerHints alias.'],
    preferredToolIDs: ['string[]', false, 'Metadata: preferred tool ID strings.'], preferredTools: ['string[]', false, 'Metadata: preferredToolIDs alias.'],
  });
  addDictionary(rows, r.registration, 'instObj', 'skills[].instructions.', {
    inline: ['string', false, 'Metadata: preferred inline text.'], resource: ['string', false, 'Metadata: resource when inline absent.'],
    path: ['string', false, 'Metadata: resource alias.'],
  });
  rows.push(field('* (unrecognized keys)', 'ordinary JSON', false,
    'Compatibility: losslessly retained by ManifestJSONValue; unrecognized keys do not register executors, enable runtimes or grant capabilities.',
    [ref(r.manifest, 'for candidate in container.allKeys where !Self.knownKeys.contains')]));
  const script = {family: 'script.json', engines: ['expo', 'nativescript', 'scriptwidget'], owner: 'Hanlin existing package reader/analyzer',
    source: r.manifest.path, decoderKnownKeys: knownKeys, fields: rows,
    unknownFields: 'Losslessly retained; recognized extension fields and actual consumers are listed explicitly.',
    boundary: 'Frozen Scripting compatibility is documented, not expanded. Metadata declarations are distinct from executable support and device acceptance.'};

  const ns = between(r.analyzer, '    private static func validatePreparedNativeScriptApplication(', '    private static func validatePreparedExpoApplication(');
  const expo = between(r.analyzer, '    private static func validatePreparedExpoApplication(', '    private static func validatePreparedDependencyTypes(');
  const packageRows = (engine, scope, session) => {
    const result = [], contract = engine === 'expo' ? 'hanlinExpo' : 'hanlinNativeScript';
    assertKeys(reads(scope, 'packageJSON'), ['main', 'hanlinRuntime', contract, 'dependencies', 'devDependencies'], engine + ' package.json reader');
    const notes = {
      main: engine === 'expo' ? 'Defaults to bundle.js only when omitted; normalized relative existing file must equal analyzed foreground entry.'
        : 'Must be bundle.mjs, matching sole foreground entry; direct session checks same canonical file.',
      hanlinRuntime: 'Must equal hanlin-' + engine + '.',
      [contract]: 'Optional contract object; when present runtimeVersion/plugins required. Expo widgets require the object.',
      dependencies: 'Module-name/string-version object; selected engine dependency checked below.',
      devDependencies: 'Same type rules; selected engine dependency used only when dependencies does not supply it.',
    };
    for (const key of reads(scope, 'packageJSON'))
      result.push(field(key, key === 'main' || key === 'hanlinRuntime' ? 'string' : 'object',
        key === 'hanlinRuntime' || (engine === 'nativescript' && key === 'main'), notes[key], [ref(scope, 'packageJSON["' + key + '"]')]));
    assertKeys(reads(scope, 'contract'), engine === 'expo' ? ['runtimeVersion', 'plugins', 'bridgeVersion'] : ['runtimeVersion', 'plugins'], engine + ' prepared contract');
    const versionNote = engine === 'expo'
      ? 'Importer uses supportsMinimum against installed Expo UI; direct foreground session checks its Expo runtime contract. Native Expo widgets also require exact UI runtime/plugin pins. These are separate stage authorities.'
      : 'Stable same-major/minor iOS runtime, no newer patch; independent from Core package version.';
    result.push(field(contract + '.runtimeVersion', 'string', true, versionNote,
      [ref(scope, 'contract["runtimeVersion"]'), ref(session, 'contract["runtimeVersion"]'), ref(r.versionPolicy, 'public enum HanlinPreparedRuntimeVersion')]));
    result.push(field(contract + '.plugins', 'record<string, string>', true,
      'Native plugins must be embedded; unknown names rejected. Current individual rules below.', [ref(scope, 'contract["plugins"]')]));
    const plugins = engine === 'expo'
      ? {'@expo/ui': 'Minimum policy against installed Expo UI; exact pin for native widgets.',
        'expo-widgets': 'Minimum compatible requirement against installed original Expo Widgets.',
        '@hanlin/expo-ui': 'Released bridge version at most installed bridge baseline; not npm wrapper version.',
        '@nativescript/react-native': 'Exact installed native API version.',
        'react-native-worklets': 'Exact installed Worklets version.'}
      : {'@nativescript/swift-ui': 'Exact installed SwiftUI plugin; direct session also verifies native provider registration.'};
    assertKeys([...scope.text.matchAll(/(?:name\s*(?:==|!=)\s*|case\s+)"([^"]+)"/g)].map(item => item[1]), Object.keys(plugins), engine + ' embedded plugins');
    for (const [name, note] of Object.entries(plugins))
      result.push(field(contract + '.plugins.' + name, 'string', false, note, [ref(scope, '"' + name + '"')]));
    if (engine === 'expo') {
      result.push(field('hanlinExpo.bridgeVersion', 'string', false,
        'Released version at most embedded bridge; importer and direct session reject malformed values.',
        [ref(scope, 'contract["bridgeVersion"]'), ref(session, 'contract["bridgeVersion"]')]));
      result.push(field('name', 'string', false, 'Metadata: direct session fallback only when caller packageID is unknown.', [ref(session, 'packageJSON["name"]')]));
      for (const key of ['nativeApi', 'nativeApi.contractVersion', 'nativeApi.abiIdentity'])
        result.push(field('hanlinExpo.' + key, key === 'nativeApi' ? 'object' : 'string', false,
          'Metadata: builder emits installed SDK host contract provenance; inspected importer/direct-session readers do not independently enforce this field.',
          [ref(r.authoring, 'nativeApi: {...input.pkg.hanlinExpo?.nativeApi')]));
    } else result.push(field('type', 'string', false, 'Metadata: authoring builder emits module for original NativeScript ESM package.',
      [ref(r.authoring, "main: 'bundle.mjs', type: 'module'")]));
    const dependency = engine === 'expo' ? '@expo/ui' : '@nativescript/core';
    for (const parent of ['dependencies', 'devDependencies']) {
      result.push(field(parent + '.*', 'string', false, 'All supplied dependency values must be strings; other npm semantics belong to original tooling.',
        [ref(r.analyzer, 'for key in ["dependencies", "devDependencies"]')]));
      result.push(field(parent + '.' + dependency, 'string', false,
        engine === 'expo' ? 'Released minimum compatible with installed Expo UI; dependencies wins.'
          : 'Released minimum compatible with installed Core, not iOS runtime; dependencies wins.',
        [ref(scope, '["' + dependency + '"]')]));
    }
    result.push(field('* (other npm metadata)', 'JSON', false, 'Metadata: copied by builder and/or consumed by original npm/runtime tooling, not a Hanlin native-plugin grant.',
      [ref(r.authoring, engine === 'expo' ? "await writeJSON(path.join(stage, 'package.json')" : "await writeJSON(path.join(app, 'package.json')")]));
    return {family: engine + ' prepared package.json', engines: [engine], owner: 'Hanlin importer + original runtime host integration',
      source: scope.path, fields: result, additionalAuthorities: [ref(session, 'package.json'), ref(r.versions, 'public enum HanlinMiniAppHostVersions')],
      boundary: 'Importer, native-session and build-time metadata remain distinct. Package fields cannot add native libraries to an already built host.'};
  };
  const packages = [packageRows('nativescript', ns, r.nsSession), packageRows('expo', expo, r.expoSession)];

  const authorRows = [];
  const authorProperties = sorted([...r.authoring.text.matchAll(/\bauthor\??\.([A-Za-z_$]\w*)/g)].map(m => m[1]));
  const authorGroupNotes = {
    schemaVersion: ['integer', false, 'When supplied must equal 1; successful builder emits 1.'],
    engine: ['expo | nativescript | scriptwidget', false, 'Must agree with requested/inferred engine; required if inference unavailable.'],
    entry: ['string', false, 'Source entry, not prepared bundle; required except ScriptWidget may use script.json.entry. Must exist within sourceRoot.'],
    tsconfig: ['string', false, 'Source-relative original compiler configuration, default tsconfig.json; installed TypeScript interprets options.'],
    resources: ['string[]', false, 'Explicit retained source-relative files/directories; ownership and cyclic-directory checks apply.'],
    sourceRoot: ['string', false, 'Packaged source root confined to imported project; inner descriptor overrides source-project settings.'],
  };
  assertKeys(authorProperties, Object.keys(authorGroupNotes), 'hanlin.authoring.json source fields');
  for (const [key, [type, required, note]] of Object.entries(authorGroupNotes)) {
    const match = requireMatch(r.authoring, new RegExp('\\bauthor\\??\\.' + key + '\\b'), 'author.' + key);
    authorRows.push(field(key, type, required, note, [ref(r.authoring, match[0])]));
  }
  const consistency = between(r.authoring, 'async function packageConsistency(', 'async function parseProject(');
  const identities = [...consistency.text.matchAll(/\['(\w+)', input\./g)].map(m => m[1]);
  assertKeys(identities, ['sourceHashes', 'compiledHashes'], 'packaged authoring identity fields');
  for (const key of identities) authorRows.push(field(key, 'record<string, SHA-256 string>', 'required for packaged sourceRoot',
    'Recorded integrity inventory; entries are checked against actual source/compiled files.', [ref(consistency, "['" + key + "'")]));
  for (const key of identities) authorRows.push(field(key + '.*', 'SHA-256 string', 'required for packaged sourceRoot',
    'Recorded paths are read/hashed; missing inventories or mismatched bytes produce diagnostics. Integrity consistency, not publisher identity.',
    [ref(consistency, "['" + key + "'")]));
  for (const [key, type] of Object.entries({sdk: 'object', 'sdk.packageVersions.*': 'string', 'sdk.manifestSHA256': 'SHA-256 string', 'sdk.compilerVersion': 'string'}))
    authorRows.push(field(key, type, false,
      'Metadata: build provenance; import revalidates with current original SDK. A recorded SDK fingerprint alone is not a compatibility rejection.',
      [ref(r.authoring, 'sdk: report.sdk'), ref(r.authoring, 'report.sdk = {packageVersions:')]));
  const authoring = {family: 'hanlin.authoring.json', engines: ['expo', 'nativescript', 'scriptwidget'], owner: 'Shared original-SDK authoring service',
    source: r.authoring.path, fields: authorRows, boundary: 'Source TypeScript validation requires the descriptor; a supplied build report does not replace current compiler validation.'};

  const dependencyScope = between(r.authoring, 'async function copyNativeScriptDependencies(', 'async function buildNativeScript(');
  const dependencyPackage = between(dependencyScope, "    const pkg = await json(path.join(source, 'package.json'));", '  // Reserve/copy direct modules first');
  const dependencyProperties = sorted([...dependencyPackage.text.matchAll(/\bpkg\??\.([A-Za-z_$]\w*)/g)].map(item => item[1]));
  assertKeys(dependencyProperties, ['version', 'nativescript', 'dependencies', 'peerDependencies', 'optionalDependencies', 'peerDependenciesMeta'],
    'NativeScript installed dependency package.json reads');
  const dependencyRows = [];
  const dependencyNotes = {
    version: ['npm package version', 'Recorded installed version becomes direct dependency/native plugin version. This function does not solve npm ranges.'],
    nativescript: ['object', 'Original NativeScript package metadata; the nested iOS declaration below drives plugin discovery.'],
    dependencies: ['record<string, npm specifier>', 'Dependency names looked up in actual installed module graph, then copied recursively.'],
    peerDependencies: ['record<string, npm specifier>', 'Merged into required graph; peer value wins when same name also occurs in dependencies.'],
    optionalDependencies: ['record<string, npm specifier>', 'Optional graph names; missing installed optional modules are skipped.'],
    peerDependenciesMeta: ['record<string, object>', 'Per-peer metadata; truthy optional moves a required peer into the optional graph.'],
  };
  for (const [key, [type, note]] of Object.entries(dependencyNotes))
    dependencyRows.push(field(key, type, false, note, [ref(dependencyPackage, 'pkg.' + key)]));
  dependencyRows.push(field('nativescript.platforms', 'object', false, 'Intermediate original platform metadata, not a new Host platform entitlement.',
    [ref(dependencyPackage, 'pkg.nativescript?.platforms?.ios')]));
  dependencyRows.push(field('nativescript.platforms.ios', 'JSON value tested for truthiness', false,
    'Truthy value marks this installed package as a native iOS plugin and emits its recorded pkg.version into the prepared plugin contract; no npm install or version solving happens here.',
    [ref(dependencyPackage, 'pkg.nativescript?.platforms?.ios')]));
  for (const key of ['dependencies', 'peerDependencies', 'optionalDependencies'])
    dependencyRows.push(field(key + '.*', 'npm specifier', false,
      'Graph traversal uses module names and already installed source paths; it does not install packages or resolve version ranges.',
      [ref(dependencyPackage, 'pkg.' + key)]));
  dependencyRows.push(field('peerDependenciesMeta.*.optional', 'JSON value tested for truthiness', false,
    'Truthy info.optional moves the peer from required to optional; missing optional resolution is skipped.',
    [ref(dependencyPackage, 'if (info.optional)')]));
  const dependencyMetadata = {family: 'NativeScript installed dependency package.json', engines: ['nativescript'],
    owner: 'Shared authoring service consuming original installed npm packages', source: r.authoring.path, fields: dependencyRows,
    boundary: 'Dependency-package metadata, distinct from the application prepared package.json. Existing installed modules are copied; this is not an npm installer/version solver or proof that a newly discovered native plugin is embedded. The prepared importer still checks plugin availability.'};

  const widgetSchema = JSON.parse(r.widgetSchema.text);
  const originalSources = widgetSchema['x-original-contract']?.sources;
  const expectedOriginalSources = [r.widgetMetadata, r.widgetPackage, r.widgetNetworkPolicy];
  if (!Array.isArray(originalSources) || originalSources.length !== expectedOriginalSources.length)
    throw new Error('Original widget provenance is missing or has unexpected sources.');
  assertKeys(originalSources.map(original => original?.path), expectedOriginalSources.map(record => record.path),
    'original widget provenance sources');
  for (const original of originalSources) {
    const record = expectedOriginalSources.find(record => record.path === original.path);
    if (!record || record.sha256 !== original.sha256) throw new Error('Original widget manifest source/schema drift: ' + original.path);
  }
  for (const name of ['WidgetPackageAuthor', 'WidgetPackageAction', 'WidgetPackageControl', 'WidgetPackagePushUpdates', 'WidgetPackageTimeline', 'WidgetPackageManifest'])
    assertKeys(storedMembers(r.widgetMetadata, name).map(item => item.name),
      Object.keys(widgetSchema.$defs[name]?.properties ?? {}), 'original ' + name);
  const schemaRows = (schema, record, owner) => {
    const result = [], objectRules = [];
    const pointerKey = name => name.replaceAll('~', '~0').replaceAll('/', '~1');
    function walk(value, pointer = '#') {
      if (!value || typeof value !== 'object' || Array.isArray(value)) return;
      if (value.$ref) {
        if (!value.$ref.startsWith('#/')) throw new Error('Unmapped external manifest schema reference: ' + value.$ref);
        let target = schema;
        for (const key of value.$ref.slice(2).split('/')) target = target?.[key.replaceAll('~1', '/').replaceAll('~0', '~')];
        if (!target) throw new Error('Unresolved manifest schema reference: ' + value.$ref);
      }
      if (value.properties || value.required || value.additionalProperties !== undefined)
        objectRules.push({jsonPointer: pointer, ...(value.required ? {required: value.required} : {}),
          ...(value.additionalProperties !== undefined ? {additionalProperties: value.additionalProperties} : {})});
      for (const [name, property] of Object.entries(value.properties ?? {})) {
        const at = pointer + '/properties/' + pointerKey(name);
        const type = property.type ?? property.$ref ?? (property.anyOf ? 'anyOf' : property.oneOf ? 'oneOf' : 'schema');
        result.push(field(at, type, (value.required ?? []).includes(name),
          'Declared by ' + owner + '; exact enum, alternatives, nullability and constraints retained in schema.',
          [{path: record.path, sha256: record.sha256, jsonPointer: at}], {schema: property}));
        walk(property, at);
      }
      for (const key of ['$defs', 'definitions', 'patternProperties', 'dependentSchemas'])
        for (const [name, definition] of Object.entries(value[key] ?? {})) walk(definition, pointer + '/' + key + '/' + pointerKey(name));
      for (const key of ['items', 'additionalProperties', 'contains', 'propertyNames', 'not', 'if', 'then', 'else'])
        if (value[key] && typeof value[key] === 'object' && !Array.isArray(value[key])) walk(value[key], pointer + '/' + key);
      for (const key of ['allOf', 'anyOf', 'oneOf', 'prefixItems'])
        (value[key] ?? []).forEach((item, i) => walk(item, pointer + '/' + key + '/' + i));
    }
    walk(schema);
    return {fields: result, objectRules};
  };
  const widget = {family: 'original ScriptWidget widget.json', engines: ['scriptwidget'], owner: 'Original ScriptWidget Package 2.0',
    source: r.widgetSchema.path, upstream: widgetSchema['x-original-contract'],
    ...schemaRows(widgetSchema, r.widgetSchema, 'the original-derived ScriptWidget schema'),
    additionalAuthorities: [ref(r.widgetMetadata, 'struct WidgetPackageManifest:'), ref(r.widgetMetadata, 'enum WidgetPackageManifestValidator'),
      ref(r.widgetPackage, 'func readManifest()'), ref(r.widgetNetworkPolicy, 'static func isValidDomainDeclaration('),
      ref(r.widgetControls, 'read('), ref(r.widgetValidator, 'validateScriptWidgetManifest')],
    boundary: 'Root widget.json is retained for main ScriptWidget compilation; entry must match widget source. Original control actions are derived; separate nativePresentations do not derive root controls. Original permission declarations add no Hanlin approval flow. Upstream schema constraints are not new host limits.'};
  const canonical = JSON.parse(r.canonicalSchema.text);
  const compiled = {family: 'canonical compiled Hanlin app', engines: ['canonical descriptor; separate format'], owner: 'HanlinPlatformContracts schema',
    source: r.canonicalSchema.path, rootProperties: Object.keys(canonical.properties ?? {}).sort(),
    ...schemaRows(canonical, r.canonicalSchema, 'the existing canonical schema'),
    boundary: 'Separate format: do not substitute these schema fields/enums for script.json or prepared package.json. Schema enumeration does not promise runtime/surface availability or parity with every Swift Codable descriptor.'};
  const legacyMetadataRows = [];
  addRecord(legacyMetadataRows, r.widgetMetadata, 'ScriptMetadata', '', {
    description: 'Metadata: legacy template description.', category: 'Metadata: legacy template category.',
    tags: 'Metadata: legacy template tags.', difficulty: 'Metadata: legacy template difficulty.',
    icon: 'Metadata: legacy template icon.', preview: 'Metadata: legacy template preview.',
    featured: 'Metadata: legacy template featured flag.',
  });
  const legacyMetadata = {family: 'original ScriptWidget meta.json compatibility', engines: ['scriptwidget'], owner: 'Original ScriptWidget compatibility metadata',
    source: r.widgetMetadata.path, fields: legacyMetadataRows,
    boundary: 'Existing optional template metadata, distinct from authoritative Package 2.0 widget.json. This enumeration adds no legacy runtime feature.'};
  const families = [script, ...packages, authoring, dependencyMetadata, widget, legacyMetadata, compiled];
  for (const family of families) {
    const names = family.fields.map(item => item.field);
    if (new Set(names).size !== names.length) throw new Error('Duplicate manifest mapping: ' + family.family);
    if (!family.fields.every(item => item.sources.length && item.sources.every(authority => authority.sha256)))
      throw new Error('Unbound manifest field: ' + family.family);
    family.fields.sort((a, b) => a.field < b.field ? -1 : a.field > b.field ? 1 : 0);
    family.coverage = {status: 'COMPLETE_SOURCE_FIELD_ENUMERATION', fieldCount: family.fields.length,
      scope: family.family === compiled.family ? 'Every property in the separate canonical schema, including nested/conditional definitions.'
        : 'Current recognized reader/producer fields in listed sources; wildcard maps retain original ownership.'};
  }
  return {schemaVersion: 1, status: 'COMPLETE_SOURCE_FIELD_ENUMERATION', nativeAcceptance: 'NOT_INFERRED',
    fieldCount: families.reduce((total, family) => total + family.fields.length, 0),
    sourceContract: 'Decoder keys, extension consumers, nested records, prepared package/authoring reads and schema properties are mapped. Added/removed recognized keys fail until mapped. Loaded source hashes participate in the existing inventory drift check.',
    families};
}

export function manifestReferenceMarkdown(coverage) {
  const tick = String.fromCharCode(96);
  const code = value => tick + String(value).replaceAll(tick, "'") + tick;
  const cell = value => String(value).replaceAll('|', '\\|').replaceAll('\n', ' ');
  const lines = ['# MiniApp manifest field reference', '',
    'Generated by Scripts/Audit/audit-miniapp-sdk.mjs from existing readers/schemas. Do not edit by hand.', '',
    'This source map is not native acceptance or an additional validator. Machine-readable constraints, source hashes and scopes are in [source-inventory.json](source-inventory.json).', '',
    'Supported means the listed reader/schema recognizes a field. Partial marks retained metadata or frozen compatibility, without promising an executable surface. Original library contracts, unknown fields, operating-system behavior and recorded provenance remain distinct.', '',
    'Use the existing audit --write after reviewing source changes, then --check to reject stale JSON or this reference. The installed SDK remains the version authority; build receipts do not replace current validation.', '',
    'Implementation source links below are repository-relative provenance, not paths to shipped SDK resources. Package authors use the installed miniapp-sdk.json declaration, toolingRoot and resource locators for authoring.', ''];
  for (const family of coverage.families) {
    lines.push('## ' + family.family, '', family.boundary, '', '**Owner:** ' + family.owner + '. **Engines:** ' + family.engines.join(', ') + '.', '',
      '| Field | Type / required | Source behavior | Status / authority |', '|---|---|---|---|');
    for (const item of family.fields) {
      const refs = item.sources.map(authority => {
        const suffix = authority.jsonPointer ?? (authority.line ? ':' + authority.line : '');
        return '[' + authority.path.split('/').at(-1) + cell(suffix) + '](../../' + authority.path + ')';
      }).join(', ');
      lines.push('| ' + code(cell(item.field)) + ' | ' + code(cell(item.type)) + '; ' +
        cell(item.required === true ? 'required when parent present' : item.required === false ? 'optional' : item.required) +
        ' | ' + cell(item.semantics) + ' | ' + item.status + '; ' + refs + ' |');
    }
    lines.push('');
  }
  lines.push('## Proof boundary', '',
    'Enumeration is complete within each stated source/schema scope. Executable routes, original library availability, signed binaries, UI callbacks, physical-device permissions and acceptance receipts remain separate. Legacy Scripting stays frozen; no custom home entry or full Apple SDK expansion is introduced.', '');
  return lines.join('\n');
}
