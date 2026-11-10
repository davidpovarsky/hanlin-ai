import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { PassThrough, Readable } from 'node:stream';
import { executePortableShell } from '../portable-shell.mjs';

async function fixture(t) {
  const cwd = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-portable-shell-'));
  t.after(() => fs.rm(cwd, { recursive: true, force: true }));
  const stdout = new PassThrough(), stderr = new PassThrough();
  const out = [], err = [];
  stdout.on('data', chunk => out.push(chunk));
  stderr.on('data', chunk => err.push(chunk));
  return { cwd, stdout, stderr, stdin: Readable.from([]), environment: {},
    out: () => Buffer.concat(out).toString(), err: () => Buffer.concat(err).toString() };
}

test('actual Yarn language preserves quoting, Unicode argv, environment and cwd across command adapters', async t => {
  const io = await fixture(t);
  await fs.mkdir(path.join(io.cwd, 'sub dir'));
  const calls = [];
  const code = await executePortableShell(`cd 'sub dir' && NAME='שלום world'; LOCAL='only this command' inspect "$NAME" 'a;b|c' ""`, [], {
    ...io,
    dispatch: async request => { calls.push(request); return 0; },
  });
  assert.equal(code, 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, 'inspect');
  assert.deepEqual(calls[0].arguments, ['שלום world', 'a;b|c', '']);
  assert.equal(calls[0].environment.NAME, 'שלום world');
  assert.equal(calls[0].environment.LOCAL, 'only this command');
  assert.equal(calls[0].cwd, path.join(io.cwd, 'sub dir'));
  assert.equal(io.environment.NAME, undefined);
});

test('real interpreter pipes stdin and redirects output while retaining exact failing exit status', async t => {
  const io = await fixture(t);
  const code = await executePortableShell(`echo 'שלום 👋🏽' | transform > 'result.txt'; fail 2> 'error.txt'`, [], {
    ...io,
    dispatch: async ({ command, stdin, stdout, stderr }) => {
      if (command === 'transform') {
        for await (const chunk of stdin) stdout.write(Buffer.from(chunk).toString().replace('שלום', 'hello'));
        return 0;
      }
      stderr.write('actual failure\n');
      return 23;
    },
  });
  assert.equal(code, 23);
  assert.equal(await fs.readFile(path.join(io.cwd, 'result.txt'), 'utf8'), 'hello 👋🏽\n');
  assert.equal(await fs.readFile(path.join(io.cwd, 'error.txt'), 'utf8'), 'actual failure\n');
});

test('dynamic command names and command substitutions always reach adapters, never OS spawn', async t => {
  const io = await fixture(t);
  const calls = [];
  const code = await executePortableShell(`CMD=inspect; "$CMD" "$(produce)"; command echo external`, [], {
    ...io,
    dispatch: async ({ command, arguments: args, stdout }) => {
      calls.push([command, args]);
      if (command === 'produce') stdout.write('שלום\n');
      return 0;
    },
  });
  assert.equal(code, 0);
  assert.deepEqual(calls, [['produce', []], ['inspect', ['שלום']], ['echo', ['external']]]);
});

test('globs, groups and logical short-circuiting use the actual parser/interpreter', async t => {
  const io = await fixture(t);
  await fs.writeFile(path.join(io.cwd, 'a.txt'), 'a');
  await fs.writeFile(path.join(io.cwd, 'b.txt'), 'b');
  const calls = [];
  const code = await executePortableShell(`false && forbidden; (inspect *.txt ) || forbidden; { echo done; }`, [], {
    ...io, dispatch: async ({ command, arguments: args }) => { calls.push([command, args]); return 0; },
  });
  assert.equal(code, 0);
  assert.deepEqual(calls, [['inspect', ['a.txt', 'b.txt']]]);
  assert.equal(io.out(), 'done\n');
});

test('missing adapters fail truthfully and can be handled with shell control flow', async t => {
  const io = await fixture(t);
  assert.equal(await executePortableShell('unknown-desktop-program', [], io), 127);
  assert.match(io.err(), /No linked runtime adapter/);
  assert.equal(await executePortableShell('unknown-desktop-program || echo handled', [], io), 0);
  assert.equal(io.out(), 'handled\n');
});
