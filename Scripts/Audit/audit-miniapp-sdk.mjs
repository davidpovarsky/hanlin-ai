// Source inventory for the existing Hanlin SDKs; this does not generate a new SDK.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';

const compilerArgument = process.argv.indexOf('--typescript-module');
const compilerFile = compilerArgument >= 0
  ? path.resolve(process.argv[compilerArgument + 1] ?? '')
  : createRequire(new URL('../Expo/package.json', import.meta.url)).resolve('typescript');
const compilerPackage = JSON.parse(await readFile(path.resolve(path.dirname(compilerFile), '../package.json'), 'utf8'));
if (compilerPackage.name !== '@typescript/typescript6' || compilerPackage.version !== '6.0.2') {
  throw new Error('Audit with the existing Expo tooling @typescript/typescript6 package pinned to 6.0.2.');
}
const ts = (await import(pathToFileURL(compilerFile).href)).default;

const root = path.resolve(import.meta.dirname, '../..');
const destination = path.join(root, 'docs/miniapp-sdk/source-inventory.json');
const files = new Map();
const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const relative = file => path.relative(root, file).replaceAll('\\', '/');
async function source(file) {
  file = path.resolve(root, file);
  if (!files.has(file)) {
    const bytes = await readFile(file);
    files.set(file, {path: relative(file), sha256: createHash('sha256').update(bytes).digest('hex'), text: bytes.toString('utf8')});
  }
  return files.get(file);
}
async function json(file) { return JSON.parse((await source(file)).text); }
const exports = [], reexports = [], visited = new Set();

