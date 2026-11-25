// Resolve the actual Swift version bindings and compare each component with its
// own original lock. This reads source contracts; it does not execute a native host.
const swiftSources = {
  HanlinScriptAnalyzer: 'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift',
  HanlinMiniAppHostVersions: 'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinMiniAppHostVersions.swift',
  HanlinNativeScriptSession: 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift',
  HanlinNativeScriptHostVersions: 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptHostVersions.swift',
  HanlinExpoSession: 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoSession.swift',
  HanlinExpoHostVersions: 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoHostVersions.swift',
  HanlinExpoNativeAPIHostVersions: 'Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/HanlinExpoNativeAPIHostVersions.swift',
  HanlinExpoNativeAPIMetadata: 'Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/HanlinExpoNativeAPIManager.swift',
  HanlinExpoBridgeMetadata: 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoBridgeMetadata.swift',
  HanlinGeneratedBridgeMetadata: 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/Generated/HanlinGeneratedViews.swift',
  HanlinCanonicalGeneratedBridgeMetadata: 'Generated/SwiftUIBridge/HanlinGeneratedViews.swift',
};

function resolveSwiftVersion(records, namespace, name, ancestry = []) {
  const identity = `${namespace}.${name}`, record = records[namespace];
  if (!record || ancestry.includes(identity) || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
    throw new Error(`Unresolved or cyclic prepared version binding: ${identity}`);
  }
  const pattern = new RegExp(`^\\s*(?:(?:public|private|internal|fileprivate|package)\\s+)?static\\s+let\\s+${name}(?:\\s*:\\s*String)?\\s*=\\s*([^\\r\\n]+)`, 'gm');
  const matches = [...record.text.matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`Prepared version declaration changed: ${identity} in ${record.path}`);
  const expression = matches[0][1].trim();
  const literal = expression.match(/^"(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)"(?:\s*\/\/.*)?$/);
  if (literal) return literal[1];
  const reference = expression.match(/^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)(?:\s*\/\/.*)?$/);
  if (reference) return resolveSwiftVersion(records, reference[1], reference[2], [...ancestry, identity]);
  throw new Error(`Unreviewed prepared version expression: ${identity} = ${expression}`);
}

function requireAgreement(component, values) {
  if (Object.values(values).some(value => typeof value !== 'string' || !value.length) || new Set(Object.values(values)).size !== 1) {
    throw new Error(`Importer, direct session and pinned/generated runtime versions disagree for ${component}: ${JSON.stringify(values)}`);
  }
}

function workletsCompilerVersion(record) {
  const matches=[...record.text.matchAll(/"-DWORKLETS_VERSION=(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)"/g)];
  if(matches.length!==1||(record.text.match(/-DWORKLETS_VERSION\b/g)??[]).length!==1)
    throw new Error('Unreviewed Worklets compiler version in '+record.path);
  return matches[0][1];
}

