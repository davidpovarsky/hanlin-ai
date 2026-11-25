// Literal operation names only: a delegated prefix does not grant every name.
function caseOperations(text) {
  return [...text.matchAll(/^\s*case\s+((?:"[^"\r\n]+"\s*,\s*)*"[^"\r\n]+")\s*:/gm)]
    .flatMap(match => [...match[1].matchAll(/"([^"\r\n]+)"/g)].map(value => value[1]));
}

export function auditExpoOperationRoutes({adapter, externalSession, platform, nativeNames, facadeOperations}) {
  const marker = adapter.text.indexOf('// MARK: - HanlinExpoHostServicesProvider');
  const start = externalSession.text.indexOf('    func perform(');
  const end = externalSession.text.indexOf('\n    func done(', start);
  if (marker < 0 || start < 0 || end <= start) throw new Error('Expo operation dispatch boundaries changed; audit the actual handlers.');
  const direct = caseOperations(adapter.text.slice(0, marker));
  const delegated = caseOperations(externalSession.text.slice(start, end)).filter(name => name.startsWith('miniapps.'));
  const delegates = /if\s+operation\.hasPrefix\("miniapps\."\),\s*let\s+externalMiniAppOperation\s*\{\s*return\s+try\s+await\s+externalMiniAppOperation\(operation,\s*payloadJSON\)/.test(adapter.text);
  const callbackInstalled = /platform\.externalMiniAppOperation\s*=\s*\{\s*\[weak self\]\s+operation,\s*payload\s+in\s*guard\s+let\s+self\s+else\s*\{\s*throw\s+CancellationError\(\)\s*\}\s*return\s+try\s+await\s+self\.perform\(operation,\s*payload:\s*payload\)/.test(externalSession.text);
  // Keep every appended constructor capability explicit: the assistant factory
  // belongs to this platform, and the prepared publisher retains its owning
  // platform/session/installed generation. Arbitrary initializer tails do not
  // establish the external-operation callback connection.
  const assistantFactory = String.raw`,\s*assistantServiceFactory:\s*assistantServiceFactory`;
  const preparedPublisher = String.raw`,\s*preparedWidgetPublisher:\s*\{\s*\[weak self\]\s+entrypointID,\s*variantID,\s*props\s+in\s*guard\s+let\s+self\s+else\s*\{\s*throw\s+HanlinWidgetActionError\.inactiveInstance\s*\}\s*return\s+try\s+await\s+self\.publishPreparedExpoWidget\(\s*installedPackageID:\s*package\.record\.installedPackageID,\s*appID:\s*package\.appID,\s*expectedGeneration:\s*package\.record\.activeGeneration,\s*sessionID:\s*sessionID,\s*entrypointID:\s*entrypointID,\s*variantID:\s*variantID,\s*props:\s*props\s*\)\s*\}`;
  const callbackPassed = new RegExp(String.raw`let\s+adapter\s*=\s*ExpoHostServicesAdapter\([\s\S]*?externalMiniAppOperation:\s*externalMiniAppOperation\s*` + assistantFactory + preparedPublisher + String.raw`\s*\)\s*expoHostServices\s*=\s*adapter\s*HanlinExpoHostServicesBridge\.register\(provider:\s*adapter,\s*forSessionID:\s*sessionID\)`).test(platform.text);
  if (!delegates || !callbackInstalled || !callbackPassed) throw new Error('Expo external-operation callback linkage changed; delegated source cases are not sufficient.');
  if (!/return\s+try\s+await\s+HanlinScriptingPlatform\.shared\.invokeLiveActivity\(operation:\s*operation,\s*payloadJSON:\s*payloadJSON,\s*context:\s*context\)/.test(adapter.text) || !platform.text.includes('func invokeLiveActivity(')) {
    throw new Error('Expo Live Activity dispatch linkage changed; audit the native handler.');
  }
  const operations = [...new Set([...direct, ...delegated])];
  const missing = [...new Set(facadeOperations.filter(operation => !operations.includes(operation)))];
  if (!nativeNames.includes('invoke') || missing.length) {
    throw new Error(`Existing Expo facade/native operation drift; missing invoke or explicit handlers: ${JSON.stringify(missing)}`);
  }
  return {operations, routes: [
    {kind: 'direct', source: adapter.path, operations: direct},
    {kind: 'delegated', source: externalSession.path, suppliedBy: platform.path,
      operations: delegated, condition: 'An active external MiniApp invocation supplies the typed callback.'},
  ]};
}
