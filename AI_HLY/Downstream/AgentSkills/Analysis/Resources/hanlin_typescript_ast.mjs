// Trusted passive helper. Runtime05 supplies its existing original TypeScript compiler.
// No import of analyzed code, fs/ts.sys access, module resolution, emit or execution.
import {createHash} from 'node:crypto';
import {isUtf8} from 'node:buffer';

export function analyzeTypeScriptSource(ts, {file, utf8, maximumBytes = 262144,
  maximumNodes = 20000, maximumFindings = 256, maximumDepth = 128,
  parseSeconds = 0.1}, cancelled = () => false) {
  const bound = (value, fallback, low, high) => Number.isFinite(value)
    ? Math.min(Math.max(Math.trunc(value), low), high) : fallback;
  maximumBytes = bound(maximumBytes, 262144, 1, 1048576);
  maximumNodes = bound(maximumNodes, 20000, 1, 100000);
  maximumFindings = bound(maximumFindings, 256, 2, 1024);
  maximumDepth = bound(maximumDepth, 128, 1, 512);
  parseSeconds = Number.isFinite(parseSeconds) ? Math.min(Math.max(parseSeconds, 0.001), 1) : 0.1;
  const report = {file, sourceSHA256: null, completion: 'complete',
    provenance: {scanner: `typescript.CompilerAPI/${ts?.version ?? 'unavailable'}`, engineVersion: process.versions.node},
    findings: [], visitedNodes: 0, inputBytes: utf8?.byteLength ?? 0,
    limitations: ['syntaxOnlyNotReadinessOrPermission', 'noPackageResolutionOrFilesystem',
      'noReferencedFileReadsOrExecution', 'aliasesAndBindingsNotResolved',
      'conditionalFactsDoNotProveReachability', 'parseIsSynchronousInputBoundedNotHardTimeOrRSSCap']};
  let sourceFile;
  let offsets;
  const location = node => {
    if (!node || !sourceFile || !offsets) return {file, line: 1, utf8Column: 1, byteOffset: 0, byteLength: 0};
    const start = node.getStart(sourceFile), end = node.getEnd();
    const {line} = sourceFile.getLineAndCharacterOfPosition(start);
    const lineStart = sourceFile.getPositionOfLineAndCharacter(line, 0);
    return {file, line: line + 1, utf8Column: offsets[start] - offsets[lineStart] + 1,
      byteOffset: offsets[start], byteLength: offsets[end] - offsets[start]};
  };
  const emit = (kind, value, node, reason, conditional = false) => {
    if (report.findings.length >= maximumFindings) { report.completion = 'partial'; return; }
    if (kind === 'unknown') report.completion = 'partial';
    report.findings.push({kind, value, confidence: kind === 'unknown' ? 'unknown'
      : conditional ? 'conditionalSyntax' : 'literalSyntax', source: location(node), reason});
  };
  const unavailable = reason => {
    report.findings = [];
    emit('unknown', null, null, reason);
    report.completion = 'unknown';
    return report;
  };
  if (typeof file !== 'string' || !file || Buffer.byteLength(file) > 1024 || file.includes('\0'))
    return unavailable('invalidSourceIdentity');
  if (!(utf8 instanceof Uint8Array)) return unavailable('UTF8BytesRequired');
  if (utf8.byteLength > maximumBytes) return unavailable('sourceBudget');
  // Embedded Node intentionally lacks ICU. Fatal TextDecoder is not used.
  const bytes = Buffer.from(utf8);
  if (!isUtf8(bytes)) return unavailable('invalidUTF8');
  if (cancelled()) return unavailable('cancelled');
  report.sourceSHA256 = createHash('sha256').update(bytes).digest('hex');
  if (ts?.version !== '6.0.3') return unavailable('unsupportedCompilerVersion');
  const source = bytes.toString('utf8');
  const extension = file.split('.').at(-1)?.toLowerCase();
  const jsonManifest = file.split(/[\\/]/).at(-1) === 'package.json';
  if (jsonManifest) report.provenance.scanner = `typescript.JSONCompilerAPI/${ts.version}`;
  const scriptKind = extension === 'tsx' ? ts.ScriptKind.TSX : extension === 'jsx' ? ts.ScriptKind.JSX
    : ['js', 'mjs', 'cjs'].includes(extension) ? ts.ScriptKind.JS
    : ['ts', 'mts', 'cts'].includes(extension) ? ts.ScriptKind.TS : jsonManifest ? ts.ScriptKind.JSON : undefined;
  if (scriptKind === undefined) return unavailable('unsupportedSourceKind');
  const deadline = performance.now() + parseSeconds * 1000;
  try {
    if (jsonManifest) JSON.parse(source); // Strict JSON syntax; parsed object is never a last-key-wins authority.
    sourceFile = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true, scriptKind);
    // Public syntactic-diagnostic API with a memory-only host. No ts.sys/default
    // CompilerHost, libs, project/config discovery, plugins or import resolution.
    const host = {
      getSourceFile: name => name === file ? sourceFile : undefined,
      getDefaultLibFileName: () => '', writeFile: () => {}, getCurrentDirectory: () => '',
      getDirectories: () => [], directoryExists: () => false,
      fileExists: name => name === file, readFile: name => name === file ? source : undefined,
      getCanonicalFileName: name => name, useCaseSensitiveFileNames: () => true, getNewLine: () => '\n',
    };
    const program = ts.createProgram([file], {noLib: true, noResolve: true, noEmit: true,
      allowJs: true, allowNonTsExtensions: true, resolveJsonModule: jsonManifest}, host);
    if (program.getSyntacticDiagnostics(sourceFile).length) return unavailable('syntaxError');
  } catch (error) {
    if (error instanceof RangeError || error instanceof SyntaxError) return unavailable('parserResourceOrSyntaxError');
    throw error; // Original compiler/host contract failures are not silently successful scans.
  }
  if (cancelled() || performance.now() >= deadline) return unavailable('cancelledOrParseBudget');
  // Original compiler positions are UTF-16 units. Map once to actual UTF-8 bytes.
  offsets = new Uint32Array(source.length + 1);
  for (let index = 0, byte = 0; index < source.length;) {
    const scalar = source.codePointAt(index), units = scalar > 0xffff ? 2 : 1;
    offsets[index] = byte;
    if (units === 2) offsets[index + 1] = byte;
    byte += scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4;
    index += units;
    offsets[index] = byte;
  }
  const literal = node => node && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node))
    && node.text.isWellFormed() && !node.text.includes('\0') && Buffer.byteLength(node.text) <= 256 ? node.text : undefined;
  const moduleFact = (specifier, node, reason, conditional) => {
    const value = literal(specifier);
    emit(value === undefined ? 'unknown' : 'moduleReference', value ?? null, node,
      value === undefined ? 'dynamicModuleSpecifier' : value.endsWith('.node')
        ? 'nativeAddonReferenceNotAvailability' : reason, conditional);
  };
  const conditionalKinds = new Set([ts.SyntaxKind.IfStatement, ts.SyntaxKind.ConditionalExpression,
    ts.SyntaxKind.TryStatement, ts.SyntaxKind.SwitchStatement, ts.SyntaxKind.ForStatement,
    ts.SyntaxKind.ForOfStatement, ts.SyntaxKind.ForInStatement, ts.SyntaxKind.WhileStatement,
    ts.SyntaxKind.DoStatement, ts.SyntaxKind.FunctionDeclaration, ts.SyntaxKind.FunctionExpression,
    ts.SyntaxKind.ArrowFunction, ts.SyntaxKind.MethodDeclaration, ts.SyntaxKind.Constructor,
    ts.SyntaxKind.ClassDeclaration, ts.SyntaxKind.BinaryExpression]);
  const pending = [[sourceFile, 0, false]];
  const manifestRoot = jsonManifest ? sourceFile.statements[0]?.expression : undefined;
  if (jsonManifest && (!manifestRoot || !ts.isObjectLiteralExpression(manifestRoot))) return unavailable('unsupportedManifestRoot');
  const manifestObjects = new Map();
  const seenKeys = new Map();
  if (manifestRoot) manifestObjects.set(manifestRoot, 'root');
  const manifestProperty = node => {
    const mode = manifestObjects.get(node.parent);
    if (!mode) return;
    const key = literal(node.name);
    if (key === undefined) { emit('unknown', null, node, 'unsupportedManifestKey'); return; }
    const seen = seenKeys.get(node.parent) ?? new Set();
    if (seen.has(key)) emit('unknown', null, node, 'duplicateManifestKey');
    seen.add(key); seenKeys.set(node.parent, seen);
    const value = literal(node.initializer);
    if (mode === 'root') {
      if (['dependencies', 'devDependencies', 'optionalDependencies', 'peerDependencies', 'engines', 'bin'].includes(key)) {
        if (key === 'bin' && value !== undefined) emit('scriptReference', value, node, 'declaredBinPathNotExecutableProof');
        else if (ts.isObjectLiteralExpression(node.initializer)) manifestObjects.set(node.initializer, key);
        else emit('unknown', null, node, 'unsupportedManifestDeclarationShape');
      } else if (['scripts', 'gypfile', 'os', 'cpu', 'libc', 'exports', 'peerDependenciesMeta'].includes(key))
        emit('unknown', null, node, 'lifecycleNativeOrPlatformMetadataNotResolved');
      else if (key === 'packageManager') emit(value === undefined ? 'unknown' : 'dependencyDeclaration', value ?? null,
        node, 'declaredPackageManagerNotAvailability');
    } else if (value === undefined) emit('unknown', null, node, 'unsupportedManifestConstraint');
    else if (mode === 'bin') emit('scriptReference', value, node, 'declaredBinPathNotExecutableProof');
    else {
      const constraint = key + '@' + value;
      emit(Buffer.byteLength(constraint) <= 256 ? 'dependencyDeclaration' : 'unknown',
        Buffer.byteLength(constraint) <= 256 ? constraint : null, node,
        mode === 'engines' ? 'declaredEngineRangeNotCompatibility'
          : mode === 'optionalDependencies' ? 'declaredNpmOptionalConstraintNotInstalled'
          : mode === 'devDependencies' ? 'declaredNpmDevelopmentConstraintNotInstalled'
          : mode === 'peerDependencies' ? 'declaredNpmPeerConstraintNotInstalled'
          : 'declaredNpmConstraintNotInstalled');
    }
  };
  while (pending.length) {
    const [node, depth, inherited] = pending.pop();
    if (report.visitedNodes >= maximumNodes || depth > maximumDepth || cancelled() || performance.now() >= deadline) {
      emit('unknown', null, node, 'traversalBudgetOrCancellation'); break;
    }
    report.visitedNodes++;
    const conditional = inherited || conditionalKinds.has(node.kind);
    if (jsonManifest && ts.isPropertyAssignment(node)) manifestProperty(node);
    else if (ts.isImportDeclaration(node)) {
      const clause = node.importClause, bindings = clause?.namedBindings;
      const onlyTypes = clause?.isTypeOnly || (clause && !clause.name && bindings && ts.isNamedImports(bindings)
        && bindings.elements.length > 0 && bindings.elements.every(element => element.isTypeOnly));
      moduleFact(node.moduleSpecifier, node,
        onlyTypes ? 'typeOnlyImportNotRuntimeRequirement' : 'literalImportNotPackageResolution', conditional);
    }
    else if (ts.isExportDeclaration(node) && node.moduleSpecifier) moduleFact(node.moduleSpecifier, node,
      node.isTypeOnly || (node.exportClause && ts.isNamedExports(node.exportClause)
        && node.exportClause.elements.length > 0 && node.exportClause.elements.every(element => element.isTypeOnly))
        ? 'typeOnlyExportNotRuntimeRequirement' : 'literalExportNotPackageResolution', conditional);
    else if (ts.isImportEqualsDeclaration(node) && ts.isExternalModuleReference(node.moduleReference))
      moduleFact(node.moduleReference.expression, node, 'literalImportEqualsNotPackageResolution', conditional);
    else if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument))
      moduleFact(node.argument.literal, node, 'typeOnlyImportNotRuntimeRequirement', conditional);
    else if (ts.isVariableDeclaration(node) && node.initializer && ts.isIdentifier(node.initializer)
      && node.initializer.text === 'require') emit('unknown', null, node, 'unresolvedLoaderAlias', conditional);
    else if (ts.isCallExpression(node)) {
      const called = node.expression;
      if (called.kind === ts.SyntaxKind.ImportKeyword || (ts.isIdentifier(called) && called.text === 'require'))
        moduleFact(node.arguments[0], node, 'literalDynamicImportSyntaxNotPackageResolution', conditional);
      else if (ts.isPropertyAccessExpression(called) && ts.isIdentifier(called.expression)
        && called.expression.text === 'require' && called.name.text === 'resolve')
        moduleFact(node.arguments[0], node, 'literalResolveSyntaxNotPackageResolution', conditional);
      else if (ts.isPropertyAccessExpression(called) && ts.isMetaProperty(called.expression)
        && called.expression.keywordToken === ts.SyntaxKind.ImportKeyword && called.name.text === 'resolve')
        moduleFact(node.arguments[0], node, 'literalResolveSyntaxNotPackageResolution', conditional);
      else if (ts.isIdentifier(called) && ['eval', 'Function'].includes(called.text))
        emit('unknown', null, node, 'dynamicEvaluation', conditional);
      else if (ts.isCallExpression(called) || ts.isElementAccessExpression(called)
        || (ts.isPropertyAccessExpression(called) && (called.name.text === 'require'
          || (ts.isIdentifier(called.expression) && called.expression.text === 'require'))))
        emit('unknown', null, node, 'dynamicCallableResolution', conditional);
    } else if (ts.isNewExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === 'Function')
      emit('unknown', null, node, 'dynamicEvaluation', conditional);
    if (report.findings.length >= maximumFindings - 1) { emit('unknown', null, node, 'findingBudget'); break; }
    const children = [];
    let exceeded = false;
    ts.forEachChild(node, child => {
      if (children.length + pending.length >= maximumNodes - report.visitedNodes) { exceeded = true; return true; }
      children.push(child);
    });
    if (exceeded) { emit('unknown', null, node, 'pendingNodeBudget'); break; }
    for (let index = children.length - 1; index >= 0; index--) pending.push([children[index], depth + 1, conditional]);
  }
  return report;
}