// Shared by the current source audit and the active native preflight. The
// checked constants identify the original resolved graph, not a separate pin.
export async function auditNativeAPIVersionContract({source, json, version}) {
  if (!version) {
    const names = ['HanlinMiniAppHostVersions', 'HanlinExpoHostVersions',
      'HanlinExpoNativeAPIHostVersions', 'HanlinExpoNativeAPIMetadata'];
    const records = Object.fromEntries(await Promise.all(names.map(async name => [name, await source(swiftSources[name])])));
    version = (...args) => resolveSwiftVersion(records, ...args);
  }
  const nativeLock = await json('Scripts/ExpoNativeAPI/dependency-lock.json');
  const expoLock = await json('Scripts/Expo/dependency-lock.json');
  const tooling = await json('Scripts/Expo/package.json');
  const lock = await json('Scripts/Expo/package-lock.json');
  const facade = await json('Packages/HanlinExpoNativeAPIJS/package.json');
  const facadeSource = await source('Packages/HanlinExpoNativeAPIJS/src/index.ts');
  function exportedVersion(name) {
    const declarations = [...facadeSource.text.matchAll(new RegExp('^export const '+name+' = "(\\d+\\.\\d+\\.\\d+(?:[-+][\\w.-]+)?)";$', 'gm'))];
    if (declarations.length !== 1) throw new Error('Unreviewed Native API facade version: '+name+' in '+facadeSource.path);
    return declarations[0][1];
  }
  const result = {
    nativeApiVersion: exportedVersion('UPSTREAM_VERSION'),
    workletsVersion: exportedVersion('WORKLETS_VERSION'),
    reactNativeVersion: expoLock.expo.reactNativeVersion,
    reactVersion: expoLock.expo.reactVersion,
    expoSDKVersion: expoLock.expo.sdkVersion,
    hermesVersion: expoLock.expo.hermesVersion,
  };
  for (const [component, packageName, key, field, importerField, exported] of [
    ['Expo Native API', '@nativescript/react-native', 'nativeApi', 'nativeApiVersion', 'nativeApiVersion', result.nativeApiVersion],
    ['Expo Worklets', 'react-native-worklets', 'worklets', 'workletsVersion', 'reactNativeWorkletsVersion', result.workletsVersion],
  ]) {
    if (nativeLock[key]?.package !== packageName) throw new Error('Native API dependency identity changed: '+key);
    requireAgreement(component, {
      facade: exported, facadePeer: facade.peerDependencies?.[packageName],
      nativeLock: nativeLock[key]?.version, tooling: tooling.dependencies?.[packageName],
      packageLock: lock.packages?.['node_modules/' + packageName]?.version,
      importerGenerated: version('HanlinMiniAppHostVersions', importerField),
      expoHost: version('HanlinExpoHostVersions', field),
      nativeHost: version('HanlinExpoNativeAPIHostVersions', field),
      publicNativeMetadata: version('HanlinExpoNativeAPIMetadata', field),
    });
  }
  const workletsManifests=await Promise.all([
    'Packages/HanlinExpoNativeAPI/Package.swift','Package.swift'
  ].map(file=>source(file)));
  requireAgreement('Expo Worklets native compiler', {
    resolvedOriginal: result.workletsVersion,
    ...Object.fromEntries(workletsManifests.map(record=>[record.path,workletsCompilerVersion(record)])),
  });
  requireAgreement('Expo React Native', {
    nativeLock: nativeLock.runtimeClosure?.reactNativeVersion, expoLock: result.reactNativeVersion,
    tooling: tooling.dependencies?.['react-native'], packageLock: lock.packages?.['node_modules/react-native']?.version,
    facadePeer: facade.peerDependencies?.['react-native'],
    importerGenerated: version('HanlinMiniAppHostVersions', 'reactNativeVersion'),
    expoHost: version('HanlinExpoHostVersions', 'reactNativeVersion'),
    nativeHost: version('HanlinExpoNativeAPIHostVersions', 'reactNativeVersion'),
    publicNativeMetadata: version('HanlinExpoNativeAPIMetadata', 'reactNativeVersion'),
  });
  requireAgreement('Expo React', {
    nativeLock: nativeLock.runtimeClosure?.reactVersion, expoLock: result.reactVersion,
    tooling: tooling.dependencies?.react, packageLock: lock.packages?.['node_modules/react']?.version,
    facadePeer: facade.peerDependencies?.react,
  });
  requireAgreement('Native API Expo SDK', {
    nativeLock: nativeLock.runtimeClosure?.expoSdkVersion, expoLock: result.expoSDKVersion,
    tooling: tooling.dependencies?.expo, packageLock: lock.packages?.['node_modules/expo']?.version,
  });
  requireAgreement('Expo Hermes', {
    nativeLock: nativeLock.runtimeClosure?.hermesVersion, expoLock: result.hermesVersion,
    expoHost: version('HanlinExpoHostVersions', 'hermesVersion'),
  });
  return result;
}

