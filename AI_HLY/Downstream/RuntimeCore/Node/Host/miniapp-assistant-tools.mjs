// Composer metadata and wrappers for the existing MiniApp action transports.
// The validator reads declarations only. It never imports or executes tool code.
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const safePath = value => nonempty(value) && !value.includes('\\') && !value.includes(':') && !value.includes('\0')
  && value.split('/').every(part => part && part !== '.' && part !== '..');
const diagnostic = (message, file = 'script.json') => ({code: 'MINIAPP_ASSISTANT_TOOL_INVALID', category: 'error', message, file});
const kinds = new Set(['text', 'toggle', 'number', 'choice', 'multiChoice', 'catalog', 'location']);

function flattenOptions(options) {
  return options.flatMap(option => [option, ...(Array.isArray(option.children) ? flattenOptions(option.children) : [])]);
}

function validateValue(field, value) {
  if (value === undefined || value === null) return field.required ? 'A value is required.' : null;
  switch (field.kind) {
    case 'text': return typeof value !== 'string' || field.required && !value.trim() ? 'A text value is required.' : null;
    case 'toggle': return typeof value !== 'boolean' ? 'A boolean value is required.' : null;
    case 'number': return typeof value !== 'number' || !Number.isFinite(value)
      || field.minimum !== undefined && value < field.minimum || field.maximum !== undefined && value > field.maximum
      ? 'A finite number within the declared bounds is required.' : null;
    case 'choice': return !flattenOptions(field.options ?? []).some(option => option.id === value)
      ? 'Choose an available option.' : null;
    case 'multiChoice':
    case 'catalog': {
      const ids = new Set(flattenOptions(field.options ?? []).map(option => option.id));
      return !Array.isArray(value) || field.required && !value.length
        || value.some(item => typeof item !== 'string' || !ids.has(item)) || new Set(value).size !== value.length
        ? 'Choose unique available catalog options.' : null;
    }
    case 'location':
      return !object(value) || !Number.isFinite(value.latitude) || !Number.isFinite(value.longitude)
        || !Number.isFinite(value.radiusMeters) || Math.abs(value.latitude) > 90 || Math.abs(value.longitude) > 180
        || value.radiusMeters <= 0 || field.minimum !== undefined && value.radiusMeters < field.minimum
        || field.maximum !== undefined && value.radiusMeters > field.maximum
        || Object.keys(value).some(key => !['latitude', 'longitude', 'radiusMeters'].includes(key))
        ? 'Choose a valid coordinate and positive radius within the declared bounds.' : null;
    default: return 'Unsupported configuration field kind.';
  }
}

export function validateComposerConfiguration(configuration) {
  const errors = [];
  if (!object(configuration) || ![undefined, 1].includes(configuration.schemaVersion)
    || !Array.isArray(configuration.panels) || !configuration.panels.length)
    return ['Composer configuration requires schemaVersion 1 and at least one panel.'];
  const panelIDs = new Set(), keys = new Set();
  for (const panel of configuration.panels) {
    if (!object(panel) || !nonempty(panel.id) || panelIDs.has(panel.id) || !nonempty(panel.title)) {
      errors.push('Configuration panels need unique nonempty IDs and titles.'); continue;
    }
    panelIDs.add(panel.id);
    if (panel.customViewID !== undefined && !nonempty(panel.customViewID))
      errors.push('customViewID must be a nonempty host view key.');
    if (panel.fields !== undefined && !Array.isArray(panel.fields)) {
      errors.push('Panel fields must be an array.'); continue;
    }
    if (!(panel.fields ?? []).length && !panel.customViewID) errors.push('A panel needs fields or a custom host view.');
    for (const field of panel.fields ?? []) {
      if (!object(field) || !nonempty(field.key) || keys.has(field.key) || !nonempty(field.title) || !kinds.has(field.kind)) {
        errors.push('Fields need unique nonempty keys, titles and a supported kind.'); continue;
      }
      keys.add(field.key);
      if (field.required !== undefined && typeof field.required !== 'boolean') errors.push(field.key + ': required must be boolean.');
      if (field.placeholder !== undefined && typeof field.placeholder !== 'string') errors.push(field.key + ': placeholder must be text.');
      if (field.minimum !== undefined && !Number.isFinite(field.minimum) || field.maximum !== undefined && !Number.isFinite(field.maximum)
        || field.minimum !== undefined && field.maximum !== undefined && field.minimum > field.maximum)
        errors.push(field.key + ': numeric bounds must be finite and ordered.');
      if (field.options !== undefined && !Array.isArray(field.options)) { errors.push(field.key + ': options must be an array.'); continue; }
      const checkOptions = options => {
        for (const option of options) {
          if (!object(option) || !nonempty(option.id) || !nonempty(option.title)
            || option.children !== undefined && !Array.isArray(option.children)) return false;
          if (!checkOptions(option.children ?? [])) return false;
        }
        return true;
      };
      if (!checkOptions(field.options ?? [])) { errors.push(field.key + ': invalid catalog option.'); continue; }
      const options = flattenOptions(field.options ?? []);
      if (new Set(options.map(option => option.id)).size !== options.length)
        errors.push(field.key + ': catalog option IDs must be unique.');
      if (['choice', 'multiChoice', 'catalog'].includes(field.kind) && !options.length)
        errors.push(field.key + ': selection fields need options.');
      if (field.defaultValue !== undefined) {
        const invalid = validateValue(field, field.defaultValue);
        if (invalid) errors.push(field.key + ': ' + invalid);
      }
    }
  }
  return errors;
}

