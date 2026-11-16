import test from 'node:test';
import assert from 'node:assert/strict';
import {builtinModules} from 'node:module';
import {runtimeCapabilities} from '../runtime-capabilities.mjs';

test('capability facts identify the actual Node process and its actual built-in namespace',()=>{
  const report=runtimeCapabilities();
  assert.equal(report.observed.node,process.versions.node);
  assert.equal(report.observed.platform,process.platform);
  assert.deepEqual(report.observed.builtInModules,builtinModules);
  assert.ok(report.observed.builtInModules.includes('fs'));
  assert.equal(report.observed.portableShellAdapterVersion,1);
  assert.equal(report.externalExecution.automaticTransfer,false);
  assert.equal(report.finiteCommandAdapter.pid,false);
});
