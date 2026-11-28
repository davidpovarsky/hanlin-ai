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


# Module resolution is an explicit native inspection, separate from the syntax
# scanner above. It uses already-loaded original interpreter dependencies and
# never imports a dotted name's parent or invokes a custom import hook.
# This is not a security boundary against arbitrary mutation of CPython itself.
def inspect_python_module_requirements(findings, *, maximum_modules=64,
                                       maximum_source_bytes=64 * 1024 * 1024):
    names = sorted({item.get('value') for item in findings
                    if type(item) is dict and type(item.get('kind')) is str
                    and item.get('kind') == 'moduleReference'
                    and type(item.get('value')) is str})
    report = dict(scope='native-skill-isolated', producer='CPython.importlib.machinery',
                  engineVersion=sys.version.split()[0], resolutionOnly=True, modules=[])
    maximum_modules = min(max(int(maximum_modules), 1), 64)
    maximum_source_bytes = min(max(int(maximum_source_bytes), 1), 64 * 1024 * 1024)

    def unresolved(reason):
        report['modules'] = [dict(name=name, status='unknown', reason=reason,
                                  resolvedPath=None, sourceFiles=[]) for name in names[:maximum_modules]]
        return report

    if len(names) > maximum_modules:
        return unresolved('moduleBudget')

    # All dependencies below are loaded by original CPython startup and the
    # existing HanlinPythonExecution bootstrap. Do not import a missing helper:
    # that could dispatch an untrusted hook before the state checks below.
    module_type = type(sys)
    function_type = type(lambda: None)
    state = vars(sys)
    module_cache = state.get('modules')
    if type(module_cache) is not dict or any(type(key) is not str for key in module_cache):
        return unresolved('opaqueModuleCache')

    def loaded_values(name):
        module = module_cache.get(name)
        return vars(module) if type(module) is module_type else None

    bootstrap = loaded_values('_frozen_importlib')
    external = loaded_values('_frozen_importlib_external')
    os_values = loaded_values('os')
    zip_values = loaded_values('zipimport')
    if any(value is None for value in (bootstrap, external, os_values, zip_values)):
        return unresolved('inspectionDependencyUnavailable')
    path_module = os_values.get('path')
    if type(path_module) is not module_type:
        return unresolved('inspectionDependencyUnavailable')
    path_values = vars(path_module)
    isabs, realpath, normcase = (path_values.get(name) for name in ('isabs', 'realpath', 'normcase'))
    if any(type(value) is not function_type for value in (isabs, realpath, normcase)):
        return unresolved('inspectionDependencyUnavailable')

    BuiltinImporter, FrozenImporter, ModuleSpec = (
        bootstrap.get(name) for name in ('BuiltinImporter', 'FrozenImporter', 'ModuleSpec'))
    PathFinder, FileFinder, SourceFileLoader, SourcelessFileLoader, ExtensionFileLoader = (
        external.get(name) for name in ('PathFinder', 'FileFinder', 'SourceFileLoader',
                                       'SourcelessFileLoader', 'ExtensionFileLoader'))
    AppleFrameworkLoader = external.get('AppleFrameworkLoader')
    ZipImporter = zip_values.get('zipimporter')
    original_loaders = external.get('_get_supported_file_loaders')
    classes = (BuiltinImporter, FrozenImporter, ModuleSpec, PathFinder, FileFinder,
               SourceFileLoader, SourcelessFileLoader, ExtensionFileLoader, ZipImporter)
    if any(type(value) is not type for value in classes) or type(original_loaders) is not function_type:
        return unresolved('inspectionDependencyUnavailable')
    if AppleFrameworkLoader is not None and type(AppleFrameworkLoader) is not type:
        return unresolved('inspectionDependencyUnavailable')

    # Identity checks for arbitrary objects; structural equality is allowed only
    # after exact builtin string/list/tuple types have been established. A custom
    # __eq__ or __ne__ must not execute while rejecting an import hook or loader.
    def same_original(value, expected):
        if value is expected:
            return True
        if type(value) is str and type(expected) is str:
            return value == expected
        if type(value) is not type(expected) or (type(value) is not tuple and type(value) is not list):
            return False
        return len(value) == len(expected) and all(same_original(a, b) for a, b in zip(value, expected))

    expected_meta = (BuiltinImporter, FrozenImporter, PathFinder)
    loaders = original_loaders()
    original_hook = FileFinder.path_hook(*loaders)
    original_closure = tuple(cell.cell_contents for cell in original_hook.__closure__)
    expected_loaders = [(suffix, loader) for loader, suffixes in loaders for suffix in suffixes]
    sys_path = state.get('path')
    path_hooks = state.get('path_hooks')
    previous_cache = state.get('path_importer_cache')

    def supported_state():
        meta = state.get('meta_path')
        if (type(meta) is not list and type(meta) is not tuple) or len(meta) != len(expected_meta):
            return False
        if any(item is not expected for item, expected in zip(meta, expected_meta)):
            return False
        if type(path_hooks) is not list and type(path_hooks) is not tuple:
            return False
        for hook in path_hooks:
            if hook is ZipImporter:
                continue
            if (type(hook) is not function_type or hook.__code__ is not original_hook.__code__
                    or not same_original(tuple(cell.cell_contents for cell in hook.__closure__ or ()), original_closure)):
                return False
        if (type(sys_path) is not list and type(sys_path) is not tuple) or len(sys_path) > 256:
            return False
        if any(type(path) is not str or not isabs(path) for path in sys_path):
            return False
        if type(previous_cache) is not dict or any(type(key) is not str for key in previous_cache):
            return False
        for path in sys_path:
            finder = previous_cache.get(path)
            if finder is None or type(finder) is ZipImporter:
                continue
            if type(finder) is not FileFinder:
                return False
            values = vars(finder)
            finder_path = values.get('path')
            if (not same_original(values.get('_loaders'), expected_loaders)
                    or type(finder_path) is not str or normcase(finder_path) != normcase(path)):
                return False
        return True

    if not supported_state():
        return unresolved('customOrUnboundedImportState')
    file_cache = {}
    used_bytes = 0

    def source_identity(path):
        nonlocal used_bytes
        path = realpath(path)
        if path in file_cache:
            return file_cache[path]
        count = 0
        digest = hashlib.sha256()
        with open(path, 'rb') as stream:
            while True:
                chunk = stream.read(min(65536, maximum_source_bytes - used_bytes + 1))
                if not chunk:
                    break
                count += len(chunk)
                used_bytes += len(chunk)
                if used_bytes > maximum_source_bytes:
                    raise ValueError('sourceBudget')
                digest.update(chunk)
        value = dict(path=path, sha256=digest.hexdigest(), bytes=count)
        file_cache[path] = value
        return value

    def resolve(name):
        unknown = lambda reason: dict(name=name, status='unknown', reason=reason,
                                      resolvedPath=None, sourceFiles=[])
        if not name or len(name.encode('utf-8')) > 256 or any(not part.isidentifier() for part in name.split('.')):
            return unknown('unsupportedModuleName')
        path = list(sys_path)
        sources = {}
        origin = None
        for index, _ in enumerate(name.split('.')):
            current = '.'.join(name.split('.')[:index + 1])
            initialized = current in module_cache
            if initialized:
                module = module_cache[current]
                if type(module) is not module_type:
                    return unknown('opaqueModuleCache')
                values = vars(module)
                spec = values.get('__spec__')
                if type(spec) is not ModuleSpec:
                    return unknown('opaqueModuleSpec')
            else:
                spec = BuiltinImporter.find_spec(current)
                if spec is None:
                    spec = FrozenImporter.find_spec(current)
                if spec is None:
                    spec = PathFinder.find_spec(current, path)
                values = {}
            if spec is None:
                # A non-executed parent can define paths dynamically. Absence in
                # this bounded resolver is not proof that installing is required.
                return unknown('notResolvedWithoutImport')
            if type(spec) is not ModuleSpec:
                return unknown('opaqueModuleSpec')
            spec_values = vars(spec)
            loader = spec_values.get('loader')
            origin = spec_values.get('origin')
            if origin is not None and type(origin) is not str:
                return unknown('opaqueModuleOrigin')
            if loader is BuiltinImporter or loader is FrozenImporter:
                pass
            elif type(loader) is ZipImporter:
                item = source_identity(loader.archive); sources[item['path']] = item
            elif type(loader) is SourceFileLoader or type(loader) is SourcelessFileLoader:
                if type(origin) is not str:
                    return unknown('missingSourceOrigin')
                item = source_identity(origin); sources[item['path']] = item
            elif type(loader) is ExtensionFileLoader or (AppleFrameworkLoader is not None and type(loader) is AppleFrameworkLoader):
                if not initialized:
                    return unknown('nativeInitializationUnobserved')
                if type(origin) is not str:
                    return unknown('missingNativeOrigin')
                item = source_identity(origin); sources[item['path']] = item
            else:
                return unknown('customLoaderOrNamespace')
            if index + 1 < len(name.split('.')):
                declared_path = spec_values.get('submodule_search_locations')
                if ((type(declared_path) is not list and type(declared_path) is not tuple)
                        or any(type(item) is not str for item in declared_path)):
                    return unknown('dynamicNamespacePath')
                actual_path = values.get('__path__', declared_path)
                if ((type(actual_path) is not list and type(actual_path) is not tuple)
                        or any(type(item) is not str for item in actual_path)
                        or not same_original(list(actual_path), list(declared_path))):
                    return unknown('dynamicParentPath')
                path = list(actual_path)
                if len(path) > 256 or any(not isabs(item) for item in path):
                    return unknown('unboundedParentPath')
        return dict(name=name, status='available', reason='resolvedWithoutImport',
                    resolvedPath=origin, sourceFiles=[sources[key] for key in sorted(sources)])

    # Fresh original finder state avoids stale directory/ZIP caches. Restore the
    # exact previous cache object even when a source disappears during inspection.
    try:
        sys.path_importer_cache = {}
        for name in names:
            try:
                report['modules'].append(resolve(name))
            except (ImportError, OSError, ValueError, KeyError, TypeError):
                report['modules'].append(dict(name=name, status='unknown', reason='resolutionUnavailable',
                                              resolvedPath=None, sourceFiles=[]))
    finally:
        sys.path_importer_cache = previous_cache
    return report
