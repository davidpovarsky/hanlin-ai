"""Passive Python dependency declarations; trusted stdlib + existing packaging parser.

Runtime supplies its already-installed original packaging.Requirement, never an import
from Skill paths. No referenced requirements, build backend, wheel or binary is loaded.
"""
import hashlib
import sys
import time
import tomllib


def analyze_python_manifest(file, utf8, *, requirement_parser=None, packaging_version=None,
                            maximum_bytes=262144, maximum_findings=256, maximum_nodes=20000,
                            maximum_depth=64, parse_seconds=0.1,
                            cancelled=lambda: False):
    maximum_bytes = min(max(int(maximum_bytes), 1), 1048576)
    maximum_findings = min(max(int(maximum_findings), 2), 1024)
    maximum_nodes = min(max(int(maximum_nodes), 1), 100000)
    maximum_depth = min(max(int(maximum_depth), 1), 128)
    parse_seconds = min(max(float(parse_seconds), 0.001), 1)
    if not parse_seconds > 0:
        parse_seconds = 0.1
    report = dict(file=file, sourceSHA256=None, completion='complete',
        provenance=dict(scanner='python.tomllib+packaging/' + (packaging_version or 'unavailable'),
                        engineVersion=sys.version.split()[0]), findings=[], visitedNodes=0,
        inputBytes=len(utf8) if isinstance(utf8, bytes) else 0,
        limitations=['declaredConstraintsNotInstalledOrCompatible', 'noImportDistributionMapping',
                     'noReferencedFileReadsOrExecution', 'noBuildBackendOrDynamicMetadataExecution',
                     'TOMLDeclarationsUseWholeDocumentSpanNotInventedTokenPositions',
                     'synchronousInputBoundedParseNotHardTimeOrRSSCap'])

    def emit(kind, value, reason, line=1, offset=0, length=0, confidence='unknown'):
        if len(report['findings']) >= maximum_findings:
            report['completion'] = 'partial'
            return
        if kind == 'unknown' or confidence == 'unknown':
            report['completion'] = 'partial'
        report['findings'].append(dict(kind=kind, value=value, confidence=confidence,
            source=dict(file=file, line=line, utf8Column=1, byteOffset=offset, byteLength=length), reason=reason))

    def unavailable(reason):
        emit('unknown', None, reason)
        report['completion'] = 'unknown'
        return report

    if not isinstance(utf8, bytes):
        return unavailable('immutableUTF8BytesRequired')
    if not isinstance(file, str) or not file or len(file.encode()) > 1024 or '\0' in file:
        return unavailable('invalidSourceIdentity')
    if len(utf8) > maximum_bytes:
        return unavailable('sourceBudget')
    if cancelled():
        return unavailable('cancelled')
    try:
        source = utf8.decode('utf-8', errors='strict')
    except UnicodeDecodeError:
        return unavailable('invalidUTF8')
    report['sourceSHA256'] = hashlib.sha256(utf8).hexdigest()
    deadline = time.monotonic() + parse_seconds
    basename = file.replace('\\', '/').rsplit('/', 1)[-1]

    def declaration(value, reason, *, line=1, offset=0, length=0, exact_line=False):
        if cancelled() or time.monotonic() >= deadline:
            emit('unknown', None, 'deadlineOrCancellation', line, offset, length)
            return False
        if not isinstance(value, str) or len(value.encode('utf-8')) > 256:
            emit('unknown', None, 'unsupportedOrOversizedDeclaration', line, offset, length)
        elif requirement_parser is None or packaging_version != '26.3':
            emit('unknown', value, 'trustedOriginalPackagingParserUnavailable', line, offset, length)
        else:
            try:
                requirement_parser(value)  # Original PEP508 parser only; no resolution/install/import.
            except ValueError:
                emit('unknown', value, 'invalidPEP508Declaration', line, offset, length)
            except (RecursionError, MemoryError):
                emit('unknown', None, 'PEP508ParserResourceError', line, offset, length)
            else:
                emit('dependencyDeclaration', value, reason, line, offset, length,
                     'literalSyntax' if exact_line else 'unknown')
        if len(report['findings']) >= maximum_findings - 1:
            emit('unknown', None, 'findingBudget', line, offset, length)
            return False
        return True

    if basename == 'requirements.txt':
        offset = 0
        for index, raw_line in enumerate(utf8.splitlines(keepends=True), 1):
            if report['visitedNodes'] >= maximum_nodes or len(report['findings']) >= maximum_findings - 1:
                emit('unknown', None, 'nodeOrFindingBudget', index, offset, 0)
                break
            report['visitedNodes'] += 1
            text = raw_line.decode('utf-8').strip()
            if text and not text.startswith('#'):
                if text.startswith('-') or text.endswith('\\'):
                    emit('unknown', None, 'pipDirectiveOrContinuationNotFollowed', index, offset, len(raw_line))
                elif not declaration(text, 'declaredPEP508NotInstalled', line=index, offset=offset,
                                     length=len(raw_line), exact_line=True):
                    break
            offset += len(raw_line)
            if cancelled() or time.monotonic() >= deadline:
                emit('unknown', None, 'deadlineOrCancellation', index, offset - len(raw_line), len(raw_line))
                break
        return report
    if basename != 'pyproject.toml':
        return unavailable('unsupportedManifestKind')
    try:
        document = tomllib.loads(source)  # Original stdlib; duplicate keys/malformed TOML rejected.
    except (ValueError, RecursionError, MemoryError):
        return unavailable('malformedOrResourceLimitedTOML')
    if cancelled() or time.monotonic() >= deadline:
        return unavailable('cancelledOrParseBudget')
    pending = [(document, 0)]
    while pending:
        value, depth = pending.pop()
        if (report['visitedNodes'] >= maximum_nodes or depth > maximum_depth or cancelled()
                or time.monotonic() >= deadline):
            return unavailable('TOMLNodeDepthDeadlineOrCancellationBudget')
        report['visitedNodes'] += 1
        children = value.values() if isinstance(value, dict) else value if isinstance(value, list) else ()
        for child in children:
            if len(pending) >= maximum_nodes - report['visitedNodes']:
                return unavailable('TOMLPendingNodeBudget')
            pending.append((child, depth + 1))
    # tomllib exposes values, not token spans. Whole-document span + UNKNOWN confidence
    # explicitly preserves that limitation; no find()/custom TOML lexer invents positions.
    project = document.get('project')
    if project is not None and not isinstance(project, dict):
        return unavailable('unsupportedProjectShape')
    project = project or {}
    groups = []
    if 'dependencies' in project:
        groups.append(('declaredProjectDependencyWholeDocumentSpan', project['dependencies']))
    optional = project.get('optional-dependencies', {})
    if isinstance(optional, dict):
        groups.extend(('declaredOptionalDependencyWholeDocumentSpan', value) for value in optional.values())
    else:
        emit('unknown', None, 'unsupportedOptionalDependencyShape', length=len(utf8))
    build = document.get('build-system', {})
    if isinstance(build, dict) and 'requires' in build:
        groups.append(('declaredBuildRequirementWholeDocumentSpan', build['requires']))
    elif not isinstance(build, dict):
        emit('unknown', None, 'unsupportedBuildSystemShape', length=len(utf8))
    if project.get('dynamic'):
        emit('unknown', None, 'dynamicProjectMetadataNotExecuted', length=len(utf8))
    if 'tool' in document or 'dependency-groups' in document:
        emit('unknown', None, 'additionalDependencyMetadataNotInterpreted', length=len(utf8))
    if 'requires-python' in project:
        emit('unknown', project['requires-python'] if isinstance(project['requires-python'], str)
             and len(project['requires-python'].encode()) <= 256 else None,
             'declaredPythonVersionRangeNotResolved', length=len(utf8))
    for reason, values in groups:
        if not isinstance(values, list):
            emit('unknown', None, 'unsupportedDependencyListShape', length=len(utf8))
            continue
        for value in values:
            if not declaration(value, reason, length=len(utf8)):
                return report
    return report
