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
