import test from 'node:test';
import assert from 'node:assert/strict';
import { selectHostPackageVersion } from '../select-host-package-version.mjs';
const metadata = { 'dist-tags': {latest:'26.1.0'}, versions: Object.fromEntries(['24.4.2','24.5.0','24.5.2','24.19.2','26.1.0','24.5.99-beta.1'].map(v=>[v,{}])) };
test('Node declarations stay on the embedded release line and take its latest patch', () => {
  assert.equal(selectHostPackageVersion('@types/node', metadata, '24.5.0'), '24.5.2');
});
test('a Node minor with no matching type release uses an earlier compatible minor', () => {
  assert.equal(selectHostPackageVersion('@types/node', metadata, '24.6.0'), '24.5.2');
});
test('type declaration updates reject an unsupported Node major', () => {
  assert.throws(()=>selectHostPackageVersion('@types/node', metadata, '22.17.0'), /compatible exact version/);
});
test('ordinary host dependencies still select their stable latest version', () => {
  assert.equal(selectHostPackageVersion('node-fetch', metadata, '24.5.0'), '26.1.0');
});
test('missing registry versions fail instead of inventing a pin', () => {
  assert.throws(()=>selectHostPackageVersion('node-fetch', {'dist-tags':{latest:'9.0.0'},versions:{}}, '24.5.0'), /compatible exact version/);
});

// Use the same pinned semver implementation as the production updater.
import semver from '../../../AI_HLY/Downstream/RuntimeCore/Node/Host/node_modules/semver/index.js';
test('new upstream majors requiring a newer Node select the highest compatible stable release', () => {
  const registry = {'dist-tags':{latest:'10.0.4'},versions:{
    '9.9.2':{engines:{node:'^20.17.0 || >=22.9.0'}},
    '9.9.3':{engines:{node:'^20.17.0 || >=22.9.0'}},
    '10.0.4':{engines:{node:'^22.22.2 || ^24.15.0 || >=26.0.0'}},
    '11.0.0-next.1':{engines:{node:'>=22'}}
  }};
  assert.equal(selectHostPackageVersion('@npmcli/arborist',registry,'24.5.0',semver.satisfies),'9.9.3');
  assert.equal(selectHostPackageVersion('@npmcli/arborist',registry,'24.15.0',semver.satisfies),'10.0.4');
});
test('upstream releases with no compatible stable engine fail before writing pins', () => {
  assert.throws(()=>selectHostPackageVersion('fixture',{'dist-tags':{latest:'1.0.0'},versions:{'1.0.0':{engines:{node:'>=26'}}}},'24.5.0',semver.satisfies),/compatible exact version/);
});