export function validateAssistantToolManifest(script, engine) {
  const diagnostics = [];
  if (script.entrypoints === undefined) return diagnostics;
  if (!Array.isArray(script.entrypoints)) return [diagnostic('entrypoints must be an array.')];
  const ids = new Set(), sources = new Set();
  for (const entry of script.entrypoints) {
    if (entry?.kind !== 'assistantTool') {
      if (entry?.assistantTool !== undefined) diagnostics.push(diagnostic('assistantTool metadata requires kind assistantTool.'));
      continue;
    }
    if (!['expo', 'nativescript'].includes(engine)) {
      diagnostics.push(diagnostic('Prepared assistant tools require Expo or NativeScript.')); continue;
    }
    const expectedMain = engine === 'expo' ? 'bundle.js' : 'bundle.mjs';
    if (!nonempty(entry.id) || ['app', 'widget'].includes(entry.id) || ids.has(entry.id)
      || !safePath(entry.sourcePath) || entry.sourcePath.split('/').length < 2
      || entry.sourcePath.split('/').at(-1) !== expectedMain || entry.sourcePath === script.entry
      || sources.has(entry.sourcePath)) {
      diagnostics.push(diagnostic('An assistantTool needs a unique ID and its own prepared folder/' + expectedMain + '.')); continue;
    }
    ids.add(entry.id); sources.add(entry.sourcePath);
    const metadata = entry.assistantTool;
    if (!object(metadata) || !nonempty(metadata.title) || !nonempty(metadata.summary)
      || !Array.isArray(metadata.actions) || !metadata.actions.length) {
      diagnostics.push(diagnostic('assistantTool requires a title, summary and at least one action.')); continue;
    }
    const actions = new Set();
    for (const action of metadata.actions) {
      if (!object(action) || !nonempty(action.id) || (!/^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*(?![\s\S])/.test(action.id) || action.id.length > 255)
        || actions.has(action.id) || !nonempty(action.title) || !nonempty(action.summary)
        || !object(action.inputSchema) || action.inputSchema.type !== 'object'
        || action.outputSchema !== undefined && !object(action.outputSchema)
        || action.exportedSymbol !== undefined && !nonempty(action.exportedSymbol)) {
        diagnostics.push(diagnostic('Assistant actions need unique valid IDs, titles, summaries, object input schemas and valid optional exports.')); continue;
      }
      actions.add(action.id);
      if (action.embeddedResultID !== undefined && (!nonempty(action.embeddedResultID)
        || !script.entrypoints.some(renderer => renderer?.id === action.embeddedResultID && renderer.kind === 'embeddedResult')))
        diagnostics.push(diagnostic('The action references a missing declared embeddedResult: ' + action.embeddedResultID));
    }
    if (metadata.configuration !== undefined)
      diagnostics.push(...validateComposerConfiguration(metadata.configuration).map(message => diagnostic(message)));
  }
  return diagnostics;
}

