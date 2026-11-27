import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {auditExpoOperationRoutes} from '../miniapp-expo-operations.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
async function fixture() {
  const source = async file => ({path: file, text: await readFile(path.join(root, file), 'utf8')});
  const module = await source('Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinHostServicesModule.swift');
  const facade = await source('Packages/HanlinExpoUI/src/host-services.ts');
  return {adapter: await source('AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift'),
    externalSession: await source('AI_HLY/Downstream/ProductSplitIntegration/HanlinExternalMiniAppSession.swift'),
    shortcutSession: await source('HanlinMiniAppsApp/MiniAppsShortcutIntent.swift'),
    platform: await source('AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift'),
    nativeNames: [...module.text.matchAll(/AsyncFunction\("([^"]+)"\)/g)].map(match => match[1]),
    facadeOperations: [...facade.text.matchAll(/invoke(?:<[^\n]+?>)?\('([^']+)'/g)].map(match => match[1])};
}

test('actual Expo grouped cases and explicitly connected external cases cover the typed facade', async () => {
  const input = await fixture(), result = auditExpoOperationRoutes(input);
  for (const name of ['liveActivities.areEnabled', 'liveActivities.list', 'liveActivities.start', 'liveActivities.update', 'liveActivities.end']) assert.ok(result.routes[0].operations.includes(name));
  for (const name of ['miniapps.context', 'miniapps.readAttachment', 'miniapps.writeAttachment', 'miniapps.complete', 'miniapps.cancel', 'miniapps.return']) assert.ok(result.routes[1].operations.includes(name));
  assert.ok(result.routes[0].operations.includes('widgets.publishPrepared'));
  assert.match(result.routes[1].condition, /active external MiniApp invocation/);
  assert.deepEqual(result.routes[2].operations, ['miniapps.shortcutProgress']);
  assert.match(result.routes[2].condition, /owned Shortcuts invocation/);
  assert.ok(input.facadeOperations.every(name => result.operations.includes(name)));
});

test('a delegated prefix cannot hide a missing operation or a disconnected callback', async () => {
  const input = await fixture();
  assert.throws(() => auditExpoOperationRoutes({...input, facadeOperations: [...input.facadeOperations, 'miniapps.notAnImplementedOperation']}), /explicit handlers/);
  assert.throws(() => auditExpoOperationRoutes({...input, adapter: {...input.adapter, text: input.adapter.text.replace('"liveActivities.start", ', '')}}), /explicit handlers/);
  assert.throws(() => auditExpoOperationRoutes({...input, platform: {...input.platform, text: input.platform.text.replaceAll('externalMiniAppOperation: externalMiniAppOperation', 'externalMiniAppOperation: nil')}}), /callback linkage changed/);
  assert.throws(() => auditExpoOperationRoutes({...input, platform: {...input.platform, text: input.platform.text.replace('self.publishPreparedExpoWidget(', 'HanlinScriptingPlatform.shared.publishPreparedExpoWidget(')}}), /callback linkage changed/);
  assert.throws(() => auditExpoOperationRoutes({...input, platform: {...input.platform, text: input.platform.text.replace('expectedGeneration: package.record.activeGeneration', 'expectedGeneration: 0')}}), /callback linkage changed/);
  assert.throws(() => auditExpoOperationRoutes({...input, nativeNames: input.nativeNames.filter(name => name !== 'invoke')}), /missing invoke/);
});

test('the connected assistant factory is explicit without relaxing other constructor arguments', async () => {
  const input = await fixture();
  const argument = 'assistantServiceFactory: assistantServiceFactory,';
  assert.ok(input.platform.text.includes(argument), 'fixture must exercise the active Expo constructor');
  const spaced = input.platform.text.replace(argument, 'assistantServiceFactory:\n                        assistantServiceFactory,');
  assert.deepEqual(auditExpoOperationRoutes({...input, platform: {...input.platform, text: spaced}}).operations,
    auditExpoOperationRoutes(input).operations);
  for (const replacement of [
    '',
    'assistantServiceFactory: nil,',
    'assistantServiceFactory: HanlinScriptingPlatform.shared.assistantServiceFactory,',
    'assistantServiceFactory: assistantServiceFactory, unrelatedCapability: anotherOwner,',
  ]) {
    const text = input.platform.text.replace(argument, replacement);
    assert.notEqual(text, input.platform.text);
    assert.throws(() => auditExpoOperationRoutes({...input, platform: {...input.platform, text}}),
      /callback linkage changed/, replacement || 'missing assistant factory');
  }
});

test('Shortcuts progress requires its actual validated callback and owned claimed dispatch', async () => {
  const input = await fixture();
  for (const [before, after] of [
    ['operation == "miniapps.shortcutProgress"', 'operation.hasPrefix("miniapps.")'],
    ['operation == "miniapps.shortcutProgress"', 'operation == "miniapps.notImplemented"'],
    ['try update.validate()', ''],
    ['progress.completedUnitCount = update.completedUnitCount', 'progress.completedUnitCount = 0'],
    ['let reportedProgress = progress', 'let reportedProgress = Progress()'],
    ['HanlinInvocationExecutor(store: store)', 'HanlinInvocationExecutor(store: anotherStore)'],
    ['executor.execute(command) { ownedCommand in', 'executor.execute(anotherCommand) { ownedCommand in'],
    ['MiniAppsShortcutExecution.run(', 'UnusedShortcutExecution.run('],
    ['command: ownedCommand, store: store, progress: reportedProgress', 'command: command, store: store, progress: reportedProgress'],
    ['command: ownedCommand, store: store, progress: reportedProgress', 'command: ownedCommand, store: anotherStore, progress: reportedProgress'],
    ['command: ownedCommand, store: store, progress: reportedProgress', 'command: ownedCommand, store: store, progress: Progress()'],
    ['performBackgroundTask(operation: operation)', 'performBackgroundTask(operation: anotherOperation)'],
    ['withIntentCancellationHandler(operation: operation)', 'withIntentCancellationHandler(operation: anotherOperation)'],
    ['systemContext.currentMode == .foreground', 'systemContext.currentMode.canContinueInForeground'],
    ['systemContext.currentMode == .foreground', 'true'],
    ['action: action, input: inputValue, canPresentUI: runsInForeground', 'action: action, input: inputValue, canPresentUI: true'],
    ['canPresentUI: Bool = false', 'canPresentUI: Bool = true'],
    ['continueInForeground: canPresentUI', 'continueInForeground: true'],
    ['userGesturePresent: true, canPresentUI: canPresentUI', 'userGesturePresent: true, canPresentUI: true'],
    ['command.invocation.delivery?.canPresentUI == true', 'true'],
    ['actionPresentationAllowed: presentsUI', 'actionPresentationAllowed: true'],
    ['registersForegroundContinuation: false', 'registersForegroundContinuation: true'],
    ['platform.executeClaimedShortcutCommand(command)', 'HanlinScriptingPlatform.shared.executeClaimedShortcutCommand(command)'],
    ['MiniAppsShortcutProgressReporter(progress: progress, commandID: command.id, store: store)',
      'MiniAppsShortcutProgressReporter(progress: Progress(), commandID: command.id, store: store)'],
    ['MiniAppsShortcutProgressReporter(progress: progress, commandID: command.id, store: store)',
      'MiniAppsShortcutProgressReporter(progress: progress, commandID: UUID(), store: store)'],
    ['MiniAppsShortcutProgressReporter(progress: progress, commandID: command.id, store: store)',
      'MiniAppsShortcutProgressReporter(progress: progress, commandID: command.id, store: anotherStore)'],
    ['try reporter.receive(operation, payload: payload)', 'try anotherReporter.receive(operation, payload: payload)'],
    ['reporter.close()', ''],
    ['platform.externalMiniAppOperation = nil', ''],
    ['func close() { progress = nil }', 'func close() {}'],
    ['self.leaseID = leaseID', 'self.leaseID = UUID()'],
    ['self.commandID = commandID', 'self.commandID = UUID()'],
    ['self.store = store', 'self.store = anotherStore'],
    ['try Task.checkCancellation()\n        guard operation', 'guard operation'],
    ['receipt.status == .running,\n              let leaseID', 'receipt.status == .succeeded,\n              let leaseID'],
    ['receipt.status == .running, receipt.leaseID == leaseID', 'receipt.status == .succeeded, receipt.leaseID == leaseID'],
    ['receipt.leaseID == leaseID', 'receipt.leaseID != nil'],
    ['!receipt.cancellationRequested', 'true'],
  ]) {
    const text = input.shortcutSession.text.replace(before, after);
    assert.notEqual(text, input.shortcutSession.text, before);
    assert.throws(() => auditExpoOperationRoutes({...input,
      shortcutSession: {...input.shortcutSession, text}}), /Shortcuts progress callback linkage changed/, before);
  }
  const expires = 'receipt.leaseExpiresAt.map({ $0 > .now }) == true';
  const pieces = input.shortcutSession.text.split(expires);
  assert.equal(pieces.length, 3, 'both reporter admission and receive validate lease expiry');
  for (let index = 0; index < 2; index += 1) {
    const text = pieces[0] + (index === 0 ? 'true' : expires) + pieces[1]
      + (index === 1 ? 'true' : expires) + pieces[2];
    assert.throws(() => auditExpoOperationRoutes({...input,
      shortcutSession: {...input.shortcutSession, text}}), /Shortcuts progress callback linkage changed/);
  }
});

test('unconnected or dead helper validation cannot qualify the Shortcuts operation', async () => {
  const input = await fixture();
  for (const [before, after] of [
    ['struct HanlinRunMiniAppShortcutIntent:', 'struct UnusedShortcutIntent:'],
    ['static func makeCommand(action: HanlinScriptActionEntity', 'static func unusedMakeCommand(action: HanlinScriptActionEntity'],
    ['final class MiniAppsShortcutProgressReporter {', 'final class UnusedShortcutProgressReporter {'],
    ['func receive(_ operation: String, payload: String)', 'func unusedReceive(_ operation: String, payload: String)'],
    ['static func run(command: HanlinScriptResumeCommand', 'static func unusedRun(command: HanlinScriptResumeCommand'],
  ]) {
    const text = input.shortcutSession.text.replace(before, after);
    assert.notEqual(text, input.shortcutSession.text);
    assert.throws(() => auditExpoOperationRoutes({...input,
      shortcutSession: {...input.shortcutSession, text}}), /Shortcuts progress callback linkage changed/);
  }
  const text = input.shortcutSession.text.replace('try update.validate()', '')
    + '\nprivate func unusedProgressValidation() throws { try update.validate() }\n';
  assert.throws(() => auditExpoOperationRoutes({...input,
    shortcutSession: {...input.shortcutSession, text}}), /Shortcuts progress callback linkage changed/);
});
