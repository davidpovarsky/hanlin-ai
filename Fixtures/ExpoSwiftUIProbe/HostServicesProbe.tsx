import React, {useState} from 'react';
import {View} from 'react-native';
import {Button, Host, Text, VStack, hostServices, type MiniAppActionInvocation,
  type MiniAppJSONValue, type ExpoWidgetPublicationReceipt} from '@hanlin/expo-ui';

// Register the complete declared action table once when the real bundle loads.
// A native caller supplies the UUID/caller/payload; no button invokes these itself.
const handlers = {
  hostServicesEcho: async (request: MiniAppActionInvocation): Promise<MiniAppJSONValue> => {
    const parameters = request.parameters;
    if (!parameters || Array.isArray(parameters) || typeof parameters !== 'object' ||
        typeof parameters.ordinal !== 'number') throw new Error('Expected an ordinal object');
    const bytes = Uint8Array.of(0, 255, parameters.ordinal % 256);
    const path = `host-action-${request.id}.bin`;
    try {
      await hostServices.writeFile(path, bytes, 'cache');
      const actual = await hostServices.readFile(path, 'cache');
      if (!actual || actual.length !== bytes.length || actual.some((value, i) => value !== bytes[i])) {
        throw new Error('Action storage roundtrip failed');
      }
      return {id: request.id, caller: request.caller, action: request.action,
        parameters, computed: parameters.ordinal + 1, storageVerified: true};
    } finally { await hostServices.deleteFile(path, 'cache'); }
  },
  hostServicesPublishWidget: async (request: MiniAppActionInvocation): Promise<MiniAppJSONValue> => {
    if (!request.parameters || Array.isArray(request.parameters) || typeof request.parameters !== 'object') {
      throw new Error('Expected a widget props object');
    }
    const receipt = await hostServices.publishWidget({engine: 'expo', entrypointID: 'widget', props: request.parameters});
    return {...receipt, invocationID: request.id};
  },
  hostServicesFail: async (request: MiniAppActionInvocation): Promise<MiniAppJSONValue> => {
    await hostServices.hasCapability('storage');
    throw new Error(`HOST_SERVICES_EXPECTED_FAILURE:${request.id}`);
  },
};
let actionLoopError: string | undefined;
void hostServices.actions.register(handlers).catch(error => {
  actionLoopError = String(error);
});

export function HostServicesProbe({close}: {close: () => void}) {
  const [files, setFiles] = useState('HOST_SERVICES_FILES_NOT_RUN');
  const [runtime, setRuntime] = useState('HOST_SERVICES_RUNTIME_NOT_RUN');
  const [activities, setActivities] = useState('HOST_SERVICES_ACTIVITY_READS_NOT_RUN');
  const [widget, setWidget] = useState('HOST_SERVICES_WIDGET_STATE_NOT_RUN');
  const [receipt, setReceipt] = useState<ExpoWidgetPublicationReceipt>();
  const fail = (label: string, set: (value: string) => void, error: unknown) =>
    set(`HOST_SERVICES_FAILED:${label}:${String(error)}`);

  const runFiles = async () => {
    const path = `host-services-${Date.now()}-${Math.random().toString(36).slice(2)}.bin`;
    try {
      if (typeof await hostServices.hasCapability('storage') !== 'boolean') throw new Error('Invalid capability response');
      if (await hostServices.readFile(path, 'documents') !== null) throw new Error('New path was not missing');
      const bytes = Uint8Array.from({length: 257}, (_, i) => i % 256);
      const written = await hostServices.writeFile(path, bytes, 'documents');
      const actual = await hostServices.readFile(path, 'documents');
      const paths = await hostServices.listFiles('documents');
      if (!written.ok || !actual || actual.length !== bytes.length ||
          actual.some((value, i) => value !== bytes[i]) || !paths.includes(path)) {
        throw new Error('File data/list response differs from the real write');
      }
      const removed = await hostServices.deleteFile(path, 'documents');
      if (!removed.ok || await hostServices.readFile(path, 'documents') !== null ||
          (await hostServices.listFiles('documents')).includes(path)) throw new Error('Delete was not observable');
      setFiles('HOST_SERVICES_FILES_PASS');
    } catch (error) { fail('files', setFiles, error); }
    finally { try { await hostServices.deleteFile(path, 'documents'); } catch { /* Closing session. */ } }
  };
  const runRuntime = async () => {
    try {
      const result = await hostServices.executeRuntime('javaScriptCore',
        'console.log("HOST_SERVICES_RUNTIME_VALUE:" + (19 + 23));');
      if (!result.executionID || result.didTimeOut || result.wasCancelled ||
          (result.exitCode !== undefined && result.exitCode !== 0) ||
          !result.stdout.includes('HOST_SERVICES_RUNTIME_VALUE:42')) throw new Error('Runtime did not return the executed result');
      setRuntime('HOST_SERVICES_RUNTIME_PASS');
    } catch (error) { fail('runtime', setRuntime, error); }
  };
  const readActivities = async () => {
    try {
      const enabled = await hostServices.liveActivities.areEnabled();
      const ids = await hostServices.liveActivities.list();
      if (typeof enabled !== 'boolean' || !Array.isArray(ids) || ids.some(id => typeof id !== 'string')) {
        throw new Error('Invalid native activity status');
      }
      setActivities(`HOST_SERVICES_ACTIVITY_READS_PASS:enabled=${enabled};count=${ids.length}`);
    } catch (error) { fail('activities', setActivities, error); }
  };
  const publish = async () => {
    try {
      const actual = await hostServices.publishWidget({engine: 'expo', entrypointID: 'widget',
        props: {title: 'HOST_SERVICES_PUBLISHED_WIDGET', counter: 31}});
      if (!actual.ok || !actual.published || actual.publication !== 'prepared-expo-state' ||
          !actual.stateCommitted || !actual.catalogVisible || !actual.reloadRequested || actual.osRendered !== null ||
          actual.generation <= 0 || actual.revision <= 0 || !/^[0-9a-f]{64}$/.test(actual.artifactSHA256) ||
          actual.entrypointID !== 'widget' || actual.variantID !== 'default' || !actual.supportedFamilies.includes('systemMedium')) {
        throw new Error('Missing exact committed-state receipt');
      }
      setReceipt(actual);
      setWidget('HOST_SERVICES_WIDGET_STATE_PASS');
    } catch (error) { fail('widget', setWidget, error); }
  };

  return <View style={{flex: 1}}><Host style={{flex: 1}}><VStack spacing={8}>
    <Text>Host Services Probe</Text>
    <Button label="Run Host Services Files" onPress={() => {void runFiles();}} />
    <Text>{files}</Text>
    <Button label="Run Host Services Runtime" onPress={() => {void runRuntime();}} />
    <Text>{runtime}</Text>
    <Button label="Read Host Live Activity Status" onPress={() => {void readActivities();}} />
    <Text>{activities}</Text>
    <Button label="Publish Prepared Expo Widget" onPress={() => {void publish();}} />
    <Text>{widget}</Text>
    {receipt && <Text>{`Widget generation ${receipt.generation}, revision ${receipt.revision}`}</Text>}
    <Text>{actionLoopError ? `HOST_SERVICES_ACTION_LOOP_FAILED:${actionLoopError}` : 'HOST_SERVICES_ACTION_LOOP_STARTED'}</Text>
    <Button label="Close Host Services Probe" onPress={close} />
  </VStack></Host></View>;
}
