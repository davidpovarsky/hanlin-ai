// Literal operation names only: a delegated prefix does not grant every name.
function caseOperations(text) {
  return [...text.matchAll(/^\s*case\s+((?:"[^"\r\n]+"\s*,\s*)*"[^"\r\n]+")\s*:/gm)]
    .flatMap(match => [...match[1].matchAll(/"([^"\r\n]+)"/g)].map(value => value[1]));
}

export function auditExpoOperationRoutes({adapter, externalSession, shortcutSession, platform, nativeNames, facadeOperations}) {
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
  // A Shortcuts child owns one reporter for the claimed command. Inspect the
  // connected declarations: matching guard text in an unrelated helper must not
  // establish operation availability or permit a different invocation's Progress.
  const shortcutText = shortcutSession?.text ?? '';
  const shortcutExecution = shortcutText.match(
    /@MainActor\s+enum\s+MiniAppsShortcutExecution\s*\{([\s\S]*?)^\}/m)?.[1] ?? '';
  const shortcutIntent = shortcutText.match(
    /^struct\s+HanlinRunMiniAppShortcutIntent:\s*LongRunningIntent,\s*CancellableIntent\s*\{([\s\S]*?)^\}/m)?.[1] ?? '';
  const shortcutPerform = shortcutIntent.match(
    /^    func\s+perform\(\)\s*async\s+throws\s*->\s*some\s+IntentResult\s*&\s*ReturnsValue<IntentFile>\s*&\s*ShowsSnippetIntent\s*\{([\s\S]*?)^    \}/m)?.[1] ?? '';
  const executorBody = shortcutPerform.match(
    /let\s+receipt\s*=\s*try\s+await\s+executor\.execute\(command\)\s*\{\s*ownedCommand\s+in([\s\S]*?)^            \}/m)?.[1] ?? '';
  const operationBody = executorBody.match(
    /let\s+operation\s*=\s*\{([\s\S]*?)^                \}/m)?.[1] ?? '';
  const shortcutDispatch = /let\s+reportedProgress\s*=\s*progress/.test(shortcutPerform)
    && /let\s+store\s*=\s*try\s+await\s+HanlinScriptingPlatform\.productExtensionStore\(\)/.test(shortcutPerform)
    && /let\s+executor\s*=\s*HanlinInvocationExecutor\(store:\s*store\)/.test(shortcutPerform)
    && /return\s+try\s+await\s+MiniAppsShortcutExecution\.run\(\s*command:\s*ownedCommand,\s*store:\s*store,\s*progress:\s*reportedProgress\s*\)/.test(operationBody)
    && /return\s+try\s+await\s+self\.performBackgroundTask\(operation:\s*operation\)/.test(executorBody)
    && /return\s+try\s+await\s+self\.withIntentCancellationHandler\(operation:\s*operation\)/.test(executorBody);
  const makeCommand = shortcutExecution.match(
    /^    static\s+func\s+makeCommand\(\s*action:\s*HanlinScriptActionEntity,\s*input:\s*HanlinValue,\s*canPresentUI:\s*Bool\s*=\s*false\s*\)\s*async\s+throws\s*->\s*HanlinScriptResumeCommand\s*\{([\s\S]*?)^    \}/m)?.[1] ?? '';
  const shortcutMode = /let\s+runsInForeground\s*=\s*systemContext\.currentMode\s*==\s*\.foreground/.test(shortcutPerform)
    && /let\s+command\s*=\s*try\s+await\s+MiniAppsShortcutExecution\.makeCommand\(\s*action:\s*action,\s*input:\s*inputValue,\s*canPresentUI:\s*runsInForeground\s*\)/.test(shortcutPerform)
    && /return\s+HanlinScriptResumeCommand\(invocation:\s*\.init\(\s*identity:\s*record\.identity,\s*entityID:\s*record\.id,\s*parameters:\s*input,\s*continueInForeground:\s*canPresentUI,\s*delivery:\s*\.init\(appID:\s*appID,\s*source:\s*\.shortcuts,\s*expiresAt:\s*\.now\.addingTimeInterval\(HanlinInvocationDelivery\.maximumLifetime\s*-\s*1\),\s*userGesturePresent:\s*true,\s*canPresentUI:\s*canPresentUI\s*\)\s*\)\s*\)/.test(makeCommand);
  const shortcutRun = shortcutExecution.match(
    /^    static\s+func\s+run\(\s*command:\s*HanlinScriptResumeCommand,\s*store:\s*HanlinScriptExtensionStore,\s*progress:\s*Progress\s*\)\s*async\s+throws\s*->\s*HanlinValue\s*\{([\s\S]*?)^    \}/m)?.[1] ?? '';
  const reporter = shortcutText.match(
    /@MainActor\s+final\s+class\s+MiniAppsShortcutProgressReporter\s*\{([\s\S]*?)^\}/m)?.[1] ?? '';
  const reporterInit = reporter.match(
    /^    init\(\s*progress:\s*Progress,\s*commandID:\s*UUID,\s*store:\s*HanlinScriptExtensionStore\s*\)\s*throws\s*\{([\s\S]*?)^    \}/m)?.[1] ?? '';
  const shortcutHandler = reporter.match(
    /^    func\s+receive\(\s*_\s+operation:\s*String,\s*payload:\s*String\s*\)\s*throws\s*->\s*String\s*\{([\s\S]*?)^    \}/m)?.[1] ?? '';
  const cleanup = shortcutRun.match(/\bdefer\s*\{([\s\S]*?)^        \}/m)?.[1] ?? '';
  const shortcutOperations = [...shortcutHandler.matchAll(
    /guard\s+operation\s*==\s*"([^"]+)"\s+else\s*\{/g)].map(match => match[1]);
  const shortcutConnected = /let\s+presentsUI\s*=\s*command\.invocation\.delivery\?\.canPresentUI\s*==\s*true/.test(shortcutRun)
    && /let\s+platform\s*=\s*HanlinScriptingPlatform\(\s*actionPresentationAllowed:\s*presentsUI,\s*registersForegroundContinuation:\s*false\s*\)/.test(shortcutRun)
    && /let\s+reporter\s*=\s*try\s+MiniAppsShortcutProgressReporter\(\s*progress:\s*progress,\s*commandID:\s*command\.id,\s*store:\s*store\s*\)/.test(shortcutRun)
    && /platform\.externalMiniAppOperation\s*=\s*\{\s*operation,\s*payload\s+in\s*try\s+reporter\.receive\(operation,\s*payload:\s*payload\)\s*\}/.test(shortcutRun)
    && /try\s+await\s+platform\.executeClaimedShortcutCommand\(command\)/.test(shortcutRun)
    && /reporter\.close\(\)[\s\S]*platform\.externalMiniAppOperation\s*=\s*nil/.test(cleanup)
    && /func\s+close\(\)\s*\{\s*progress\s*=\s*nil\s*\}/.test(reporter);
  const reporterOwned = /guard\s+let\s+receipt\s*=\s*try\s+store\.receipt\(for:\s*commandID\),\s*receipt\.status\s*==\s*\.running,\s*let\s+leaseID\s*=\s*receipt\.leaseID,\s*receipt\.leaseExpiresAt\.map\(\{\s*\$0\s*>\s*\.now\s*\}\)\s*==\s*true\s+else\s*\{\s*throw\s+HanlinInvocationQueueError\.staleLease\s*\}/.test(reporterInit)
    && /self\.progress\s*=\s*progress;\s*self\.commandID\s*=\s*commandID;\s*self\.leaseID\s*=\s*leaseID;\s*self\.store\s*=\s*store/.test(reporterInit)
    && /try\s+Task\.checkCancellation\(\)/.test(shortcutHandler)
    && /guard\s+operation\s*==\s*"miniapps\.shortcutProgress"\s+else\s*\{\s*throw\s+MiniAppsShortcutError\.unsupportedOperation\s*\}/.test(shortcutHandler)
    && /guard\s+let\s+progress,\s*let\s+receipt\s*=\s*try\s+store\.receipt\(for:\s*commandID\),\s*receipt\.status\s*==\s*\.running,\s*receipt\.leaseID\s*==\s*leaseID,\s*receipt\.leaseExpiresAt\.map\(\{\s*\$0\s*>\s*\.now\s*\}\)\s*==\s*true,\s*!receipt\.cancellationRequested\s+else\s*\{\s*throw\s+CancellationError\(\)\s*\}/.test(shortcutHandler);
  const shortcutProgress = /let\s+update\s*=\s*try\s+JSONDecoder\(\)\.decode\(HanlinShortcutProgress\.self,\s*from:\s*Data\(payload\.utf8\)\)\s*try\s+update\.validate\(\)\s*progress\.totalUnitCount\s*=\s*update\.totalUnitCount\s*progress\.completedUnitCount\s*=\s*update\.completedUnitCount/.test(shortcutHandler);
  if (!shortcutMode || !shortcutDispatch || !shortcutConnected || !reporterOwned || !shortcutProgress || shortcutOperations.length !== 1
      || shortcutOperations[0] !== 'miniapps.shortcutProgress') {
    throw new Error('Shortcuts progress callback linkage changed; audit the owned native handler.');
  }
  const operations = [...new Set([...direct, ...delegated, ...shortcutOperations])];
  const missing = [...new Set(facadeOperations.filter(operation => !operations.includes(operation)))];
  if (!nativeNames.includes('invoke') || missing.length) {
    throw new Error(`Existing Expo facade/native operation drift; missing invoke or explicit handlers: ${JSON.stringify(missing)}`);
  }
  return {operations, routes: [
    {kind: 'direct', source: adapter.path, operations: direct},
    {kind: 'delegated', source: externalSession.path, suppliedBy: platform.path,
      operations: delegated, condition: 'An active external MiniApp invocation supplies the typed callback.'},
    {kind: 'shortcuts', source: shortcutSession.path, suppliedBy: platform.path,
      operations: shortcutOperations, condition: 'An owned Shortcuts invocation validates its live lease and typed Progress; UI admission follows its validated foreground/background delivery.'},
  ]};
}
