// Generated from Scripts/NativeScript/window-host.mjs; SHA256 dea0cbf557f1b1f04c3ad54d9792e794192e2f58c6c8926764870b6d5fccedeb
// Host-owned neutral entry. All evaluation, resolution, cache identity and
// import() behavior below belong to the original NativeScript ns:module API.
import { Application } from '@nativescript/core';
import { configureLoader, createPumpingRequire } from 'ns:module';

const scopes = Object.create(null);
const accepted = HanlinNativeScriptWindowFactoryRegistry.registerPackageLoader(configurationJSON => {
  const configuration = JSON.parse(configurationJSON);
  for (const [prefix, entries] of Object.entries(configuration.scopes)) {
    if (Object.hasOwn(scopes, prefix)) throw new Error('A live package namespace cannot be replaced.');
    scopes[prefix] = entries;
  }
  configureLoader({importMap: {scopes}});
  // Do not pump UIKit sources under JS frames or allow a concurrent load to
  // steal factory registration. Ordinary asynchronous dynamic imports continue
  // on the original event loop after the synchronous entry registered.
  const load = createPumpingRequire(configuration.entrypoint, {
    deadlineSeconds: 10, onTimeout: 'throw', pumpRunLoop: false
  });
  load('./bundle.mjs');
});
if (!accepted) throw new Error('The native window host already has a package loader.');
Application.ios.notifyReady();
