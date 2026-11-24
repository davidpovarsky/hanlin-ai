#!/usr/bin/env node
/** Generate authoring declarations/schema from the installed original Package 2.0 types. */
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {originalManifestValidationSHA256} from './scriptwidget/manifest-validation.mjs';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const common = 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Common/';
const networkPolicyPath = 'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeFetch.swift';
const digest = value => createHash('sha256').update(value).digest('hex');
const declaration = (source, name) => {
  const match = source.match(new RegExp('(?:struct|enum) ' + name + '\\b[^\\{]*\\{([\\s\\S]*?)\\n\\}'));
  if (!match) throw new Error('Original ScriptWidget declaration not found: ' + name);
  return match[1];
};
const between = (source, start, end) => {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  if (a < 0 || b < 0) throw new Error('Original ScriptWidget validation boundary changed: ' + start);
  return source.slice(a, b);
};

export async function generateScriptWidgetManifest({root = repositoryRoot,
  output = path.join(root, 'Scripts/MiniApps/scriptwidget'), check = false} = {}) {
  const metadata = await readFile(path.join(root, common, 'ScriptMetadata.swift'), 'utf8');
  const packageSource = await readFile(path.join(root, common, 'ScriptWidgetPackage.swift'), 'utf8');
  const networkPolicySource = await readFile(path.join(root, networkPolicyPath), 'utf8');
  // Shapes/enums/version constants regenerate automatically. Semantic changes need
  // an explicit mapping update; publishing a stale validator would mislead authors.
  const semanticSource = [
    declaration(metadata, 'WidgetPackageManifestValidator'),
    declaration(metadata, 'WidgetRuntimeRequirement'),
    declaration(metadata, 'WidgetPackageTimeline'),
    // The manifest delegates host syntax to this installed policy, including the host-generated '*' default.
    between(networkPolicySource, '    static func isValidDomainDeclaration(', '\n    static func host('),
    declaration(packageSource, 'ScriptWidgetPackageName'),
    between(packageSource, '    static func components(_ relative:', '    static func identity('),
    between(packageSource, '    func readManifest()', '    func effectiveManifest()')
  ].join('\n');
  if (digest(semanticSource) !== originalManifestValidationSHA256)
    throw new Error('Original ScriptWidget manifest validation changed. Update the authoring semantic mapping against the installed original source before staging the SDK.');

  const enumNames = ['WidgetPackageFamily', 'WidgetPackagePermission', 'WidgetPackageControlType'];
  const structNames = ['WidgetPackageAuthor', 'WidgetPackageAction', 'WidgetPackageControl',
    'WidgetPackagePushUpdates', 'WidgetPackageTimeline', 'WidgetPackageManifest'];
  const enums = Object.fromEntries(enumNames.map(name => {
    const body = declaration(metadata, name);
    const values = [...body.matchAll(/^    case ([^\n]+)$/gm)].flatMap(match => match[1].split(',').map(value => value.trim()));
    if (!values.length || values.some(value => !/^\w+$/.test(value))) throw new Error('Unmapped original enum: ' + name);
    return [name, values];
  }));
  if (JSON.stringify(enums.WidgetPackageControlType) !== JSON.stringify(['button', 'toggle']))
    throw new Error('Unmapped original ScriptWidget control kind; update its typed action/state semantics.');
  const members = Object.fromEntries(structNames.map(name => {
    const body = declaration(metadata, name);
    const fields = [...body.matchAll(/^    var (\w+): ([\w[\]?]+)(?: = [^\n]+)?$/gm)]
      .map(match => ({name: match[1], type: match[2].replace(/\?$/, ''), optional: match[2].endsWith('?')}));
    if (!fields.length) throw new Error('Unmapped original manifest members: ' + name);
    return [name, fields];
  }));
  const scalar = type => {
    if (type === 'String') return {type: 'string'};
    if (type === 'Int') return {type: 'integer'};
    if (type === 'Bool') return {type: 'boolean'};
    if (type.startsWith('[') && type.endsWith(']')) return {type: 'array', items: scalar(type.slice(1, -1))};
    if (enums[type] || members[type]) return {$ref: '#/$defs/' + type};
    throw new Error('Unmapped original manifest type: ' + type);
  };
  const definitions = Object.fromEntries(Object.entries(enums).map(([name, values]) => [name, {type: 'string', enum: values}]));
  for (const [name, fields] of Object.entries(members)) definitions[name] = {
    type: 'object',
    additionalProperties: false,
    properties: Object.fromEntries(fields.map(field => [field.name,
      field.optional ? {anyOf: [scalar(field.type), {type: 'null'}]} : scalar(field.type)])),
    required: fields.filter(field => !field.optional).map(field => field.name)
  };
  const property = (name, field) => {
    const value = definitions[name].properties[field];
    if (!value) throw new Error('Original manifest field changed: ' + name + '.' + field);
    return value.anyOf?.[0] ?? value;
  };
  const refine = (name, field, constraints, code) => Object.assign(property(name, field), constraints,
    code ? {'x-original-code': code} : {});
  const manifest = 'WidgetPackageManifest', action = 'WidgetPackageAction', control = 'WidgetPackageControl';
  const formatVersion = Number(declaration(metadata, manifest).match(/currentFormatVersion = (\d+)/)?.[1]);
  const runtimeVersion = declaration(packageSource, 'ScriptWidgetBuildContract').match(/runtimeAPIVersion = "([^"]+)"/)?.[1];
  const nativeRuntimeVersion = declaration(packageSource, 'ScriptWidgetBuildContract').match(/nativeRuntimeAPIVersion = "([^"]+)"/)?.[1];
  if (!formatVersion || !runtimeVersion || !nativeRuntimeVersion) throw new Error('Original manifest runtime constants not found.');
  refine(manifest, 'formatVersion', {const: formatVersion}, 'unsupported_format');
  refine(manifest, 'id', {pattern: '^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$'}, 'invalid_id');
  refine(manifest, 'version', {pattern: '^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$'}, 'invalid_version');
  refine(manifest, 'runtimeVersion', {const: runtimeVersion}, 'unsupported_runtime');
  refine(manifest, 'minimumRuntimeVersion', {pattern: '^(0|[1-9][0-9]{0,2})\\.(0|[1-9][0-9]{0,2})$'}, 'invalid_minimum_runtime');
  refine(manifest, 'entry', {pattern: '\\.[jJ][sS][xX]?$'}, 'invalid_entry_type');
  refine(manifest, 'supportedFamilies', {minItems: 1, uniqueItems: true}, 'missing_or_duplicate_families');
  refine(manifest, 'permissions', {uniqueItems: true}, 'duplicate_permissions');
  refine(manifest, 'plugins', {items: {type: 'string', pattern: '^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$'}}, 'invalid_plugin');
  // These constraints belong to the original validator, not a Hanlin authoring quota.
  refine(manifest, 'actions', {maxItems: 16}, 'too_many_actions');
  refine(manifest, 'controls', {maxItems: 8}, 'too_many_controls');
  refine(manifest, 'tags', {maxItems: 20}, 'too_many_tags');
  for (const name of [action, control]) {
    const label = name === action ? 'action' : 'control';
    refine(name, 'id', {pattern: '^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$'}, 'invalid_' + label + '_id');
    refine(name, 'title', {'x-original-max-characters': 40, 'x-original-nonblank': true}, 'invalid_' + label + '_title');
    refine(name, 'systemImage', {pattern: '^[A-Za-z0-9][A-Za-z0-9.-]{0,79}$'}, 'invalid_' + label + '_image');
  }
  refine(action, 'description', {'x-original-max-characters': 160}, 'invalid_action_description');
  const functionPattern = '^[A-Za-z_$][A-Za-z0-9_$]{0,63}$';
  refine(action, 'function', {pattern: functionPattern}, 'invalid_action_function');
  refine(control, 'action', {pattern: functionPattern}, 'invalid_control_action');
  const state = {type: 'string', pattern: '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'};
  definitions[control].allOf = [
    {oneOf: [
      {required: ['actionID'], properties: {actionID: {type: 'string'}, action: {type: 'null'}}},
      {required: ['action'], properties: {action: {type: 'string'}, actionID: {type: 'null'}}}
    ]},
    {if: {properties: {type: {const: 'toggle'}}},
      then: {required: ['stateKey'], properties: {stateKey: state}},
      else: {properties: {stateKey: {type: 'null'}}}}
  ];
  refine('WidgetPackageTimeline', 'dailyTimes', {minItems: 1, maxItems: 4, uniqueItems: true,
    items: {type: 'string', pattern: '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'}}, 'invalid_timeline');
  refine('WidgetPackagePushUpdates', 'channel', {pattern: state.pattern}, 'invalid_push_channel');

  // readManifest rejects unknown JSON keys independently of Codable. Verify that
  // the generated property set still matches that authoritative reader.
  for (const [name, constant] of [[manifest, 'allowedKeys'], [action, 'allowedActionKeys'], [control, 'allowedControlKeys']]) {
    const text = packageSource.match(new RegExp('let ' + constant + ': Set<String> = \\[([\\s\\S]*?)\\]'))?.[1];
    const allowed = [...(text ?? '').matchAll(/"([^"]+)"/g)].map(match => match[1]).sort();
    if (JSON.stringify(allowed) !== JSON.stringify(Object.keys(definitions[name].properties).sort()))
      throw new Error('Original manifest reader/Codable keys differ: ' + name);
  }
  const sourceManifest = JSON.parse(await readFile(path.join(root, 'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json'), 'utf8'));
  const sources = [[common + 'ScriptMetadata.swift', metadata], [common + 'ScriptWidgetPackage.swift', packageSource],
    [networkPolicyPath, networkPolicySource]].map(([local, source]) => {
    const record = sourceManifest.files.find(item => item.local === local);
    const sha256 = digest(source);
    if (!record || record.localSHA256 !== sha256) throw new Error('Original manifest provenance is stale: ' + local);
    return {path: local, upstream: record.upstream, commit: record.commit, sha256};
  });
  const schema = {$schema: 'https://json-schema.org/draft/2020-12/schema',
    title: 'Original ScriptWidget Package 2.0 widget.json', $ref: '#/$defs/' + manifest, $defs: definitions,
    'x-original-contract': {runtimeVersion, nativeRuntimeVersion, validationSHA256: originalManifestValidationSHA256, sources}};
  const swiftToTS = type => type.startsWith('[') ? swiftToTS(type.slice(1, -1)) + '[]'
    : ({String: 'string', Int: 'number', Bool: 'boolean'}[type] ?? type);
  const declarations = [
    '// Generated from the installed original ScriptWidget Codable manifest; do not edit.',
    '// Semantic rules and source identities: widget-manifest.schema.json.', ''
  ];
  for (const [name, values] of Object.entries(enums))
    declarations.push('type ' + name + ' = ' + values.map(value => JSON.stringify(value)).join(' | ') + ';');
  for (const [name, fields] of Object.entries(members)) {
    if (name === control) continue;
    declarations.push('', 'interface ' + name + ' {', ...fields.map(field =>
      '  ' + field.name + (field.optional ? '?' : '') + ': ' +
      (name === manifest && field.name === 'formatVersion' ? formatVersion :
        name === manifest && field.name === 'runtimeVersion' ? JSON.stringify(runtimeVersion) : swiftToTS(field.type)) +
      (field.optional ? ' | null' : '') + ';'), '}');
  }
  declarations.push('', 'type WidgetPackageControl = {',
    ...members[control].filter(field => !['type', 'action', 'actionID', 'stateKey'].includes(field.name))
      .map(field => '  ' + field.name + (field.optional ? '?' : '') + ': ' + swiftToTS(field.type) + (field.optional ? ' | null' : '') + ';'),
    '} & ({actionID: string; action?: null} | {action: string; actionID?: null})',
    '  & ({type: "button"; stateKey?: null} | {type: "toggle"; stateKey: string});', '');
  await mkdir(output, {recursive: true});
  for (const [name, text] of [['widget-manifest.d.ts', declarations.join('\n')],
    ['widget-manifest.schema.json', JSON.stringify(schema, null, 2) + '\n']]) {
    if (check) {
      if (await readFile(path.join(output, name), 'utf8') !== text) throw new Error('Original manifest declarations are stale: ' + name);
    } else await writeFile(path.join(output, name), text);
  }
  return {output, sources, formatVersion, runtimeVersion, nativeRuntimeVersion};
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const value = name => process.argv.slice(2).find(arg => arg.startsWith(name + '='))?.slice(name.length + 1);
  console.log(JSON.stringify(await generateScriptWidgetManifest({root: value('--repository') ?? repositoryRoot,
    output: value('--output') ?? undefined, check: process.argv.includes('--check')})));
}
