import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, realpath, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { collectHostImages, requireHostMetadata } from '../app-binary-preflight.mjs';

function commands({ loads = [], runpaths = [], metadata = [] } = {}) {
  const records = [
    ...loads.map((name) => 'cmd LC_LOAD_DYLIB\n name ' + name + ' (offset 24)'),
    ...runpaths.map((path) => 'cmd LC_RPATH\n path ' + path + ' (offset 12)'),
    ...metadata.map(({ segment = '__DATA', size = '0x334466' } = {}) =>
      'cmd LC_SEGMENT_64\nSection\n sectname __TNSMetadata\n segname ' + segment + '\n size ' + size),
  ];
  return records.map((record, index) => 'Load command ' + index + '\n ' + record).join('\n');
}

const thin = (options) => ({ architectures: ['arm64'], loadCommands: commands(options) });
const fat = (slices) => ({
  architectures: Object.keys(slices),
  loadCommands: Object.entries(slices).map(([architecture, options]) =>
    'Host (architecture ' + architecture + '):\n' + commands(options)).join('\n'),
});

async function fixture(t, files, aliases = {}) {
  const directory = await realpath(await mkdtemp(join(tmpdir(), 'hanlin-host-preflight-')));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const app = join(directory, 'Host.app');
  const inspections = new Map();
  for (const [name, inspection] of Object.entries(files)) {
    const path = resolve(app, name);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, 'unit fixture; inspection output is supplied explicitly');
    inspections.set(path, inspection);
  }
  for (const [alias, target] of Object.entries(aliases)) {
    await symlink(resolve(app, target), resolve(app, alias));
  }
  return {
    app,
    collect: () => collectHostImages(app, join(app, 'Host'), (path) => {
      assert.ok(inspections.has(path), 'Only linked direct host images may be inspected: ' + path);
      return inspections.get(path);
    }),
  };
}

test('accepts metadata in the normal main executable', async (t) => {
  const f = await fixture(t, { Host: thin({ metadata: [{}] }) });
  assert.equal(requireHostMetadata(await f.collect()).get('arm64'), join(f.app, 'Host'));
});

test('accepts the linked debug dylib and exposes it for the provider checks', async (t) => {
  const f = await fixture(t, {
    Host: thin({ loads: ['@rpath/Host.debug.dylib'], runpaths: ['@executable_path'] }),
    'Host.debug.dylib': thin({ metadata: [{}] }),
  });
  const images = await f.collect();
  assert.deepEqual(images.map((image) => image.path), [join(f.app, 'Host'), join(f.app, 'Host.debug.dylib')]);
  assert.equal(requireHostMetadata(images).get('arm64'), join(f.app, 'Host.debug.dylib'));
});

test('rejects missing, empty and wrong-segment host metadata', async (t) => {
  for (const metadata of [[], [{ size: '0x0' }], [{ segment: '__TEXT' }]]) {
    const f = await fixture(t, { Host: thin({ metadata }) });
    const images = await f.collect();
    assert.throws(() => requireHostMetadata(images), /exactly one nonempty/);
  }
});

test('rejects two metadata owners in the same loaded architecture', async (t) => {
  const f = await fixture(t, {
    Host: thin({ loads: ['@loader_path/Host.debug.dylib'], metadata: [{}] }),
    'Host.debug.dylib': thin({ metadata: [{}] }),
  });
  const images = await f.collect();
  assert.throws(() => requireHostMetadata(images), /found 2 host images/);
});

test('does not admit framework metadata or an unlinked app-local dylib', async (t) => {
  const f = await fixture(t, {
    Host: thin({ loads: ['@executable_path/Frameworks/SDK.framework/SDK'] }),
    'Frameworks/SDK.framework/SDK': thin({ metadata: [{}] }),
    'Unlinked.dylib': thin({ metadata: [{}] }),
  });
  const images = await f.collect();
  assert.equal(images.length, 1);
  assert.throws(() => requireHostMetadata(images), /exactly one nonempty/);
});

test('resolves actual rpath order without substituting an app-local shadow', async (t) => {
  const f = await fixture(t, {
    Host: thin({
      loads: ['@rpath/Host.debug.dylib'],
      runpaths: ['@executable_path/../Outside', '@executable_path'],
    }),
    '../Outside/Host.debug.dylib': thin({ metadata: [{}] }),
    'Host.debug.dylib': thin({ metadata: [{}] }),
  });
  const images = await f.collect();
  assert.equal(images.length, 1);
  assert.throws(() => requireHostMetadata(images), /exactly one nonempty/);
});

test('deduplicates linked aliases of the same direct host image', async (t) => {
  const f = await fixture(t, {
    Host: thin({ loads: ['@loader_path/Host.debug.dylib', '@loader_path/Alias.dylib'] }),
    'Host.debug.dylib': thin({ metadata: [{}] }),
  }, { 'Alias.dylib': 'Host.debug.dylib' });
  const images = await f.collect();
  assert.equal(images.length, 2);
  assert.equal(requireHostMetadata(images).size, 1);
});

test('checks metadata ownership per architecture instead of counting fat slices as images', async (t) => {
  const f = await fixture(t, {
    Host: fat({
      arm64: { metadata: [{}] },
      x86_64: { loads: ['@loader_path/Host.debug.dylib'] },
    }),
    'Host.debug.dylib': fat({ arm64: {}, x86_64: { metadata: [{}] } }),
  });
  const owners = requireHostMetadata(await f.collect());
  assert.equal(owners.get('arm64'), join(f.app, 'Host'));
  assert.equal(owners.get('x86_64'), join(f.app, 'Host.debug.dylib'));
});

test('does not let one fat slice satisfy another architecture without metadata', async (t) => {
  const f = await fixture(t, { Host: fat({ arm64: { metadata: [{}] }, x86_64: {} }) });
  const images = await f.collect();
  assert.throws(() => requireHostMetadata(images), /x86_64/);
});
