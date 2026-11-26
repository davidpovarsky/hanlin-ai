import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
const resources = new URL('../../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/', import.meta.url);

async function harness() {
  const windows = [];
  const calls = [];
  let registered;
  const app = {
    _registerWindow(window) { windows.push(window); },
    _unregisterWindow(window) {
      const index = windows.indexOf(window);
      if (index >= 0) windows.splice(index, 1);
      window.state = 'closed';
      if (window.rootView) window.rootView._nativeWindow = null;
      if (window.isPrimary && windows.length) windows[0].isPrimary = true;
    },
    notifyReady() {},
    _ensureAppCssLoaded() {}
  };
  const application = {ios: app, get primaryWindow() { return windows.find(window => window.isPrimary); }};
  class IOSNativeWindow {
    constructor(scene, surface, id, isPrimary, role) {
      Object.assign(this, {id, isPrimary, role, state: 'attached', events: []});
    }
    setContent(root) {
      this.rootView = root;
      root._nativeWindow = this;
      this._setNativeContent(root);
    }
    _getViewController(root) { return root.controller; }
    _setViewControllerView() {}
    _notifyEvent(event) { this.events.push(event); }
    _reattach(scene, surface) { this.state = 'attached'; this.surface = surface; }
    _detach() { this.state = 'detached'; }
    orientation() { return 'portrait'; }
    systemAppearance() { return this._getSystemAppearance(); }
    layoutDirection() { return this._getLayoutDirection(); }
    _getSystemAppearanceValue(value) { return value; }
    _getLayoutDirectionValue(value) { return value; }
    _setSystemAppearance() {}
    _setLayoutDirection() {}
  }
  const context = vm.createContext({
    console,
    HanlinNativeScriptWindowFactoryRegistry: {
      registerFactory(factory) { if (registered) return false; registered = factory; return true; }
    },
    // The cooperative helper must never use this deliberately wrong global.
    HanlinNativeServicesBridge: {activeSessionBridge() { throw new Error('used global request bridge'); }}
  });
  const core = new vm.SyntheticModule(['Application', 'NativeWindowEvents'], function() {
    this.setExport('Application', application);
    this.setExport('NativeWindowEvents', {attached: 'attached', close: 'close'});
  }, {context});
  const ios = new vm.SyntheticModule(['IOSNativeWindow'], function() {
    this.setExport('IOSNativeWindow', IOSNativeWindow);
  }, {context});
  const helper = new vm.SyntheticModule(['IOSHelper'], function() {
    this.setExport('IOSHelper', {traitCollectionColorAppearanceChangedEvent: 'color',
      traitCollectionLayoutDirectionChangedEvent: 'direction'});
  }, {context});
  const services = new vm.SourceTextModule(await readFile(new URL('host-services/index.mjs', resources), 'utf8'), {context});
  const module = new vm.SourceTextModule(await readFile(new URL('window-factory/index.mjs', resources), 'utf8'), {context});
  await module.link(specifier => ({
    '@nativescript/core': core,
    '@nativescript/core/native-window/native-window.ios': ios,
    '@nativescript/core/ui/core/view/view-helper': helper,
    '@hanlin/host-services': services
  })[specifier]);
  await module.evaluate();
  const view = () => ({on() {}, controller: {traitCollection: {userInterfaceStyle: 1, layoutDirection: 0}}});
  const open = id => {
    const native = {
      windowID: id, closed: false, presented: [],
      containerController: {traitCollection: {userInterfaceStyle: 1, layoutDirection: 0}},
      servicesBridge: {
        sendRequestActionCapabilityPayloadJSONCompletion(target, operation, capability, payload, completion) {
          calls.push({id, operation, payload: JSON.parse(payload)});
          queueMicrotask(() => completion(JSON.stringify(operation === 'miniapps.context' ? {id} : {ok: true}), null));
        },
        executeRuntimeCompletion(payload, completion) {
          calls.push({id, operation: 'runtime', payload: JSON.parse(payload)});
          completion('{}', null);
          return id + '-runtime';
        },
        cancelRuntime(request) { calls.push({id, operation: 'cancelRuntime', request}); return true; }
      },
      setLifecycleHandler(handler) { this.handler = handler; },
      presentViewController(controller) { this.presented.push(controller); },
      showFailure(error) { this.error = error; },
      close() { if (this.closed) return; this.closed = true; this.handler('close', null); }
    };
    try { registered(native); }
    catch (error) { native.close(); throw error; }
    return native;
  };
  return {windows, calls, view, open, register: module.namespace.registerWindowFactory};
}

test('two fresh roots retain explicit request contexts and reverse-order async returns', async () => {
  const h = await harness();
  const clients = new Map();
  h.register(({id, services}) => { clients.set(id, services); return h.view(); });
  const a = h.open('A');
  const b = h.open('B');
  assert.equal(a.presented.length, 1);
  assert.equal(b.presented.length, 1);
  assert.notEqual(a.presented[0], b.presented[0]);
  assert.equal((await clients.get('A').miniapps.getContext()).id, 'A');
  assert.equal((await clients.get('B').miniapps.getContext()).id, 'B');
  await clients.get('B').miniapps.complete('B edited');
  await clients.get('A').miniapps.complete('A edited');
  assert.deepEqual(h.calls.filter(call => call.operation === 'miniapps.complete').map(call => [call.id, call.payload]),
    [['B', 'B edited'], ['A', 'A edited']]);
});

test('closing first or second window preserves remaining root and its attachment/runtime routing', async () => {
  for (const first of ['A', 'B']) {
    const h = await harness();
    const clients = new Map();
    h.register(({id, services}) => { clients.set(id, services); return h.view(); });
    const contexts = {A: h.open('A'), B: h.open('B')};
    const remaining = first === 'A' ? 'B' : 'A';
    const root = h.windows.find(window => window.id === remaining).rootView;
    contexts[first].close();
    assert.equal(h.windows.length, 1);
    assert.equal(h.windows[0].rootView, root);
    await clients.get(remaining).miniapps.readAttachment('file-' + remaining);
    const handle = clients.get(remaining).startRuntime('javaScriptCore', '1');
    assert.equal(handle.requestID, remaining + '-runtime');
    handle.cancel();
    assert.deepEqual(h.calls.map(call => call.id), [remaining, remaining, remaining]);
  }
});

test('a reused root is rejected without moving it out of the first window', async () => {
  const h = await harness();
  const root = h.view();
  h.register(() => root);
  h.open('A');
  assert.throws(() => h.open('B'), /fresh root/);
  assert.equal(h.windows.length, 1);
  assert.equal(root._nativeWindow.id, 'A');
});

test('a delayed factory cannot present or return after its own window closes', async () => {
  const h = await harness();
  let resolve;
  h.register(() => new Promise(done => { resolve = done; }));
  const context = h.open('A');
  context.close();
  resolve(h.view());
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(context.presented.length, 0);
  assert.equal(h.windows.length, 0);
  assert.equal(h.calls.length, 0);
});

test('scene detach and reattach keeps the same root/request binding', async () => {
  const h = await harness();
  let services;
  h.register(value => { services = value.services; return h.view(); });
  const context = h.open('A');
  const root = h.windows[0].rootView;
  context.handler('detached', null);
  assert.equal(h.windows[0].state, 'detached');
  context.handler('attached', {windowScene: {id: 'scene-A'}});
  assert.equal(h.windows[0].rootView, root);
  assert.equal(h.windows[0].state, 'attached');
  assert.equal((await services.miniapps.getContext()).id, 'A');
});