export function assistantToolSourceEntries(script, author, engine) {
  const diagnostics = validateAssistantToolManifest(script, engine);
  const declarations = Array.isArray(script.entrypoints) ? script.entrypoints.filter(entry => entry?.kind === 'assistantTool') : [];
  const sources = author.assistantTools ?? {};
  if (!object(sources)) return {entries: [], diagnostics: [...diagnostics, diagnostic('assistantTools must map entrypoint IDs to dedicated source files.', 'hanlin.authoring.json')]};
  const entries = [];
  for (const entry of declarations) {
    const source = sources[entry.id];
    if (!safePath(source) || source === author.entry) {
      diagnostics.push(diagnostic('assistantTools.' + entry.id + ' must identify a dedicated source file, separate from the app entry.', 'hanlin.authoring.json'));
      continue;
    }
    entries.push({...entry, source});
  }
  for (const id of Object.keys(sources)) if (!declarations.some(entry => entry.id === id))
    diagnostics.push(diagnostic('assistantTools references undeclared assistantTool entrypoint: ' + id, 'hanlin.authoring.json'));
  return {entries, diagnostics};
}

/// Each wrapper registers only declared actions; namespace imports never include
/// the foreground app unless the author explicitly imported it in their tool.
export function assistantToolWrapper(entry, importPath, engine) {
  const actions = entry.assistantTool.actions.map(action => ({id: action.id, symbol: action.exportedSymbol ?? action.id}));
  const common = 'import * as tool from ' + JSON.stringify(importPath) + ';\n'
    + 'const actions = ' + JSON.stringify(actions) + ';\n'
    + 'function execute(action, envelope, caller) {\n'
    + '  const handler = tool[action.symbol];\n'
    + '  if (typeof handler !== "function") throw new Error("Missing assistant action export: " + action.symbol);\n'
    + '  if (!envelope || typeof envelope !== "object" || !("arguments" in envelope) || !("configuration" in envelope)) throw new Error("Invalid assistant action envelope.");\n'
    + '  return Promise.resolve(handler(envelope.arguments, {configuration: envelope.configuration, actionID: action.id, caller})).then(value => { assertJSON(value); return value; });\n'
    + '}\n'
    + 'function assertJSON(value, ancestors = new Set()) {\n'
    + '  if (value === null || typeof value === "string" || typeof value === "boolean") return;\n'
    + '  if (typeof value === "number") { if (!Number.isFinite(value)) throw new Error("Non-finite action result."); return; }\n'
    + '  if (typeof value !== "object" || ancestors.has(value)) throw new Error("Action result must be finite, acyclic JSON.");\n'
    + '  if (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null) throw new Error("Action result must use plain JSON objects.");\n'
    + '  ancestors.add(value); for (const item of Object.values(value)) assertJSON(item, ancestors); ancestors.delete(value);\n'
    + '}\n';
  if (engine === 'expo') return common
    + 'import { AppRegistry } from "react-native";\n'
    + 'import { hostServices } from "@hanlin/expo-ui";\n'
    + 'const handlers = Object.fromEntries(actions.map(action => [action.id, request => execute(action, request.parameters, request.caller)]));\n'
    + 'void hostServices.actions.register(handlers).catch(error => { console.error("Hanlin assistant action transport failed", error); });\n'
    + 'AppRegistry.registerComponent("HanlinAssistantTool", () => function HanlinAssistantTool() { return null; });\n';
  return common
    + 'const bridge = HanlinNativeServicesBridge.activeSessionBridge();\n'
    + 'if (!bridge) throw new Error("No active Hanlin NativeScript assistant session.");\n'
    + 'for (const action of actions) bridge.registerRequestHandlerCapabilityHandler(action.id, "assistant-tool", (caller, payload, reply) => {\n'
    + '  Promise.resolve().then(() => execute(action, JSON.parse(payload), caller)).then(value => {\n'
    + '    if (value === undefined) throw new Error("Assistant action must return JSON (use null for no result).");\n'
    + '    const result = JSON.stringify(value);\n'
    + '    if (result === undefined) throw new Error("Assistant action returned no JSON result.");\n'
    + '    reply(result, null);\n'
    + '  }).catch(error => reply(null, error instanceof Error ? error.message : String(error)));\n'
    + '});\n';
}
