const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const ts = require(process.argv[3]);
const root = process.argv[2];
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const generatedPath = 'Packages/HanlinExpoUI/src/generated/modifiers.ts';
const barrelPath = 'Packages/HanlinExpoUI/src/modifiers.ts';
const nativePath = 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/Generated/HanlinGeneratedModifiers.swift';
const extensionPath = 'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoModifierExtension.swift';
const probePath = 'Fixtures/ExpoSwiftUIProbe/GeneratedModifiersProbe.tsx';
const generated = read(generatedPath), barrel = read(barrelPath), native = read(nativePath), probe = read(probePath);
const parsed = ts.createSourceFile(probePath, probe, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
if (parsed.parseDiagnostics.length) throw new Error(ts.formatDiagnostics(parsed.parseDiagnostics, {getCurrentDirectory:()=>root,getCanonicalFileName:x=>x,getNewLine:()=> '\n'}));
const precedence = [...barrel.matchAll(/export \{([^}]+)\} from '@expo\/ui\/swift-ui\/modifiers';/g)].flatMap(match => match[1].split(',').map(name => name.trim()));
const factories = new Map();
const factorySource = ts.createSourceFile(generatedPath, generated, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
for (const statement of factorySource.statements) if (ts.isVariableStatement(statement)) {
  for (const declaration of statement.declarationList.declarations) {
    const init = declaration.initializer;
    if (!init || !ts.isArrowFunction(init) || !ts.isCallExpression(init.body)) continue;
    const [type, properties] = init.body.arguments;
    if (!ts.isStringLiteral(type) || !ts.isObjectLiteralExpression(properties)) throw new Error('Unmapped generated payload');
    factories.set(declaration.name.getText(factorySource), {key: type.text, fields: properties.properties.map(p => p.name.getText(factorySource)), declaration: declaration.getText(factorySource)});
  }
}
const calls = new Map();
function visit(node, context) {
  if (ts.isFunctionDeclaration(node) && node.name) context = node.name.text;
  if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) && node.expression.expression.getText(parsed) === 'm') {
    const name = node.expression.name.text;
    const row = {context, line: parsed.getLineAndCharacterOfPosition(node.getStart(parsed)).line + 1,
      call: node.getText(parsed), arguments: node.arguments.map(argument => argument.getText(parsed))};
    calls.set(name, [...(calls.get(name) ?? []), row]);
  }
  ts.forEachChild(node, child => visit(child, context));
}
visit(parsed, 'module');
const observable = new Set(['accessibility','tracking','position','allowsHitTesting','submitScope','selectionDisabled','tableColumnHeaders','searchCompletion','navigationBarBackButtonHidden','navigationBarHidden','navigationBarTitle']);
const boundaries = {
  previewDisplayName: 'Preview-only metadata; running app UI cannot demonstrate Xcode preview naming.',
  documentLaunchTitle: 'Requires an actual host-owned document launch scene; embedded probe does not create one.',
  documentLaunchSubtitle: 'Requires an actual host-owned document launch scene; embedded probe does not create one.',
  fileDialogBrowserOptions: 'Requires a real SwiftUI file importer/exporter presenter; no such public presenter is created here.',
  fileDialogConfirmationLabel: 'Requires a real SwiftUI file importer/exporter presenter; no such public presenter is created here.',
  fileDialogCustomizationID: 'Requires a real SwiftUI file importer/exporter presenter; no such public presenter is created here.',
  fileDialogImportsUnresolvedAliases: 'Requires a real SwiftUI file importer/exporter presenter and alias input.',
  fileDialogMessage: 'Requires a real SwiftUI file importer/exporter presenter; no such public presenter is created here.',
  fileExporterFilenameLabel: 'Requires a real SwiftUI file exporter presenter; no such public presenter is created here.',
  allowsWindowActivationEvents: 'Requires an inactive native window receiving an activation event.',
  assistiveAccessNavigationIcon: 'Requires the actual Assistive Access system context.',
  onOpenURL: 'Applies the real URL preference to a Link; external URL handling is not invoked by this probe.',
  defersSystemGestures: 'Requires observing OS edge gesture arbitration, not just an app tap.',
  persistentSystemOverlays: 'System overlay presentation effect requires OS observation.',
  statusBar: 'Host/status-bar presentation effect requires OS observation.',
  statusBarHidden: 'Host/status-bar presentation effect requires OS observation.',
  flipsForRightToLeftLayoutDirection: 'Requires right-to-left layout context; locale does not alone establish layout direction.'
};
const rows = [];
for (const [name, factory] of factories) {
  if (precedence.includes(name)) continue;
  const examples = calls.get(name);
  if (!examples?.length) throw new Error('Effective public generated modifier is missing: ' + name);
  const registration = native.match(new RegExp('ViewModifierRegistry\\.register\\("' + name + '"\\) \\{ params, appContext, _ in\\n\\s+try (HanlinGenerated\\w+Modifier)\\(from: params, appContext: appContext\\)'));
  if (!registration) throw new Error('Native registry binding is missing: ' + name);
  const start = native.indexOf('public struct ' + registration[1] + ':');
  const next = native.indexOf('\npublic ', start + 1);
  const record = native.slice(start, next < 0 ? native.length : next);
  const fields = [...record.matchAll(/@Field public var (\w+):/g)].map(match => match[1]);
  if (JSON.stringify([...fields].sort()) !== JSON.stringify([...factory.fields].sort())) throw new Error('Native payload field mismatch: ' + name);
  if (!record.includes('content.' + name + '(')) throw new Error('Native forwarding method mismatch: ' + name);
  const accessibility = name.startsWith('accessibility') || name.startsWith('speech');
  rows.push({name, publicKey: factory.key, parameterFields: fields, examples, nativeRecord: registration[1], nativeRecordSHA256: sha(record),
    nativeForwarding: record.trim(), evidence: observable.has(name) ? 'Observable native assertion authored; execution pending' : 'Typed forwarding/native context application; individual OS effect not asserted',
    boundary: boundaries[name] ?? (accessibility && name !== 'accessibility' ? 'Accessibility service/settings or drag/drop context is required for full effect; appearance and companion actions do not establish it.' : 'A mounted panel is only context evidence; the exact adapter body and declared parameters are recorded separately.')});
}
if (factories.size !== 87 || precedence.length !== 4 || rows.length !== 83) throw new Error('Public export cardinality changed; review the actual surface.');
if (/\bas\s+any\b|@ts-ignore|@ts-expect-error/.test(probe)) throw new Error('Forbidden authoring suppression');
const output = {baseSHA: '6d9a59bfc1bd1830a8d56e694c42b19c6bd7d468', compilerVersion: ts.version,
  scope: 'TSX syntax and actual source identity/field binding only; semantic validation, Metro build and native observations are separate.',
  declaredFactories: factories.size, upstreamPrecedence: precedence, effectivePublicFactories: rows.length, matchedProbeFactories: rows.length,
  nativeAcceptance: 'NOT_RUN', publicCLIValidation: 'PENDING_COMBINED_ENTRYPOINT_LANE',
  sources: Object.fromEntries([generatedPath,barrelPath,nativePath,extensionPath,probePath].map(p => [p, {sha256: sha(read(p)), bytes: Buffer.byteLength(read(p))}])),
  supportingPublicFactories: [...calls.keys()].filter(name => !rows.some(row => row.name === name)).sort(), cases: rows};
process.stdout.write(JSON.stringify(output, null, 2) + '\n');
