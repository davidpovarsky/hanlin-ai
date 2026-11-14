import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

test('actual Host global installer preserves C values when struct names collide', async () => {
  const source = await readFile(new URL('../../../Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/nativescript/native-api/ffi/objc/shared/bridge/Install.mm', import.meta.url), 'utf8');
  const installer = source.match(/R"Engine_GLOBALS\(([\s\S]*?)\)Engine_GLOBALS"/)[1];
  const ranges = {sharedRegionsCount: 0};
  const api = {timezone: 3600, dyld_shared_cache_ranges: ranges,
    metadata: Object.fromEntries(['classNames','functionNames','constantNames','protocolNames','enumNames','structNames','unionNames']
      .map(name => [name, () => ['constantNames','structNames'].includes(name) ? ['timezone','dyld_shared_cache_ranges'] : []])),
    getStruct() { return initial => ({...initial}); }};
  const context = vm.createContext({__fixtureNativeAPI: api});
  vm.runInContext(installer + '("__fixtureNativeAPI");', context);
  assert.equal(vm.runInContext('timezone', context), 3600);
  assert.equal(vm.runInContext('dyld_shared_cache_ranges', context), ranges);
  assert.throws(() => vm.runInContext('new timezone()', context), /not a constructor/);
});
