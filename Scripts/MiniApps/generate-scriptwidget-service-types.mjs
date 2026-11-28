#!/usr/bin/env node
import {readFile, writeFile, mkdir, readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {argumentTypes, resultTypes} from './scriptwidget/service-shapes.mjs';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const nativeRoot = 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal';
const originalRoot = nativeRoot + '/Original';
const hostPath = 'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/HanlinScriptWidgetRuntime.swift';
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const normalized = type => type.replace(/\s/g, '');
function primitive(swiftType) {
  const type = normalized(swiftType).replace(/[?!]$/, '');
  if (type === 'String') return 'string';
  if (['Bool'].includes(type)) return 'boolean';
  if (['Int', 'Int64', 'Double', 'Float', 'TimeInterval'].includes(type)) return 'number';
  if (type === 'Void') return 'void';
  if (type === '[String]') return 'string[]';
  if (['[String:Any]', '[AnyHashable:Any]'].includes(type)) return 'ScriptWidgetJSONObject';
  throw new Error('Unmapped original Swift type: ' + swiftType);
}
function widen(value) {
  if (value === null) return 'null';
  if (['string', 'number', 'boolean'].includes(typeof value)) return typeof value;
  if (Array.isArray(value)) {
    if (!value.length) throw new Error('Empty catalog array needs an authoritative native result shape.');
    return '(' + [...new Set(value.map(widen))].join(' | ') + ')[]';
  }
  if (typeof value === 'object')
    return '{' + Object.entries(value).map(([key, child]) => JSON.stringify(key) + ': ' + widen(child)).join('; ') + '}';
  throw new Error('Unsupported original catalog value.');
}
async function catalogAt(root) {
  const directory = path.join(root, 'Scripts/MiniApps/scriptwidget/upstream');
  const provenance = JSON.parse(await readFile(path.join(directory, 'provenance.json'), 'utf8'));
  for (const file of provenance.files)
    if (digest(await readFile(path.join(directory, file.local))) !== file.sha256)
      throw new Error('Original ScriptWidget catalog changed without provenance: ' + file.local);
  const {dataAPICatalog} = await import(pathToFileURL(path.join(directory, 'dataAPICatalog.js')).href);
  const {storageAPICatalog} = await import(pathToFileURL(path.join(directory, 'storageAPICatalog.js')).href);
  return {methods: new Map([...dataAPICatalog, ...storageAPICatalog].map(item => [item.id, item])), provenance};
}

export async function generateScriptWidgetServiceTypes({root = repositoryRoot, output = path.join(root, 'Scripts/MiniApps/scriptwidget'), check = false} = {}) {
  const sources = new Map();
  const read = async relative => {
    const bytes = await readFile(path.join(root, relative));
    sources.set(relative, {path: relative, sha256: digest(bytes)});
    return bytes.toString('utf8');
  };
  const runtime = await read(originalRoot + '/Widget/Runtime/ScriptWidgetRuntime.swift');
  const host = await read(hostPath);
  const util = await read(nativeRoot + '/Resources/support.bundle/util.js');
  const protocolFiles = (await readdir(path.join(root, originalRoot, 'Widget/API'))).filter(name => name.endsWith('.swift')).sort();
  const protocols = new Map();
  for (const relative of [...protocolFiles.map(name => originalRoot + '/Widget/API/' + name),
      originalRoot + '/Widget/Component/ScriptWidgetRuntimeElement.swift', originalRoot + '/Plugin/ScriptWidgetDataSources.swift']) {
    const source = await read(relative);
    for (const match of source.matchAll(/@objc\s+protocol\s+(\w+)\s*:\s*JSExport\s*\{([\s\S]*?)\n\}/g))
      protocols.set(match[1], {body: match[2], source: relative});
  }
  // Result nullability and native validation rules reside here in addition to protocols.
  await read(originalRoot + '/Common/ScriptWidgetCloudJSON.swift');
  const {methods: catalog, provenance} = await catalogAt(root);
  const installStart = runtime.indexOf('func installBaseAPIs()');
  const installEnd = runtime.indexOf('private func packagePreflightError', installStart);
  if (installStart < 0 || installEnd < 0) throw new Error('Original native API installation function was not found.');
  const bindings = new Map([...runtime.slice(installStart, installEnd)
    .matchAll(/runtimeContext\["([^"]+)"\]\s*=\s*(\w+)\.self/g)]
    .filter(match => match[1] !== 'Promise').map(match => [match[1], match[2]]));
  const outputLines = [
    '// Generated from installed original Swift JSExport signatures and original editor catalogs.',
    '// Run Scripts/MiniApps/generate-scriptwidget-service-types.mjs; do not edit.',
    '/// <reference path="./components.d.ts" />',
    '/// <reference path="./service-types.d.ts" />', ''
  ];
  const inventory = [];
  const usedArguments = new Set(), usedResults = new Set();
  for (const [global, nativeClass] of [...bindings].sort(([a], [b]) => a.localeCompare(b))) {
    const original = protocols.get(nativeClass + 'Exports');
    if (!original) throw new Error('Missing original JSExport protocol for ' + global + ': ' + nativeClass);
    const methods = [];
    outputLines.push('/** Original native implementation: ' + original.source + ' */', 'declare const ' + global + ': {');
    for (const method of original.body.matchAll(/static\s+func\s+(\w+)\s*\(([^)]*)\)\s*->\s*([^\n]+)/g)) {
      const [, name, rawParameters, swiftReturn] = method;
      const id = global + '.' + name;
      const parameters = rawParameters.trim() ? rawParameters.split(',').map(part => {
        const match = part.trim().match(/^(?:_\s+)?(\w+)\s*:\s*(.+)$/);
        if (!match) throw new Error('Unknown original parameter syntax for ' + id + ': ' + part);
        return {name: match[1], swiftType: match[2].trim()};
      }) : [];
      const refinements = argumentTypes[id];
      if (refinements && refinements.length !== parameters.length) throw new Error('Native argument arity changed: ' + id);
      if (refinements) usedArguments.add(id);
      const signatureParameters = parameters.map((parameter, index) => {
        const refinement = refinements?.[index];
        const optional = refinement ? refinement.endsWith('?') : parameter.swiftType.endsWith('?');
        const type = refinement ? refinement.replace(/\?$/, '') : primitive(parameter.swiftType);
        return {...parameter, optional, type};
      });
      const metadata = catalog.get(id);
      const async = swiftReturn.trim() === 'ScriptWidgetRuntimePromise';
      if (metadata?.asynchronous !== undefined && metadata.asynchronous !== async) throw new Error('Original catalog/native async mismatch: ' + id);
      if (metadata?.arguments && metadata.arguments.length !== parameters.length) throw new Error('Original catalog/native arity mismatch: ' + id);
      let valueType = resultTypes[id];
      if (valueType) usedResults.add(id);
      else if (metadata && 'value' in metadata) valueType = widen(metadata.value);
      else if (async) throw new Error('Missing original native result schema: ' + id);
      else valueType = primitive(swiftReturn);
      const returnType = async ? 'ScriptWidgetNativePromise<' + valueType + '>' : valueType;
      const parametersText = signatureParameters.map(parameter => parameter.name + (parameter.optional ? '?' : '') + ': ' + parameter.type).join(', ');
      const details = metadata?.documentation ?? (metadata ? 'Original catalog: ' + id + (metadata.minimumRuntimeVersion ? '; runtime ' + metadata.minimumRuntimeVersion : '') + '.' : '');
      if (details) outputLines.push('  /** ' + details.replaceAll('*/', '* /') + ' */');
      outputLines.push('  ' + name + '(' + parametersText + '): ' + returnType + ';');
      methods.push({name, parameters: signatureParameters, returnType, nativeSignature: method[0].trim(), asynchronous: async,
        resultAuthority: resultTypes[id] ? 'native semantic refinement' : metadata && 'value' in metadata ? 'original editor catalog, primitive values widened' : 'original native Swift type'});
    }
    if (!methods.length) throw new Error('Original native object has no parsed callable methods: ' + global);
    if (global === '$storage') {
      if (!host.includes('get: __hanlinGetWidgetValue, set: __hanlinSetWidgetValue')) throw new Error('Hanlin storage additions changed.');
      outputLines.push('  /** Hanlin exact-value additions; missing values are null. */',
        '  get(key: string): ScriptWidgetJSON;', '  set(key: string, value: ScriptWidgetJSON): boolean;');
    }
    outputLines.push('};', '');
    inventory.push({global, nativeClass, source: original.source, methods});
  }
  for (const name of Object.keys(argumentTypes)) if (!usedArguments.has(name)) throw new Error('Native argument refinement no longer matches an installed API: ' + name);
  for (const name of Object.keys(resultTypes)) if (!usedResults.has(name)) throw new Error('Native result refinement no longer matches an installed API: ' + name);

  const hostGlobalsInstalled = [];
  const assertBlock = (name, signature) => {
    const escaped = name.replaceAll('$', '\\$');
    const binding = host.match(new RegExp('context\\.setObject\\((\\w+),\\s*forKeyedSubscript:\\s*"' + escaped + '"'));
    if (!binding) return false;
    if (!host.replace(/\s/g, '').includes('let' + binding[1] + ':@convention(block)' + signature))
      throw new Error('Native host signature changed: ' + name);
    hostGlobalsInstalled.push(name);
    return true;
  };
  if (assertBlock('$component', '(String,JSValue)->Void')) outputLines.push(
    '/** Original registration diagnostic; function JSX components resolve their own builder. */',
    'declare function $component<P>(name: string, builder: (props: P) => JSX.Element): void;', '');
  if (assertBlock('$dynamic_island', '(NSDictionary)->Void')) outputLines.push(
    '/** Captures the actual original native element for each supplied Dynamic Island region. */',
    'declare function $dynamic_island(regions: ScriptWidgetDynamicIslandRegions): void;', '');
  if (host.includes('globalThis.$presentation = {')) {
    if (!host.includes('expandSheet: __hanlinPresentationExpand') || !host.includes('finish: text => __hanlinPresentationFinish'))
      throw new Error('Native presentation command binding changed.');
    hostGlobalsInstalled.push('$presentation');
    for (const [binding, name, signature] of [
      ['keyboardEdit', '__hanlinKeyboardEdit', '(NSDictionary)->Void'],
      ['notificationAction', '__hanlinNotificationAction', '(String)->Void'],
    ]) {
      if (!host.replace(/\s/g, '').includes('let' + binding + ':@convention(block)' + signature) ||
          !host.includes('context.setObject(' + binding + ', forKeyedSubscript: "' + name + '"'))
        throw new Error('Native system presentation binding changed: ' + name);
    }
    for (const operation of ['insertText', 'deleteBackward', 'adjustTextPosition', 'nextInputMode'])
      if (!host.includes('operation: "' + operation + '"'))
        throw new Error('Native keyboard command binding changed: ' + operation);
    for (const action of ['openApp', 'dismiss'])
      if (!host.includes('__hanlinNotificationAction("' + action + '")'))
        throw new Error('Native notification command binding changed: ' + action);
    outputLines.push(
      'declare const $presentation: {',
      '  expandSheet(): void;',
      '  finish(replacementText?: string | null): void;',
      '  keyboard: {insertText(text: string): void; deleteBackward(): void; adjustTextPosition(offset: number): void; nextInputMode(): void};',
      '  notification: {openApp(): void; dismiss(): void};',
      '};', '');
  }
  if (host.includes('actionParameters: HanlinValue') && host.includes('"parameters": actionParameters.toAny()'))
    outputLines.push('declare namespace JSX { interface GlobalProperties { actionParameters?: ScriptWidgetJSON; } }', '');

  const hostGlobals = await read('Scripts/MiniApps/scriptwidget/host-globals.d.ts');
  for (const name of ['$import', '$render', '$error', '$getenv', '$widget'])
    if (!host.includes('forKeyedSubscript: "' + name + '"')) throw new Error('Declared Hanlin global is not installed: ' + name);
  for (const name of ['$fetch', 'fetch'])
    if (!runtime.includes('runtimeContext["' + name + '"]')) throw new Error('Original fetch alias is not installed: ' + name);
  for (const name of ['$gradient', '$animation', '$json', '$type_of_object'])
    if (!util.includes('function ' + name + '(')) throw new Error('Declared original utility does not exist: ' + name);
  if (!util.includes('const $xml = Object.freeze(')) throw new Error('Original XML utility was not found.');
  const globals = [...new Set([...hostGlobalsInstalled, ...inventory.map(item => item.global),
    ...[...hostGlobals.matchAll(/declare\s+(?:function|const|class)\s+([$\w]+)/g)].map(match => match[1])])].sort();
  const manifest = {schemaVersion: 1, globals, nativeObjectCount: inventory.length,
    nativeMethodCount: inventory.reduce((sum, item) => sum + item.methods.length, 0), bindings: inventory,
    sources: [...sources.values()].sort((a, b) => a.path.localeCompare(b.path)),
    originalCatalog: provenance, nativeAwaitable: 'then(resolve,reject) returns void; await works; no native catch/finally/chaining',
    unavailableOriginalRendererGlobals: ['$component', '$dynamic_island'].filter(name => !hostGlobalsInstalled.includes(name)),
    note: 'Only actual installed native objects and evaluated utility/host additions are declared. Catalogs describe result shapes, not mock execution.'};
  await mkdir(output, {recursive: true});
  for (const [name, content] of [['original-api.d.ts', outputLines.join('\n')],
      ['native-api.json', JSON.stringify(manifest, null, 2) + '\n']]) {
    const file = path.join(output, name);
    if (check) { if (await readFile(file, 'utf8') !== content) throw new Error('ScriptWidget native declarations are stale: ' + name); }
    else await writeFile(file, content);
  }
  return {globals: globals.length, nativeObjects: inventory.length, nativeMethods: manifest.nativeMethodCount, output};
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const value = name => process.argv.slice(2).find(arg => arg.startsWith(name + '='))?.slice(name.length + 1);
  console.log(JSON.stringify(await generateScriptWidgetServiceTypes({root: value('--repository') ?? repositoryRoot,
    output: value('--output') ?? undefined, check: process.argv.includes('--check')})));
}
