// Scoped declaration corrections authenticated against original declaration and implementation bytes.
// No runtime sources, compiler gates, or public native methods are replaced.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../..');
const rn = path.join(import.meta.dirname, 'node_modules/react-native');
const nativeAPI = path.join(import.meta.dirname, 'node_modules/@nativescript/react-native');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const rnVersion = JSON.parse(await readFile(path.join(rn, 'package.json'), 'utf8')).version;
const nativeAPIVersion = JSON.parse(await readFile(path.join(nativeAPI, 'package.json'), 'utf8')).version;
// Exact declaration AND implementation hashes remain the authority when upstream
// advances a release without changing the audited files.
const patches = [
  {file: 'Libraries/Animated/nodes/AnimatedProps.d.ts',
    originalSHA256: '0dde4c5442c332f01cb8f830ead7965b64996dca6b9bcc3a280806f48b8d3f21',
    source: 'Libraries/Animated/nodes/AnimatedProps.js',
    sourceSHA256: 'd860011a3cde601ef237ffb40eef05c68cb3b15bc3c25e2fead8db751f1167de',
    replacements: [['style?: AnimatedStyleAllowlist | undefined;', 'style?: AnimatedStyleAllowlist | null | undefined;'],
      ['[key: string]: true | AnimatedStyleAllowlist;', '[key: string]: true | AnimatedStyleAllowlist | null | undefined;']],
    reason: 'Flow explicitly permits an optional nullable style. The TS index signature must admit that named property.'},
  {file: 'Libraries/Lists/VirtualizedList.d.ts',
    originalSHA256: '90335722e3f37fbca6dc2dc699efac7ebf2f8866a9cfddce21a3dd6bb9e9a92a',
    source: 'Libraries/Lists/VirtualizedList.js',
    sourceSHA256: '94d0e1f682f3422648451be3070a68a6e69eeddce7bed4c43cc3124e89565b5e',
    replacements: [['React.ComponentRef<VirtualizedListType>', 'InstanceType<VirtualizedListType>']],
    reason: 'The exported value is the actual class constructor. Infer its instance without the unrelated React static lifecycle generic constraint.'},
  {file: 'src/private/webapis/dom/nodes/ReadOnlyNode.d.ts',
    originalSHA256: 'b0599260380ad18e7b783d712990bdf0cfba1346719bb8273fbaf06ed5a61bae',
    source: 'src/private/webapis/dom/nodes/ReactNativeDocument.js',
    sourceSHA256: 'dcafb922a27f7dac28f3d6079af34c90dfb047ea42f519d6a45fc16a671a4394',
    replacements: [['get textContent(): string;', 'get textContent(): string | null;']],
    reason: 'The abstract base throws; the concrete Document getter really returns null. Preserve that actual subclass behavior in the base return type.'},
  {package: '@nativescript/react-native', file: 'Runtime.d.ts',
    originalSHA256: 'f28f211c956653fe859b9fc30a3765afb8902aa3d505248e28e3991fe32d1ca1',
    source: 'native-api/ffi/objc/shared/bridge/Install.mm',
    sourceSHA256: 'f8c156b7ea87e6eed0e7aa9a5af1816bacb40332a68038ac521e191e15510e83',
    replacements: [['declare class timezone {\n  constructor(init?: timezone);', 'interface timezone {'],
      ['declare class dyld_shared_cache_ranges {\n  constructor(init?: dyld_shared_cache_ranges);', 'interface dyld_shared_cache_ranges {']],
    reason: 'Actual Install.mm installs constants first and does not overwrite conflicting globals with struct constructors. Keep struct field types and actual constants; do not advertise new timezone()/new dyld_shared_cache_ranges().'},
  {package: '@nativescript/react-native', file: 'UIKit.d.ts',
    originalSHA256: '6ad19868e345469b507442f2666ca55ba69a5a98915e09459739e43246469638',
    source: 'native-api/ffi/objc/shared/bridge/host_objects/Object.mm',
    sourceSHA256: 'fbc95bc22a5115453f944a408183ca2a64e3338954ba8ca4b2b045146afe7348',
    replacements: [['  description(): string;\n\n  static readonly supportsSecureCoding: boolean;',
      '  readonly description: string;\n\n  static readonly supportsSecureCoding: boolean;']],
    reason: 'Apple exposes the ObjC description selector, but the actual JS host object explicitly resolves description to a string before method lookup. Match that JS boundary and inherited NSObject property.'},
];
const provenance = [];
for (const patch of patches) {
  const base = patch.package ? nativeAPI : rn;
  const file = path.join(base, patch.package ? 'types/ios' : 'types_generated', patch.file);
  const sourceSHA256 = sha(await readFile(path.join(base, patch.source)));
  if (patch.sourceSHA256 && sourceSHA256 !== patch.sourceSHA256) throw new Error(`Original implementation drift: ${patch.source}`);
  if (patch.package) {
    const hostSource = path.join(root, 'Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/nativescript', patch.source);
    if (sha(await readFile(hostSource)) !== patch.sourceSHA256) throw new Error(`Host/native API declaration dependency drift: ${patch.source}`);
  }
  const current = await readFile(file, 'utf8');
  // Reverse only these exact, reviewed substitutions to authenticate the pinned
  // original even after a prior application. No broad text/regex repair.
  let original = current;
  if (sha(current) !== patch.originalSHA256) {
    for (const [before, after] of patch.replacements) {
      if (original.split(after).length !== 2) throw new Error(`Non-unique reverse correction: ${patch.file}`);
      original = original.replace(after, before);
    }
  }
  if (sha(original) !== patch.originalSHA256) throw new Error(`Upstream declaration drift: ${patch.file}`);
  let corrected = original;
  for (const [before, after] of patch.replacements) {
    if (corrected.split(before).length !== 2) throw new Error(`Non-unique declaration correction: ${patch.file}`);
    corrected = corrected.replace(before, after);
  }
  if (process.argv.includes('--check') && current !== corrected) throw new Error(`Declaration correction not applied: ${patch.file}`);
  if (current !== corrected) await writeFile(file, corrected);
  provenance.push({package: patch.package ?? 'react-native', file: patch.file, originalSHA256: patch.originalSHA256, correctedSHA256: sha(corrected),
    source: patch.source, sourceSHA256, reason: patch.reason});
}
const output = path.join(root, 'build/acceptance/expo-type-declarations');
await mkdir(output, {recursive: true});
await writeFile(path.join(output, 'corrections.json'), JSON.stringify({schemaVersion: 1, reactNative: rnVersion, nativeAPI: nativeAPIVersion,
  boundary: 'Declaration-only corrections; strict checking and native/Metro execution are separate mandatory gates.', patches: provenance}, null, 2) + '\n');
console.log('PASS: five exact pinned declaration-file corrections; no skipLibCheck or runtime changes.');