export async function auditPreparedRuntimeContract({source, json, nsLock, nsPackage, tooling, lock, bridge}) {
  const records = Object.fromEntries(await Promise.all(Object.entries(swiftSources)
    .map(async ([name, file]) => [name, await source(file)])));
  await source('Scripts/MiniApps/resolve-upstreams.mjs');
  const expoLock = await json('Scripts/Expo/dependency-lock.json');
  const version = (...args) => resolveSwiftVersion(records, ...args);
  function requirePolicy(namespace, pattern, label) {
    if (!pattern.test(records[namespace].text)) throw new Error(`Prepared runtime version policy changed: ${label}; audit the installed contract.`);
  }
  const corePolicy = installed => new RegExp(`\\bfunc\\s+isCoreVersionCompatible\\([^)]*\\)\\s*->\\s*Bool\\s*\\{\\s*HanlinPreparedRuntimeVersion\\.supportsMinimum\\(\\s*versionString\\s*,\\s*installed:\\s*${installed}\\s*\\)\\s*\\}`);
  requirePolicy('HanlinScriptAnalyzer', corePolicy('nativeScriptCoreVersion'), 'importer Core minimum');
  requirePolicy('HanlinNativeScriptSession', corePolicy('supportedCoreVersion'), 'direct-session Core minimum');
  requirePolicy('HanlinScriptAnalyzer', /HanlinPreparedRuntimeVersion\.supportsCompatiblePatch\(\s*runtimeVersion\s*,\s*installed:\s*nativeScriptRuntimeVersion\s*\)/, 'importer iOS runtime patch');
  requirePolicy('HanlinNativeScriptSession', /HanlinPreparedRuntimeVersion\.supportsCompatiblePatch\(\s*requiredRuntime\s*,\s*installed:\s*supportedRuntimeVersion\s*\)/, 'direct-session iOS runtime patch');
  requirePolicy('HanlinExpoSession', /HanlinPreparedRuntimeVersion\.supportsMinimum\(\s*runtimeVersion\s*,\s*installed:\s*HanlinExpoBridgeMetadata\.runtimeVersion\s*\)/, 'direct-session Expo runtime minimum');
  const names = ['nativeScriptRuntimeVersion', 'nativeScriptCoreVersion', 'nativeScriptSwiftUIVersion', 'expoSDKVersion', 'expoUIVersion', 'expoUIBridgeVersion'];
  const versions = Object.fromEntries(names.map(name => [name, version('HanlinScriptAnalyzer', name)]));
  const nativeSession = {
    runtimeVersion: version('HanlinNativeScriptSession', 'supportedRuntimeVersion'),
    coreVersion: version('HanlinNativeScriptSession', 'supportedCoreVersion'),
    swiftUIVersion: version('HanlinNativeScriptSession', 'supportedSwiftUIVersion'),
  };
  const expoSession = {
    sdkVersion: version('HanlinExpoSession', 'supportedSDKVersion'),
    uiVersion: version('HanlinExpoSession', 'supportedUIVersion'),
    runtimeVersion: version('HanlinExpoBridgeMetadata', 'runtimeVersion'),
    bridgeVersion: version('HanlinExpoBridgeMetadata', 'bridgeVersion'),
  };
  requireAgreement('NativeScript iOS runtime', {
    importer: versions.nativeScriptRuntimeVersion, session: nativeSession.runtimeVersion,
    importerGenerated: version('HanlinMiniAppHostVersions', 'nativeScriptRuntimeVersion'),
    sessionGenerated: version('HanlinNativeScriptHostVersions', 'runtimeVersion'),
    nativeLock: nsLock.nativeScript.iosRuntimeVersion, tooling: nsPackage.devDependencies?.['@nativescript/ios'],
  });
  requireAgreement('NativeScript Core', {
    importer: versions.nativeScriptCoreVersion, session: nativeSession.coreVersion,
    importerGenerated: version('HanlinMiniAppHostVersions', 'nativeScriptCoreVersion'),
    sessionGenerated: version('HanlinNativeScriptHostVersions', 'coreVersion'),
    nativeLock: nsLock.nativeScript.coreVersion, tooling: nsPackage.dependencies?.['@nativescript/core'],
  });
  requireAgreement('NativeScript SwiftUI plugin', {
    importer: versions.nativeScriptSwiftUIVersion, session: nativeSession.swiftUIVersion,
    importerGenerated: version('HanlinMiniAppHostVersions', 'nativeScriptSwiftUIVersion'),
    sessionGenerated: version('HanlinNativeScriptHostVersions', 'swiftUIVersion'),
    nativeLock: nsLock.swiftUI.version, tooling: nsPackage.dependencies?.['@nativescript/swift-ui'],
  });
  requireAgreement('Expo SDK', {
    importer: versions.expoSDKVersion, session: expoSession.sdkVersion,
    importerGenerated: version('HanlinMiniAppHostVersions', 'expoSDKVersion'),
    sessionGenerated: version('HanlinExpoHostVersions', 'expoSDKVersion'),
    nativeLock: expoLock.expo.sdkVersion, tooling: tooling.dependencies?.expo,
    packageLock: lock.packages?.['node_modules/expo']?.version,
  });
  requireAgreement('Expo UI', {
    importer: versions.expoUIVersion, session: expoSession.uiVersion,
    importerGenerated: version('HanlinMiniAppHostVersions', 'expoUIVersion'),
    sessionGenerated: version('HanlinExpoHostVersions', 'expoUIVersion'),
    nativeLock: expoLock.expo.uiVersion, tooling: tooling.dependencies?.['@expo/ui'],
    packageLock: lock.packages?.['node_modules/@expo/ui']?.version,
  });
  requireAgreement('prepared Expo runtime', {
    importer: versions.expoUIVersion, session: expoSession.runtimeVersion,
    sessionGenerated: version('HanlinExpoHostVersions', 'runtimeVersion'), nativeLock: expoLock.expo.uiVersion,
  });
  requireAgreement('Hanlin Expo bridge', {
    importer: versions.expoUIBridgeVersion, session: expoSession.bridgeVersion,
    generated: version('HanlinGeneratedBridgeMetadata', 'bridgeVersion'), configuration: bridge.bridgeVersion,
  });
  const tsMetadataPaths = [
    'Generated/SwiftUIBridge/bridge-manifest.ts',
    'Packages/HanlinExpoUI/src/generated/bridge-manifest.ts',
  ];
  const tsMetadata = await Promise.all(tsMetadataPaths.map(file => source(file)));
  const publicRuntimeVersions = tsMetadata.map(record => {
    const declarations = [...record.text.matchAll(/^export const HANLIN_EXPO_RUNTIME_VERSION = '(\d+\.\d+\.\d+(?:[-+][\w.-]+)?)' as const;$/gm)];
    if (declarations.length !== 1) throw new Error('Unreviewed Expo public runtime metadata in '+record.path);
    return declarations[0][1];
  });
  requireAgreement('Expo public runtime metadata', {
    installedOriginalUI: expoLock.expo.uiVersion,
    nativeRuntime: expoSession.runtimeVersion,
    configuration: bridge.runtimeVersion,
    generatedSwift: version('HanlinGeneratedBridgeMetadata', 'runtimeVersion'),
    canonicalSwift: version('HanlinCanonicalGeneratedBridgeMetadata', 'runtimeVersion'),
    canonicalTypeScript: publicRuntimeVersions[0],
    installedTypeScript: publicRuntimeVersions[1],
  });
  if (tsMetadata[0].text !== tsMetadata[1].text ||
      records.HanlinCanonicalGeneratedBridgeMetadata.text !== records.HanlinGeneratedBridgeMetadata.text) {
    throw new Error('Expo bridge metadata mirrors differ from their canonical generated sources');
  }
  const expoBridgeRuntimeMetadata = {
    runtimeVersion: expoSession.runtimeVersion,
    configuration: 'Tools/SwiftUIBridge/configuration.json',
    typescriptSources: tsMetadataPaths,
    swiftSources: [swiftSources.HanlinCanonicalGeneratedBridgeMetadata, swiftSources.HanlinGeneratedBridgeMetadata],
    originalRuntimeSource: 'Scripts/Expo/dependency-lock.json',
  };
  // Coverage records identify the reviewed Apple API input. Updating an original
  // runtime does not itself prove newly introduced APIs or change the bridge ABI.
  const bridgeGenerationBaseline = {
    source: 'Tools/SwiftUIBridge/configuration.json',
    expoUIVersion: bridge.expoUIVersion,
    purpose: 'reviewed Apple API coverage input; not the installed runtime version',
  };
  const nativeAPI = await auditNativeAPIVersionContract({source, json, version});
  return {versions, nativeSession, expoSession, nativeAPI, expoBridgeRuntimeMetadata, bridgeGenerationBaseline, versionSources: swiftSources};
}
