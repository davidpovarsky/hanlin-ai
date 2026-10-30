import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Read Mach-O load commands directly, so the same binary facts can be checked
// on Windows and on the Apple runner. This is an audit, not a signing check.
export function inspectMachO(file) {
  const original = fs.readFileSync(file);
  let bytes = original;
  if ([0xcafebabe, 0xcafebabf].includes(bytes.readUInt32BE(0))) {
    const wide = bytes.readUInt32BE(0) === 0xcafebabf;
    let slice;
    for (let index = 0; index < bytes.readUInt32BE(4); index++) {
      const offset = 8 + index * (wide ? 32 : 20);
      if (bytes.readUInt32BE(offset) === 0x0100000c) {
        const begin = wide ? Number(bytes.readBigUInt64BE(offset + 8)) : bytes.readUInt32BE(offset + 8);
        const size = wide ? Number(bytes.readBigUInt64BE(offset + 16)) : bytes.readUInt32BE(offset + 12);
        slice = bytes.subarray(begin, begin + size);
      }
    }
    if (!slice) throw new Error(`No arm64 slice: ${file}`);
    bytes = slice;
  }
  if (bytes.readUInt32LE(0) !== 0xfeedfacf) throw new Error(`Expected 64-bit Mach-O: ${file}`);
  const dylibs = [];
  let offset = 32;
  for (let index = 0; index < bytes.readUInt32LE(16); index++) {
    const command = bytes.readUInt32LE(offset), size = bytes.readUInt32LE(offset + 4);
    if (size < 8 || offset + size > bytes.length) throw new Error('Invalid Mach-O command');
    if ([0x0c, 0x80000018, 0x8000001f, 0x80000023].includes(command)) {
      const begin = offset + bytes.readUInt32LE(offset + 8);
      const end = bytes.indexOf(0, begin);
      if (end < begin || end >= offset + size) throw new Error('Invalid dylib string');
      dylibs.push(bytes.subarray(begin, end).toString());
    }
    offset += size;
  }
  const flags = bytes.readUInt32LE(24);
  return { file, sha256: crypto.createHash('sha256').update(original).digest('hex'), inspectedArchitecture: 'arm64', flags: `0x${flags.toString(16)}`,
    applicationExtensionSafe: Boolean(flags & 0x02000000), dylibs };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [root, output] = process.argv.slice(2);
  if (!root || !output) throw new Error('Usage: node audit-native-products.mjs APP_OR_ARTIFACTS_ROOT OUTPUT.json');
  const records = [];
  function visit(directory) {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, item.name);
      if (item.isDirectory() && !item.name.endsWith('.dSYM')) visit(file);
      else if (item.isFile() && ['ExpoUI', 'ExpoModulesCore', 'ExpoModulesWorklets', 'ExpoModulesJSI', 'HanlinScriptingWidgets', 'AI_Hanlin'].includes(item.name)) {
        const record = inspectMachO(file);
        record.file = path.relative(root, file).replaceAll('\\', '/');
        records.push(record);
      }
    }
  }
  visit(root);
  const native = records.filter(r => /Expo(UI|ModulesCore|ModulesWorklets)$/.test(r.file));
  const forbiddenDependencies = native.flatMap(record => record.dylibs.filter(lib => /\/(hermesvm|React|ReactNativeDependencies)\.framework\//.test(lib)).map(library => ({ file: record.file, library })));
  const status = native.length > 0 && native.every(r => r.applicationExtensionSafe) && !forbiddenDependencies.length ? 'PASS' : 'FAILED_EXTENSION_CLOSURE';
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify({ status, records, forbiddenDependencies }, null, 2) + '\n');
  console.log(`${status}: ${records.length} binaries; ${forbiddenDependencies.length} forbidden transitive loads. See ${output}`);
  if (status !== 'PASS') process.exitCode = 1;
}
