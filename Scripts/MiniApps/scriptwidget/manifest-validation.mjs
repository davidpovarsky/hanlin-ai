// Authoring translation of the installed original ScriptWidget Package 2.0
// validator. Generation verifies the source digest before publishing this mapping.
export const originalManifestValidationSHA256 = '2ba51a3d9c899d0e0145a88030f358944a374622782d10a0d3e116e963a6c16d';
const byteCount = value => new TextEncoder().encode(value).length;
const graphemes = new Intl.Segmenter(undefined, {granularity: 'grapheme'});
const characterCount = value => [...graphemes.segment(value)].length;
const components = value => {
  if (typeof value !== 'string' || /^[A-Za-z]:/.test(value)) return null;
  const parts = value.split('/');
  return parts.length >= 1 && parts.length <= 16 && parts.every(part =>
    part && part !== '.' && part !== '..' && !part.includes('\\') && byteCount(part) <= 255 &&
    !/[\p{Cc}\p{Cf}]/u.test(part.replace(/[\u200C\u200D]/g, ''))) ? parts : null;
};
// ScriptWidgetNetworkPolicy.isValidDomainDeclaration; its native body is part of the semantic fingerprint.
const isValidDomainDeclaration = value => {
  if (value === '*') return true;
  const normalized = value.toLowerCase();
  return value === normalized && !normalized.includes('://') && !normalized.includes('/') && !normalized.includes(':') &&
    !normalized.startsWith('.') && !normalized.endsWith('.') && /^[a-z0-9*.-]+$/.test(normalized) &&
    (!normalized.includes('*') || normalized.startsWith('*.'));
};
const sameIDs = values => new Set(values.map(value => value.toLowerCase())).size === values.length;
const supports = (minimum, current) => {
  if (!/^(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})$/.test(minimum)) return false;
  const requested = minimum.split('.').map(Number), available = current.split('.').map(Number);
  return requested[0] === available[0] && requested[1] <= available[1];
};
const pointer = (base, name) => base + '/' + String(name).replace(/~/g, '~0').replace(/\//g, '~1');

export async function validateScriptWidgetManifest({text, entry, compiler: ts, schema, exists}) {
  const diagnostics = [];
  const source = ts.parseJsonText('widget.json', text);
  const nodes = new Map([['', source]]);
  const visit = (node, location = '') => {
    nodes.set(location, node);
    if (ts.isObjectLiteralExpression(node)) for (const property of node.properties) {
      if (ts.isPropertyAssignment(property)) visit(property.initializer, pointer(location, property.name.text));
    }
    else if (ts.isArrayLiteralExpression(node)) node.elements.forEach((element, index) => visit(element, pointer(location, index)));
  };
  const expression = source.statements[0]?.expression;
  if (expression) visit(expression);
  const issue = (code, message, location = '', category = 'error') => {
    let lookup = location;
    while (!nodes.has(lookup) && lookup) lookup = lookup.slice(0, lookup.lastIndexOf('/'));
    const node = nodes.get(lookup);
    const position = node?.getStart(source) ?? 0;
    const start = source.getLineAndCharacterOfPosition(position);
    const end = source.getLineAndCharacterOfPosition(node?.getEnd() ?? position);
    diagnostics.push({code: 'SCRIPTWIDGET_' + code.toUpperCase(), originalCode: code, category, message,
      file: 'widget.json', jsonPath: location || '/', line: start.line + 1, column: start.character + 1,
      endLine: end.line + 1, endColumn: end.character + 1,
      remediation: 'Edit the original widget.json contract and validate again; its schema is scriptwidget/widget-manifest.schema.json in this host SDK.'});
  };
  let manifest;
  try { manifest = JSON.parse(text); }
  catch (error) {
    issue('invalid_manifest_json', 'widget.json must be valid JSON: ' + error.message);
    const offset = source.parseDiagnostics?.[0]?.start ?? Number(error.message.match(/position (\d+)/)?.[1]);
    if (Number.isInteger(offset)) {
      const point = source.getLineAndCharacterOfPosition(offset);
      Object.assign(diagnostics[0], {line: point.line + 1, column: point.character + 1,
        endLine: point.line + 1, endColumn: point.character + 2});
    }
    return {diagnostics};
  }
  const validateShape = (value, rule, location) => {
    if (rule.$ref) rule = schema.$defs[rule.$ref.slice('#/$defs/'.length)];
    if (rule.anyOf) {
      if (value === null && rule.anyOf.some(item => item.type === 'null')) return;
      rule = rule.anyOf.find(item => item.type !== 'null');
      if (rule.$ref) rule = schema.$defs[rule.$ref.slice('#/$defs/'.length)];
    }
    const code = rule['x-original-code'] ?? 'invalid_manifest_field';
    const fail = message => issue(code, (location || 'widget.json') + ': ' + message, location);
    const actual = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
    if ((rule.type === 'integer' && !Number.isInteger(value)) ||
      (rule.type !== 'integer' && rule.type && actual !== rule.type)) {
      fail('expected ' + rule.type + ', received ' + actual + '.'); return;
    }
    if (rule.const !== undefined && value !== rule.const) fail('expected ' + JSON.stringify(rule.const) + '.');
    if (rule.enum && !rule.enum.includes(value)) fail('expected one of ' + rule.enum.join(', ') + '.');
    if (typeof value === 'string') {
      if (rule.pattern && !new RegExp(rule.pattern).test(value)) fail('does not match the original format ' + rule.pattern + '.');
      if (rule['x-original-max-characters'] && characterCount(value) > rule['x-original-max-characters'])
        fail('must contain at most ' + rule['x-original-max-characters'] + ' characters.');
      if (rule['x-original-nonblank'] && !value.trim()) fail('must not be blank.');
    }
    if (Array.isArray(value)) {
      if (rule.minItems !== undefined && value.length < rule.minItems) fail('requires at least ' + rule.minItems + ' item(s).');
      if (rule.maxItems !== undefined && value.length > rule.maxItems) fail('the original runtime supports at most ' + rule.maxItems + ' items.');
      if (rule.uniqueItems && new Set(value.map(item => JSON.stringify(item))).size !== value.length) fail('must not contain duplicates.');
      if (rule.items) value.forEach((item, index) => validateShape(item, rule.items, pointer(location, index)));
    }
    if (actual === 'object') {
      for (const name of rule.required ?? []) if (!(name in value)) issue('missing_manifest_field', 'Missing required field ' + name + '.', pointer(location, name));
      for (const [name, child] of Object.entries(value)) {
        if (rule.properties?.[name]) validateShape(child, rule.properties[name], pointer(location, name));
        else if (rule.additionalProperties === false) issue('unknown_manifest_field',
          'The original manifest does not define ' + name + '.', pointer(location, name));
      }
    }
  };
  validateShape(manifest, schema, '');
  if (diagnostics.some(item => item.category === 'error')) return {diagnostics};

  const m = manifest, permissions = new Set(m.permissions);
  const nativeRuntime = schema['x-original-contract'].nativeRuntimeVersion;
  if (!m.name.trim() || characterCount(m.name) > 80 || byteCount(m.name) > 240 ||
      m.name.startsWith('.') || m.name.normalize('NFC').toLowerCase() === '__build' || components(m.name)?.length !== 1)
    issue('invalid_name', 'name must be a nonreserved package name, at most 80 characters/240 UTF-8 bytes, without path separators or control characters.', '/name');
  if (m.minimumRuntimeVersion != null && !supports(m.minimumRuntimeVersion, nativeRuntime))
    issue('unsupported_minimum_runtime', 'This package requires a newer or incompatible ScriptWidget Runtime.', '/minimumRuntimeVersion');
  const systemPermissions = ['notifications', 'calendarWrite', 'maps', 'weather', 'alarms', 'documents', 'contacts', 'home'];
  if (systemPermissions.some(name => permissions.has(name)) && !supports('1.6', m.minimumRuntimeVersion ?? '0.0'))
    issue('system_runtime', 'System service capabilities require minimumRuntimeVersion 1.6 or later.', '/minimumRuntimeVersion');
  if (permissions.has('calendarWrite') && !permissions.has('calendar'))
    issue('calendar_write_permission', 'calendarWrite also requires calendar.', '/permissions');
  if (permissions.has('icloud') && !supports('1.5', m.minimumRuntimeVersion ?? '0.0'))
    issue('icloud_runtime', 'iCloud JSON requires minimumRuntimeVersion 1.5 or later.', '/minimumRuntimeVersion');
  if (!components(m.entry)) issue('invalid_entry', 'entry must be a package-relative POSIX path within the original package.', '/entry');
  else if (exists && !await exists(m.entry)) issue('missing_entry', 'Entry file ' + m.entry + ' does not exist.', '/entry');
  if (m.entry !== entry) issue('entry_mismatch', 'widget.json entry ' + m.entry + ' does not match the declared ScriptWidget source ' + entry + '.', '/entry');
  if (m.preview != null && !components(m.preview)) issue('invalid_preview', 'preview escapes the package directory.', '/preview');
  if (m.timeline) {
    if (m.timeline.dailyTimes.join(',') !== [...m.timeline.dailyTimes].sort().join(','))
      issue('invalid_timeline', 'timeline.dailyTimes must be sorted.', '/timeline/dailyTimes');
    if (m.timeline.timeZone != null) {
      let valid = byteCount(m.timeline.timeZone) <= 128;
      try { new Intl.DateTimeFormat('en', {timeZone: m.timeline.timeZone}); } catch { valid = false; }
      if (!valid) issue('invalid_timeline', 'timeline.timeZone must identify a valid time zone.', '/timeline/timeZone');
    }
  }
  if (m.networkDomains.length && !permissions.has('network'))
    issue('undeclared_network', 'networkDomains requires the network permission.', '/networkDomains');
  if (permissions.has('network') && !m.networkDomains.length)
    issue('missing_network_domains', 'Network access must declare at least one host.', '/networkDomains');
  for (const [index, domain] of m.networkDomains.entries()) {
    if (!isValidDomainDeclaration(domain))
      issue('invalid_network_domain', 'Invalid network host declaration: ' + domain + '.', '/networkDomains/' + index);
  }
  if (m.plugins) {
    if (!sameIDs(m.plugins)) issue('duplicate_plugins', 'plugins must contain unique identifiers.', '/plugins');
    if (m.plugins.length && !permissions.has('network')) issue('plugin_network', 'Data source plugins require the network permission.', '/plugins');
  }
  const actions = m.actions ?? [], controls = m.controls ?? [];
  if (!sameIDs(actions.map(action => action.id))) issue('duplicate_actions', 'Action identifiers must be unique.', '/actions');
  if (!sameIDs(controls.map(control => control.id))) issue('duplicate_controls', 'Control identifiers must be unique.', '/controls');
  for (const [index, control] of controls.entries()) {
    const base = '/controls/' + index;
    if (control.action != null && control.actionID != null)
      issue('ambiguous_control_action', 'Controls must declare either action or actionID, not both.', base);
    else if (control.actionID != null && !actions.some(action => action.id.toLowerCase() === control.actionID.toLowerCase()))
      issue('missing_control_action', 'Control ' + control.id + ' references unknown action ' + control.actionID + '.', base + '/actionID');
    else if (control.action == null && control.actionID == null)
      issue('missing_control_action', 'Controls must declare actionID or the legacy action field.', base);
    if (control.type === 'toggle') {
      if (control.stateKey == null || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(control.stateKey))
        issue('invalid_control_state', 'Toggle controls require a valid stateKey.', base + '/stateKey');
      else if (!permissions.has('storage')) issue('control_storage', 'Toggle controls require the storage permission.', '/permissions');
    } else if (control.stateKey != null) issue('button_control_state', 'Button controls must not declare stateKey.', base + '/stateKey');
  }
  if (m.pushUpdates) {
    if (!permissions.has('network')) issue('push_network', 'pushUpdates requires the network permission.', '/pushUpdates');
    let valid = false;
    try {
      const url = new URL(m.pushUpdates.registrationURL), host = url.hostname.toLowerCase();
      const parts = host.split('.');
      const local = host === 'localhost' || host === '::1' || host === '[::1]' || host.endsWith('.local') ||
        ['127.', '10.', '192.168.'].some(prefix => host.startsWith(prefix)) ||
        (parts.length === 4 && parts[0] === '172' && Number(parts[1]) >= 16 && Number(parts[1]) <= 31);
      valid = url.protocol === 'https:' && !!host && !local && m.networkDomains.some(domain =>
        domain.startsWith('*.') ? host !== domain.slice(2) && host.endsWith('.' + domain.slice(2)) : host === domain);
    } catch {}
    if (!valid) issue('invalid_push_url', 'pushUpdates.registrationURL must be a public HTTPS URL on a declared network domain.', '/pushUpdates/registrationURL');
  }
  if (m.tags && !sameIDs(m.tags)) issue('duplicate_tags', 'Duplicate tags should be removed.', '/tags', 'warning');
  if (m.author?.url != null && !/^https:/i.test(m.author.url))
    issue('invalid_author_url', 'author.url must use HTTPS.', '/author/url');
  return {manifest, diagnostics};
}
