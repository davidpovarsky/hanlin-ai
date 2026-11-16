"""Trusted, passive bytes -> syntax facts helper for the EXISTING Python engine.

Runtime05 must register this with trusted stdlib imports before any Skill sys.path/cwd
changes. No analyzed module is imported, compiled to executable code, or run here.
The actual interpreter version is reported; host tests cannot certify embedded3.14.
"""
import ast
import hashlib
import sys
import time


def analyze_python_source(file, utf8, *, maximum_bytes=262144, maximum_nodes=20000,
                          maximum_findings=256, maximum_depth=128, parse_seconds=0.1,
                          cancelled=lambda: False):
    maximum_bytes = min(max(int(maximum_bytes), 1), 1048576)
    maximum_nodes = min(max(int(maximum_nodes), 1), 100000)
    maximum_findings = min(max(int(maximum_findings), 2), 1024)
    maximum_depth = min(max(int(maximum_depth), 1), 512)
    parse_seconds = min(max(float(parse_seconds), 0.001), 1)
    if not (parse_seconds > 0):
        parse_seconds = 0.1
    report = dict(file=file, sourceSHA256=None, completion='complete',
                  provenance=dict(scanner='cpython.ast', engineVersion=sys.version.split()[0]),
                  findings=[], visitedNodes=0, inputBytes=len(utf8) if isinstance(utf8, (bytes, bytearray, str)) else 0, limitations=[
                      'syntaxOnlyNotReadinessOrPermission', 'noImportDistributionMapping',
                      'noReferencedFileReadsOrExecution', 'aliasesAndBindingsNotResolved',
                      'conditionalFactsDoNotProveReachability',
                      'parseIsSynchronousInputBoundedNotHardTimeOrRSSCap'])
    line_starts = [0]

    def location(node=None):
        if node is None or not hasattr(node, 'lineno'):
            return dict(file=file, line=1, utf8Column=1, byteOffset=0, byteLength=0)
        line = node.lineno
        column = node.col_offset
        start = line_starts[min(line - 1, len(line_starts) - 1)] + column
        end_line = getattr(node, 'end_lineno', line) or line
        end_column = getattr(node, 'end_col_offset', column) or column
        end = line_starts[min(end_line - 1, len(line_starts) - 1)] + end_column
        return dict(file=file, line=line, utf8Column=column + 1,
                    byteOffset=start, byteLength=max(0, end - start))

    def emit(kind, value, node, reason, conditional=False):
        if len(report['findings']) >= maximum_findings:
            report['completion'] = 'partial'
            return
        if kind == 'unknown':
            report['completion'] = 'partial'
        report['findings'].append(dict(kind=kind, value=value,
            confidence='unknown' if kind == 'unknown' else 'conditionalSyntax' if conditional else 'literalSyntax',
            source=location(node), reason=reason))

    def unavailable(reason):
        report['completion'] = 'unknown'
        report['findings'] = []
        emit('unknown', None, None, reason)
        report['completion'] = 'unknown'
        return report

    if not isinstance(file, str) or not file or len(file.encode('utf-8')) > 1024 or '\0' in file:
        return unavailable('invalidSourceIdentity')
    if not isinstance(utf8, bytes):
        return unavailable('immutableUTF8BytesRequired')
    if len(utf8) > maximum_bytes:
        return unavailable('sourceBudget')
    if cancelled():
        return unavailable('cancelled')
    try:
        source = utf8.decode('utf-8', errors='strict')
    except UnicodeDecodeError:
        return unavailable('invalidUTF8')
    report['sourceSHA256'] = hashlib.sha256(utf8).hexdigest()
    for index, byte in enumerate(utf8):
        if byte == 10 or (byte == 13 and (index + 1 == len(utf8) or utf8[index + 1] != 10)):
            line_starts.append(index + 1)
    deadline = time.monotonic() + parse_seconds
    try:
        root = ast.parse(source, filename=file, mode='exec', type_comments=True)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return unavailable('syntaxOrParserResourceError')
    if cancelled() or time.monotonic() >= deadline:
        return unavailable('cancelledOrParseBudget')
    conditional_nodes = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda,
                         ast.If, ast.IfExp, ast.For, ast.AsyncFor, ast.While, ast.Try,
                         ast.Match, ast.BoolOp, ast.comprehension)
    pending = [(root, 0, False)]

    def literal(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            try:
                if len(node.value.encode('utf-8')) <= 256 and '\0' not in node.value:
                    return node.value
            except UnicodeEncodeError:
                pass
        return None

    while pending:
        node, depth, conditional = pending.pop()
        if (report['visitedNodes'] >= maximum_nodes or depth > maximum_depth or cancelled()
                or time.monotonic() >= deadline):
            emit('unknown', None, node, 'traversalBudgetOrCancellation')
            break
        report['visitedNodes'] += 1
        conditional = conditional or isinstance(node, conditional_nodes) or type(node).__name__ == 'TryStar'
        if isinstance(node, ast.Import):
            for alias in node.names:
                if len(report['findings']) >= maximum_findings - 1:
                    break
                if len(alias.name.encode('utf-8')) > 256:
                    emit('unknown', None, alias, 'moduleNameBudget')
                else:
                    emit('moduleReference', alias.name, alias,
                         'literalImportNotDistributionMapping', conditional)
                if alias.name == 'importlib' and alias.asname:
                    emit('unknown', None, alias, 'unresolvedImportAlias', conditional)
        elif isinstance(node, ast.ImportFrom):
            name = '.' * node.level + (node.module or '')
            if len(name.encode('utf-8')) <= 256:
                emit('moduleReference', name, node, 'relativeImportNotResolved' if node.level
                     else 'literalImportNotDistributionMapping', conditional)
            else:
                emit('unknown', None, node, 'moduleNameBudget')
            if node.level:
                emit('unknown', None, node, 'relativeModuleResolutionUnavailable', conditional)
            if node.module == 'importlib' and any(alias.name == 'import_module' for alias in node.names):
                emit('unknown', None, node, 'unresolvedImportAlias', conditional)
        elif isinstance(node, ast.Call):
            function = node.func
            name = function.id if isinstance(function, ast.Name) else None
            qualified = (function.value.id + '.' + function.attr
                         if isinstance(function, ast.Attribute) and isinstance(function.value, ast.Name) else None)
            if name == '__import__' or qualified == 'importlib.import_module':
                target = literal(node.args[0]) if node.args else None
                emit('moduleReference' if target is not None else 'unknown', target, node,
                     'literalDynamicImportSyntaxNotDistributionMapping' if target is not None else 'dynamicImport', conditional)
                if len(node.args) > 1 or node.keywords:
                    emit('unknown', None, node, 'dynamicImportResolutionArguments', conditional)
            elif name in ('eval', 'exec', 'compile') or qualified in ('os.system', 'subprocess.run', 'subprocess.Popen'):
                emit('unknown', None, node, 'dynamicEvaluationOrProcessInvocation', conditional)
            elif isinstance(function, ast.Attribute) and function.attr == 'import_module':
                emit('unknown', None, node, 'unresolvedImportAlias', conditional)
            elif qualified in ('ctypes.CDLL', 'ctypes.PyDLL'):
                emit('unknown', None, node, 'nativeLibraryAvailabilityNotResolved', conditional)
            elif name in ('getattr', 'globals', 'locals') or isinstance(function, (ast.Subscript, ast.Call)):
                emit('unknown', None, node, 'dynamicCallableResolution', conditional)
        if len(report['findings']) >= maximum_findings - 1:
            emit('unknown', None, node, 'findingBudget')
            break
        children = []
        for child in ast.iter_child_nodes(node):
            if len(children) + len(pending) >= maximum_nodes - report['visitedNodes']:
                emit('unknown', None, node, 'pendingNodeBudget')
                break
            children.append(child)
        else:
            pending.extend((child, depth + 1, conditional) for child in reversed(children))
            continue
        break
    return report