function members(node, tree) {
  return [...(node.members ?? node.properties ?? [])].filter(n => n.name).map(n => ({
    name: n.name.getText(tree), kind: ts.SyntaxKind[n.kind], optional: !!n.questionToken,
    ...(n.type ? {type: n.type.getText(tree)} : {}),
  }));
}
async function inspectTS(file) {
  file = path.resolve(root, file);
  if (visited.has(file)) return;
  visited.add(file);
  const record = await source(file);
  const tree = ts.createSourceFile(file, record.text, ts.ScriptTarget.Latest, true,
    file.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  if (tree.parseDiagnostics.length) throw new Error(`SDK declaration parse failure: ${record.path}`);
  for (const node of tree.statements) {
    const line = tree.getLineAndCharacterOfPosition(node.getStart(tree)).line + 1;
    if (ts.isExportDeclaration(node) && node.moduleSpecifier) {
      const module = node.moduleSpecifier.text;
      const names = node.exportClause && ts.isNamedExports(node.exportClause)
        ? node.exportClause.elements.map(n => n.name.text) : ['*'];
      reexports.push({source: record.path, line, module, names, typeOnly: !!node.isTypeOnly});
      if (module.startsWith('.')) {
        const base = path.resolve(path.dirname(file), module);
        let found;
        for (const suffix of ['.ts', '.tsx', '/index.ts']) {
          try { await source(base + suffix); found = base + suffix; break; } catch (error) { if (error.code !== 'ENOENT') throw error; }
        }
        if (!found) throw new Error(`Unresolved local SDK export: ${record.path} -> ${module}`);
        await inspectTS(found);
      }
      continue;
    }
    if (!node.modifiers?.some(m => m.kind === ts.SyntaxKind.ExportKeyword)) continue;
    if (ts.isVariableStatement(node)) {
      for (const declaration of node.declarationList.declarations) {
        if (!ts.isIdentifier(declaration.name)) throw new Error(`Unreviewed public binding: ${record.path}:${line}`);
        let value = declaration.initializer;
        while (value && (ts.isAsExpression(value) || ts.isSatisfiesExpression(value))) value = value.expression;
        exports.push({source: record.path, line, name: declaration.name.text, kind: 'variable',
          ...(value && (ts.isStringLiteral(value) || ts.isNumericLiteral(value)) ? {literalValue: value.text} : {}),
          ...(value && ts.isObjectLiteralExpression(value) ? {members: members(value, tree)} : {})});
      }
    } else if (node.name) {
      exports.push({source: record.path, line, name: node.name.text, kind: ts.SyntaxKind[node.kind],
        ...(node.type ? {type: node.type.getText(tree)} : {}),
        ...(node.members ? {members: members(node, tree)} : {})});
    }
  }
}

await inspectTS('Packages/HanlinExpoUI/src/index.ts');
await inspectTS('Packages/HanlinExpoUI/src/modifiers.ts');
await inspectTS('Packages/HanlinExpoNativeAPIJS/src/index.ts');
const expoExports = [...exports];
await inspectTS('Scripts/NativeScript/host-services.ts');
const nativeScriptExports = exports.slice(expoExports.length);
const tooling = await json('Scripts/Expo/package.json');
const lock = await json('Scripts/Expo/package-lock.json');
const nsLock = await json('Scripts/NativeScript/dependency-lock.json');
const nsPackage = await json('Scripts/NativeScript/package.json');
const uiPackage = await json('Packages/HanlinExpoUI/package.json');
const nativeAPIPackage = await json('Packages/HanlinExpoNativeAPIJS/package.json');
const bridge = await json('Tools/SwiftUIBridge/configuration.json');
const reviewed = await json('Tools/SwiftUIBridge/expo-reviewed-capabilities.json');
const header = await source('Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/include/HanlinNativeServicesBridge.h');
const objcMethods = [...header.text.matchAll(/^[-+]\s*\([^\n]+?\)\s*(\w+)([\s\S]*?);/gm)].map(match => {
  const signature = match[0].replaceAll(/\s+/g, ' ');
  const selectors = [...signature.matchAll(/(\w+)\s*:/g)].map(m => m[1]);
  return {selector: selectors.length ? selectors.join(':') + ':' : match[1],
    classMethod: signature.startsWith('+'), signature, line: header.text.slice(0, match.index).split('\n').length};
});
const nativeModule = await source('Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinHostServicesModule.swift');
const adapter = await source('AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift');
const system = await source('AI_HLY/Downstream/HostServices/System/HanlinSystemServicesBroker.swift');
const manifest = await source('Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinPackageContracts.swift');
const keyBlock = manifest.text.match(/private static let knownKeys: Set<String> = \[([\s\S]*?)\]/)?.[1];
if (!keyBlock) throw new Error('The script.json decoder contract changed; audit its actual keys.');
const knownKeys = [...keyBlock.matchAll(/"([^"]+)"/g)].map(m => m[1]);
const canonicalSchema = await json('Packages/HanlinPlatform/Sources/HanlinPlatformContracts/Resources/HanlinAppManifest.schema.json');
for (const file of [
  'Scripts/Audit/audit-miniapp-sdk.mjs', 'Packages/HanlinNativeScriptRuntime/Package.swift', 'Packages/HanlinExpoRuntime/Package.swift',
  'Packages/HanlinExpoNativeAPI/Package.swift', 'AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift',
  'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/HanlinNativeServicesBridge.m',
  'AI_HLY/Downstream/NativeScript/HanlinNativeServicesBridge.swift',
  'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/HanlinNativeScriptCoreSupport.mm',
  'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift',
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoHostServicesBridge.swift',
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoSession.swift',
  'AI_HLY/Downstream/HostServices/Runtime/HanlinRuntimeBroker.swift', 'AI_HLY/Downstream/HostServices/Core/HanlinHostCallContext.swift',
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/Generated/HanlinGeneratedViews.swift',
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/Generated/HanlinGeneratedModifiers.swift',
  'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift',
  'Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinInstallContracts.swift',
  'Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinVersions.swift',
  'Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinPreparedRuntimeVersion.swift',
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoBridgeMetadata.swift',
  'AI_HLY/Downstream/HostServices/Runtime/HanlinRuntimeWireProtocol.swift',
  'Scripts/NativeScript/build-host-services.mjs',
  'Scripts/NativeScript/Fixtures/HostServices/valid.ts',
  'Scripts/NativeScript/Fixtures/HostServices/invalid.ts',
  'Scripts/NativeScript/prepare-ios-dependencies.mjs',
  'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/index.mjs',
  'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/index.d.ts',
  'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/package.json',
]) await source(file);

const analyzer = await source('Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift');
const preparedVersions = Object.fromEntries([...analyzer.text.matchAll(/private static let (nativeScriptRuntimeVersion|nativeScriptSwiftUIVersion|expoSDKVersion|expoUIVersion|expoUIBridgeVersion) = "([^"]+)"/g)].map(m => [m[1], m[2]]));
if (Object.keys(preparedVersions).length !== 5 || !analyzer.text.includes('HanlinPreparedRuntimeVersion.supportsMinimum')) {
  throw new Error('Prepared runtime version validation changed; audit the installed contract.');
}
const nativeSessionSource = await source('Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift');
const nativeSessionVersion = name => nativeSessionSource.text.match(new RegExp(`private static let ${name} = "([^"]+)"`))?.[1];
if (nativeSessionVersion('supportedRuntimeVersion') !== preparedVersions.nativeScriptRuntimeVersion ||
    nativeSessionVersion('supportedSwiftUIVersion') !== preparedVersions.nativeScriptSwiftUIVersion ||
    nsLock.nativeScript.coreVersion !== preparedVersions.nativeScriptRuntimeVersion ||
    nsLock.nativeScript.iosRuntimeVersion !== preparedVersions.nativeScriptRuntimeVersion ||
    nsLock.swiftUI.version !== preparedVersions.nativeScriptSwiftUIVersion ||
    bridge.runtimeVersion !== preparedVersions.expoSDKVersion ||
    bridge.expoUIVersion !== preparedVersions.expoUIVersion ||
    bridge.bridgeVersion !== preparedVersions.expoUIBridgeVersion) {
  throw new Error('Importer, direct session and pinned/generated runtime versions disagree.');
}

const wanted = ['expo', '@expo/ui', 'react', 'react-native', 'expo-modules-core', 'expo-modules-jsi', 'react-native-worklets', '@nativescript/react-native'];
const nativeNames = [...nativeModule.text.matchAll(/AsyncFunction\("([^"]+)"\)/g)].map(m => m[1]);
const operations = [...adapter.text.slice(0, adapter.text.indexOf('// MARK: - HanlinExpoHostServicesProvider')).matchAll(/case "([^"]+)":/g)].map(m => m[1]);
const facade = (await source('Packages/HanlinExpoUI/src/host-services.ts')).text;
const facadeOperations = [...facade.matchAll(/invoke(?:<[^\n]+?>)?\('([^']+)'/g)].map(m => m[1]);
if (!nativeNames.includes('invoke') || facadeOperations.some(op => !operations.includes(op))) {
  throw new Error('Existing Expo facade/native operation drift; do not publish an inferred API.');
}
const inventory = {
  schemaVersion: 1,
  auditParser: {package: compilerPackage.name, version: compilerPackage.version, reportedCompilerVersion: ts.version,
    sha256: createHash('sha256').update(await readFile(compilerFile)).digest('hex'),
    purpose: 'syntax/export inventory; not strict typecheck or native availability proof'},
  scope: 'Existing NativeScript + Expo SDK source only; no Scripting-JSC development',
  status: 'IN_PROGRESS_SOURCE_AUDIT',
  evidenceBoundary: 'Exposed declarations and version locks are not a signed binary or per-surface E2E pass. Objective-C records are declarations, not metadata/JS marshalling proof.',
  snapshotIdentity: 'sourceCommit is the base commit; exact source hashes also cover any listed uncommitted source paths at audit time.',
  extensionReachability: 'extension-reachability.json (INT-01; separate consumer of this source inventory)',
  preparedRuntimeContract: {source: analyzer.path, versions: preparedVersions,
    minimumVersionSource: 'Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinPreparedRuntimeVersion.swift',
    policy: 'Released three-component semantic versions; historical ^/~ /=/v prefix expresses minimum metadata, not npm resolution. Core/Expo require the installed major and no newer version. Widget runtime/plugin exact pins remain authoritative.',
    stableDiagnosticCodes: [...new Set([...analyzer.text.matchAll(/code: "(MINIAPP_[A-Z_]+)"/g)].map(m => m[1]))].sort(),
    status: 'shared importer/direct-session minimum policy; numeric build precedence ignores build labels. Source pin consistency checked; full schemas and installed Host acceptance remain separate gates'},
  nativeScript: {toolingDependencies: nsPackage.dependencies ?? {}, toolingDevDependencies: nsPackage.devDependencies ?? {}, pinnedNativeContract: nsLock.nativeScript, swiftUI: nsLock.swiftUI,
    publicExports: nativeScriptExports,
    hostBridge: {source: header.path, methods: objcMethods, status: 'generic_source_wired_native_acceptance_pending', missingGenericRuntimeKinds: [], result: 'generic async callback returns canonical RuntimeExecutionResult JSON; legacy string callbacks remain compatible',
      cancellation: 'host-issued handle scoped to captured session; cooperative cancellation and invalidation; no second NS isolate'}},
  expo: {
    declaredAndLocked: Object.fromEntries(wanted.map(name => [name, {declared: tooling.dependencies[name], locked: lock.packages?.['node_modules/' + name]?.version ?? null}])),
    hanlinUI: {packageVersion: uiPackage.version, peerDependencies: uiPackage.peerDependencies, generatedBridgeVersion: bridge.bridgeVersion,
      generatedRuntimeContract: bridge.runtimeVersion, expoUIVersion: bridge.expoUIVersion,
      upstreamViewCount: bridge.expoViews.length, upstreamModifierCount: bridge.expoModifiers.length,
      reviewedViews: reviewed.views, reviewedModifiers: reviewed.modifiers},
    nativeAPIFacade: {packageVersion: nativeAPIPackage.version, peerDependencies: nativeAPIPackage.peerDependencies},
    nativeModule: {source: nativeModule.path, exports: nativeNames},
    hostInvoke: {source: adapter.path, operations, facadeOperations, status: 'partial_source_wiring_not_surface_acceptance'},
    publicExports: expoExports.sort((a, b) => compare(a.source, b.source) || a.line - b.line || compare(a.name, b.name)),
    reexports: reexports.sort((a, b) => compare(a.source, b.source) || a.line - b.line),
  },
  manifests: [
    {family: 'script.json', source: manifest.path, decoderKnownKeys: knownKeys, unknownFields: 'losslessly retained; not executable entrypoints or grants', status: 'partial; engine/package.json/analyzer rules are additional contracts'},
    {family: 'canonical compiled Hanlin app', source: 'Packages/HanlinPlatform/Sources/HanlinPlatformContracts/Resources/HanlinAppManifest.schema.json',
      rootProperties: Object.keys(canonicalSchema.properties ?? {}).sort(), note: 'Do not substitute this schema for the NS/Expo script.json and prepared package.json contract.'},
  ],
  systemServices: {source: system.path, declaredMethods: [...system.text.matchAll(/public func (\w+)\(/g)].map(m => m[1]),
    status: 'declarations do not prove NS/Expo public bindings, iOS availability, OS permission or canPresentUI'},
  gaps: [
    {id: 'SDK04-API-ACCEPTANCE', owner: 'SDK-04', detail: 'HanlinExpoUI peers now match the existing stable tooling pins, with no resolved dependency changes. File empty/missing distinction and runtime deadline/artifact typings are source-corrected; actual JS->module->native per-API and Metro/device coverage remain required.'},
    {id: 'INT06-LEGACY-ACCEPTANCE', owner: 'INT-06', detail: 'Native legacy backend/name/failure cases passed at1e4ba8c0/run43315911311. The generic structured boundary is now shared with NS; complete actual JS-to-module/per-surface receipt coverage remains open.'},
    {id: 'INT06-SHELL-SOURCE', owner: 'INT-06', detail: 'Generic RuntimeKind.shell still uses the linked native string parser; the public command-string tool uses the portable-shell route. Align the documented source semantics without adding another shell engine.'},
    {id: 'INT03-NS-RESULT', owner: 'INT-03', detail: 'Generic NS executeRuntime now uses the same JSON request/full receipt boundary as Expo, with typed generated facade and session-owned cooperative cancellation. Actual VM/metadata/backend acceptance is pending; legacy callbacks retain string semantics.'},
    {id: 'INT03-SESSION', owner: 'INT-03', detail: 'NativeScript has one active session and process-environment mutation; no concurrent-isolate or process-isolation claim.'},
    {id: 'INT06-CONTEXT', owner: 'INT-02/INT-06', detail: 'Actual headless NS share-sheet rejection passed atcbb0d8e3/run43325255401; foreground default remains true. MiniApp context still uses userGesturePresent=false; full invocation context and all OS-prompt services require separate validation.'},
    {id: 'INT06-AVAILABILITY', owner: 'INT-06', detail: 'hasCapability returns personal-host policy, not OS/service availability. The17 SystemServicesBroker declarations have no generic NS/Expo Host binding in these inspected adapters.'},
    {id: 'SDK01-BINARY', owner: 'SDK-01', detail: 'Installed device Host/bridge versions and signed extension entitlements remain unverified here; source manifests are not IPA evidence.'},
  ],
  sources: [...files.values()].map(({path, sha256}) => ({path, sha256})).sort((a, b) => compare(a.path, b.path)),
};
if (process.argv.includes('--check')) {
  const prior = JSON.parse(await readFile(destination, 'utf8'));
  delete prior.sourceCommit;
  delete prior.uncommittedSourcePaths;
  if (JSON.stringify(prior) !== JSON.stringify(inventory)) throw new Error('SDK source inventory drift. Audit source changes, then regenerate with --write.');
  console.log(`PASS: SDK source inventory matches ${inventory.sources.length} sources and ${exports.length} local public exports.`);
} else if (process.argv.includes('--write')) {
  const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  const changed = execFileSync('git', ['status', '--porcelain', '--untracked-files=all'], {cwd: root, encoding: 'utf8'})
    .split('\n').filter(Boolean).map(line => line.slice(3).replaceAll('\\', '/'));
  const uncommittedSourcePaths = inventory.sources.map(s => s.path).filter(p => changed.includes(p));
  await mkdir(path.dirname(destination), {recursive: true});
  await writeFile(destination, JSON.stringify({sourceCommit, uncommittedSourcePaths, ...inventory}, null, 2) + '\n');
  console.log(`Wrote source inventory: ${inventory.sources.length} sources, ${exports.length} local public exports; E2E not inferred.`);
} else throw new Error('Use --check for read-only drift verification or --write after auditing changes.');
