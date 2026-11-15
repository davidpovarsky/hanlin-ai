"""Public framework entry headers shared by SDK probes and the app metadata phase."""
from __future__ import annotations

import contextlib
import hashlib
import json
from pathlib import Path
import re
import ctypes
import os
import subprocess
import sys
import tempfile


ROLE_MANIFEST = "metadata-input-roles.json"
PUBLIC_ROLE = "public-objc-c-root"
CPP_ROLE = "cpp-include-dependency"
INCOMPLETE_RECORD_POLICY_SOURCE = "5d4569c197810cdd4c1e02e7c16d42a01a77d5c0"


def declaration_role(declarations: list[dict]) -> str:
    # Records come from the installed compiler's cursor expansion locations,
    # not header-name matching or an absence-of-binary heuristic.
    if any(d["category"] == "public" for d in declarations):
        return PUBLIC_ROLE
    if any(d["category"] not in {"cpp", "public", "inert"} for d in declarations):
        return PUBLIC_ROLE
    return CPP_ROLE if any(d["category"] == "cpp" for d in declarations) else PUBLIC_ROLE


@contextlib.contextmanager
def compiler_working_directory(directory: Path):
    previous = Path.cwd()
    try:
        os.chdir(directory)
        yield
    finally:
        os.chdir(previous)


def compiler_environment_sha256() -> str:
    # These driver/preprocessor inputs affect implicit include lookup and target defaults.
    names = ["CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJC_INCLUDE_PATH",
             "OBJCPLUS_INCLUDE_PATH", "SDKROOT", "DEVELOPER_DIR", "PATH", "LANG", "LC_ALL",
             "LC_CTYPE", "MACOSX_DEPLOYMENT_TARGET", "IPHONEOS_DEPLOYMENT_TARGET"]
    return hashlib.sha256(json.dumps({name: os.environ.get(name) for name in names}, sort_keys=True).encode()).hexdigest()


def canonical_target(target: str) -> tuple:
    match = re.fullmatch(r"([^-]+)-apple-ios([0-9]+(?:\.[0-9]+)*)(-simulator|-macabi)?", target)
    if not match:
        raise RuntimeError("Framework input-role target is missing or unsupported: " + target)
    version = [int(part) for part in match.group(2).split(".")]
    while len(version) > 1 and version[-1] == 0:
        version.pop()
    return match.group(1), "apple", "ios", tuple(version), match.group(3) or ""


def verify_role_context(arguments: list[str], expected: list[str] | None = None) -> None:
    if expected is not None:
        if arguments != expected:
            raise RuntimeError("Framework input-role parser arguments changed")
    if os.environ.get("SDKROOT"):
        if "-isysroot" not in arguments or Path(arguments[arguments.index("-isysroot") + 1]).resolve() != Path(os.environ["SDKROOT"]).resolve():
            raise RuntimeError("Framework input-role SDK context changed")
        target = canonical_target(arguments[arguments.index("-target") + 1] if "-target" in arguments else "")
        if os.environ.get("ARCHS") and target[0] not in os.environ["ARCHS"].split():
            raise RuntimeError("Framework input-role architecture context changed")
        deployment = os.environ.get("IPHONEOS_DEPLOYMENT_TARGET")
        platform = os.environ.get("PLATFORM_NAME")
        if not deployment or platform not in {"iphoneos", "iphonesimulator"}:
            raise RuntimeError("Framework input-role effective deployment/environment is missing")
        suffix = "-simulator" if platform == "iphonesimulator" else ""
        if target != canonical_target(f"{target[0]}-apple-ios{deployment}{suffix}"):
            raise RuntimeError("Framework input-role deployment/environment context changed")


def parser_arguments(language: str, arguments: list[str]) -> list[str]:
    # Audit both grammars; retain every ordered target/define/include flag.
    standard = "gnu++20" if language == "objective-c++" else next((a[5:] for a in reversed(arguments) if a.startswith("-std=")), "gnu17")
    if "-x" in arguments or any(a.startswith("-xobjective") for a in arguments):
        raise RuntimeError("Framework input-role parser language override is unsupported")
    return ["-x", language, "-std=" + standard, *[a for a in arguments if not a.startswith("-std=")]]


def complete_language_proof(proof: dict, language: str, arguments: list[str]) -> bool:
    return (proof.get("complete") is True and bool(proof.get("compiler")) and
            proof.get("language") == language and
            proof.get("arguments") == parser_arguments(language, arguments) and
            proof.get("errors") == [] and isinstance(proof.get("diagnostics"), list) and
            not any(d.get("severity", 4) >= 3 for d in proof["diagnostics"]) and
            isinstance(proof.get("declarations"), list) and
            isinstance(proof.get("dependencies"), dict) and bool(proof["dependencies"]))


def inspect_header_declarations(headers: list[Path], arguments: list[str], library: Path,
                                language: str = "objective-c++") -> dict:
    """Inspect actual owned declarations using the selected compiler's libclang."""
    class Cursor(ctypes.Structure):
        _fields_ = [("kind", ctypes.c_uint), ("xdata", ctypes.c_int), ("data", ctypes.c_void_p * 3)]
    class Location(ctypes.Structure):
        _fields_ = [("ptr_data", ctypes.c_void_p * 2), ("int_data", ctypes.c_uint)]
    class String(ctypes.Structure):
        _fields_ = [("data", ctypes.c_void_p), ("flags", ctypes.c_uint)]
    lib = ctypes.CDLL(str(library))
    def bind(name, result, *args):
        fn = getattr(lib, name)
        fn.restype, fn.argtypes = result, list(args)
        return fn
    ptr, integer = ctypes.c_void_p, ctypes.c_uint
    create = bind("clang_createIndex", ptr, ctypes.c_int, ctypes.c_int)
    parse = bind("clang_parseTranslationUnit2", ctypes.c_int, ptr, ctypes.c_char_p,
                 ctypes.POINTER(ctypes.c_char_p), ctypes.c_int, ptr, integer, integer, ctypes.POINTER(ptr))
    root_cursor = bind("clang_getTranslationUnitCursor", Cursor, ptr)
    location = bind("clang_getCursorLocation", Location, Cursor)
    expansion = bind("clang_getExpansionLocation", None, Location, ctypes.POINTER(ptr),
                     ctypes.POINTER(integer), ctypes.POINTER(integer), ctypes.POINTER(integer))
    filename = bind("clang_getFileName", String, ptr)
    spelling = bind("clang_getCursorSpelling", String, Cursor)
    mangling = bind("clang_Cursor_getMangling", String, Cursor)
    parent = bind("clang_getCursorSemanticParent", Cursor, Cursor)
    lexical_parent = bind("clang_getCursorLexicalParent", Cursor, Cursor)
    definition = bind("clang_isCursorDefinition", integer, Cursor)
    printing_policy = bind("clang_getCursorPrintingPolicy", ptr, Cursor)
    printed = bind("clang_getCursorPrettyPrinted", String, Cursor, ptr)
    dispose_policy = bind("clang_PrintingPolicy_dispose", None, ptr)
    cstr = bind("clang_getCString", ctypes.c_char_p, String)
    dispose_string = bind("clang_disposeString", None, String)
    count_diagnostics = bind("clang_getNumDiagnostics", integer, ptr)
    diagnostic = bind("clang_getDiagnostic", ptr, ptr, integer)
    severity = bind("clang_getDiagnosticSeverity", integer, ptr)
    format_diag = bind("clang_formatDiagnostic", String, ptr, integer)
    dispose_diag = bind("clang_disposeDiagnostic", None, ptr)
    version = bind("clang_getClangVersion", String)
    def string(value):
        try:
            return (cstr(value) or b"").decode("utf-8", errors="replace")
        finally:
            dispose_string(value)
    callback_type = ctypes.CFUNCTYPE(integer, Cursor, Cursor, ptr)
    visit = bind("clang_visitChildren", integer, Cursor, callback_type, ptr)
    owned = {str(h.resolve()): h for h in headers}
    declarations, errors, diagnostics, callback_errors = [], [], [], []
    file_paths = {}
    def c_linkage(cursor):
        current = lexical_parent(cursor)
        for _ in range(64):
            if current.kind in {0, 70, 350}:
                return False
            if current.kind == 23:
                policy = printing_policy(current)
                try:
                    return string(printed(current, policy)).lstrip().startswith('extern "C"')
                finally:
                    dispose_policy(policy)
            current = lexical_parent(current)
        raise RuntimeError("Header-role lexical ancestry is unresolved")
    @callback_type
    def visitor(cursor, unused_parent, unused_data):
        try:
            if not 1 <= cursor.kind <= 39:
                return 2
            file = ptr()
            line, column, offset = integer(), integer(), integer()
            expansion(location(cursor), ctypes.byref(file), ctypes.byref(line), ctypes.byref(column), ctypes.byref(offset))
            if file.value not in file_paths:
                file_paths[file.value] = str(Path(string(filename(file))).resolve()) if file.value else ""
            path = file_paths[file.value]
            if path not in owned:
                return 2  # Recurse; imported headers can contain owned expansions.
            kind = cursor.kind
            ancestors = []
            ancestor = parent(cursor)
            for _ in range(64):
                if ancestor.kind in {0, 70, 350}:  # invalid/translation unit
                    break
                ancestors.append(ancestor.kind)
                ancestor = parent(ancestor)
            cpp_scope = any(k in {4, 21, 22, 24, 25, 26, 30, 31, 32} for k in ancestors)
            symbol = ""
            if 11 <= kind <= 19 or kind in {37, 38}:
                category = "public"
            elif kind == 8:  # C linkage remains public, even inside a C++ namespace.
                symbol = string(mangling(cursor))
                # A global C-compatible declaration acquires C++ mangling in
                # this inspection TU even without an extern-C wrapper. Keep it.
                category = "cpp" if cpp_scope and not c_linkage(cursor) and (not symbol or symbol.startswith(("_Z", "__Z", "?"))) else "public"
            elif kind == 9 and cpp_scope:
                symbol = string(mangling(cursor))
                category = "cpp" if not c_linkage(cursor) and (not symbol or symbol.startswith(("_Z", "__Z", "?"))) else "public"
            elif kind in {2, 3, 5} and not definition(cursor):
                # The pinned MetaFactory rejects forward records/enums. They
                # are not a supported entity by themselves; a public typedef,
                # function, global or complete definition still keeps the root.
                category = "inert"
            elif kind in {2, 3, 5, 7, 9, 20} and (not cpp_scope or c_linkage(cursor)):
                category = "public"  # C records/enums/globals/typedefs must survive.
            elif cpp_scope or kind in {4, 21, 22, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 39}:
                category = "cpp"
            elif kind in {6, 10, 23}:  # fields/parameters/linkage covered by their declarations
                return 2
            else:
                category = "unknown"  # Conservative public root, never silently skipped.
            declarations.append({"header": str(owned[path]), "line": line.value,
                                 "kind": kind, "name": string(spelling(cursor)), "category": category,
                                 "linkageName": symbol})
        except Exception as error:
            callback_errors.append(str(error))
        return 2
    inclusion_callback = ctypes.CFUNCTYPE(None, ptr, ctypes.POINTER(Location), integer, ptr)
    inclusions = bind("clang_getInclusions", None, ptr, inclusion_callback, ptr)
    dependencies = {}
    @inclusion_callback
    def inclusion(file, unused_stack, unused_length, unused_data):
        try:
            path = Path(string(filename(file)))
            if path.is_file() and path.resolve() != driver.resolve():
                dependencies[str(path.resolve())] = hashlib.sha256(path.read_bytes()).hexdigest()
        except Exception as error:
            callback_errors.append(str(error))
    index, unit = create(0, 0), ptr()
    try:
        with tempfile.TemporaryDirectory(prefix="hanlin-header-role-") as folder:
            driver = Path(folder) / "input.mm"
            driver.write_text("\n".join('#include "' + str(h.resolve()).replace("\\", "/") + '"' for h in headers) + "\n", encoding="utf-8")
            actual_parser_arguments = parser_arguments(language, arguments)
            args = [a.encode() for a in actual_parser_arguments]
            result = parse(index, os.fsencode(driver), (ctypes.c_char_p * len(args))(*args), len(args), None, 0, 0x40, ctypes.byref(unit))
            if result or not unit.value:
                raise RuntimeError(f"Actual libclang header-role parse failed: {result}")
            for n in range(count_diagnostics(unit)):
                item = diagnostic(unit, n)
                try:
                    level, message = severity(item), string(format_diag(item, 0))
                    diagnostics.append({"severity": level, "message": message})
                    if level >= 3:
                        errors.append(message)
                finally:
                    dispose_diag(item)
            if not errors:
                visit(root_cursor(unit), visitor, None)
            inclusions(unit, inclusion, None)
            if callback_errors:
                raise RuntimeError("Header-role cursor inspection failed: " + "; ".join(callback_errors))
            return {"compiler": string(version()), "errors": errors, "diagnostics": diagnostics, "declarations": declarations,
                    "language": language, "arguments": actual_parser_arguments, "complete": not errors,
                    "dependencies": dependencies,
                    "role": PUBLIC_ROLE if errors else declaration_role(declarations)}
    finally:
        if unit.value:
            bind("clang_disposeTranslationUnit", None, ptr)(unit)
        bind("clang_disposeIndex", None, ptr)(index)


def produce_role_inventory(directory: Path, arguments: list[str], library: Path, classify: bool = True, receipt_path: Path | None = None) -> dict:
    repository = Path(__file__).resolve().parents[2]
    build_tool = repository / "Scripts/NativeScript/build-metadata-tool.py"
    if f'SOURCE = "{INCOMPLETE_RECORD_POLICY_SOURCE}"' not in build_tool.read_text(encoding="utf-8"):
        raise RuntimeError("Metadata declaration policy needs review for the changed runtime source")
    records = []
    for framework in sorted(directory.glob("*.framework")):
        # Every file in the hashed header tree participates, including future
        # .hpp/.inc files not yet imported by today's entry header.
        headers = sorted(p for sub in ["Headers", "PrivateHeaders"] for p in (framework / sub).rglob("*") if p.is_file())
        # A cheap conservative screen avoids parsing ObjC/C frameworks at all.
        texts = "\n".join(p.read_text(encoding="utf-8", errors="strict") for p in headers)
        if not classify or not re.search(r'\b(namespace|class|template)\b', texts) or re.search(r'@(interface|protocol)\b', texts):
            proof = {"role": PUBLIC_ROLE, "errors": [], "declarations": [], "reason": "Conservative public root"}
        else:
            proof = inspect_header_declarations(headers, arguments, library)
            if proof["role"] == CPP_ROLE:
                # A dual-language header may expose a C API only in its
                # non-C++ branch. Inspect the actual ObjC translation as well.
                objc = inspect_header_declarations(headers, arguments, library, "objective-c")
                proof["objcCompatibility"] = objc
                if not complete_language_proof(objc, "objective-c", arguments) or any(
                    d["category"] not in {"cpp", "inert"} for d in objc["declarations"]
                ):
                    proof["role"] = PUBLIC_ROLE
            for declaration in proof["declarations"]:
                declaration["header"] = Path(declaration["header"]).relative_to(framework.resolve()).as_posix()
            for declaration in proof.get("objcCompatibility", {}).get("declarations", []):
                declaration["header"] = Path(declaration["header"]).relative_to(framework.resolve()).as_posix()
        records.append({"framework": framework.name, "relativePath": framework.name,
                        "modules": module_names((framework / "Modules/module.modulemap").read_text(encoding="utf-8"))
                            if (framework / "Modules/module.modulemap").is_file() else [],
                        "inputSHA256": framework_inputs(framework), "role": proof["role"], "proof": proof})
    manifest = {"schemaVersion": 2, "producer": "Scripts/Expo/prepare-ios-dependencies.mjs",
                "producerSHA256": hashlib.sha256((repository / "Scripts/Expo/prepare-ios-dependencies.mjs").read_bytes()).hexdigest(),
                "classifierSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "metadataToolSourceSHA256": hashlib.sha256(build_tool.read_bytes()).hexdigest(),
                "metadataDeclarationPolicySource": INCOMPLETE_RECORD_POLICY_SOURCE,
                "dependencyLockSHA256": hashlib.sha256((repository / "Scripts/Expo/dependency-lock.json").read_bytes()).hexdigest(),
                "compilerLibrarySHA256": hashlib.sha256(library.read_bytes()).hexdigest(),
                "originRoot": str(directory.resolve()), "compilerArguments": arguments,
                "workingDirectory": str(Path.cwd().resolve()), "compilerEnvironmentSHA256": compiler_environment_sha256(),
                "frameworks": records}
    (receipt_path or directory / ROLE_MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def verified_framework_roles(directory: Path, compiler_arguments: list[str] | None = None, receipt_path: Path | None = None) -> dict:
    path = receipt_path or directory / ROLE_MANIFEST
    if not path.is_file():
        return {}
    manifest = json.loads(path.read_text(encoding="utf-8"))
    repository = Path(__file__).resolve().parents[2]
    if manifest.get("schemaVersion") != 2 or not re.fullmatch(r"[0-9a-f]{64}", manifest.get("compilerLibrarySHA256", "")) or \
       manifest.get("producer") != "Scripts/Expo/prepare-ios-dependencies.mjs" or \
       manifest.get("producerSHA256") != hashlib.sha256((repository / "Scripts/Expo/prepare-ios-dependencies.mjs").read_bytes()).hexdigest() or \
       manifest.get("classifierSHA256") != hashlib.sha256(Path(__file__).read_bytes()).hexdigest() or \
       manifest.get("metadataToolSourceSHA256") != hashlib.sha256((repository / "Scripts/NativeScript/build-metadata-tool.py").read_bytes()).hexdigest() or \
       manifest.get("metadataDeclarationPolicySource") != INCOMPLETE_RECORD_POLICY_SOURCE or \
       manifest.get("dependencyLockSHA256") != hashlib.sha256((repository / "Scripts/Expo/dependency-lock.json").read_bytes()).hexdigest():
        raise RuntimeError("Framework input-role producer provenance mismatch")
    roles = {}
    for record in manifest["frameworks"]:
        framework = directory / record["relativePath"]
        if framework.parent.resolve() != directory.resolve() or framework.name != record["framework"]:
            raise RuntimeError("Framework input-role path/identity mismatch")
        module_map = framework / "Modules/module.modulemap"
        modules = module_names(module_map.read_text(encoding="utf-8")) if module_map.is_file() else []
        if record["role"] not in {PUBLIC_ROLE, CPP_ROLE} or framework.name in roles or \
           record["inputSHA256"] != framework_inputs(framework) or modules != record["modules"]:
            raise RuntimeError("Framework input-role identity/headers changed: " + framework.name)
        proof = record["proof"]
        if any(d.get("header") not in record["inputSHA256"] for d in proof.get("declarations", [])):
            raise RuntimeError("Framework input-role proof refers to an unowned header")
        if record["role"] == CPP_ROLE:
            arguments = manifest["compilerArguments"]
            verify_role_context(arguments, compiler_arguments)
            if manifest.get("workingDirectory") != str(Path.cwd().resolve()):
                raise RuntimeError("Framework input-role working directory changed")
            if manifest.get("compilerEnvironmentSHA256") != compiler_environment_sha256():
                raise RuntimeError("Framework input-role compiler environment changed")
            objc = proof.get("objcCompatibility", {})
            if not complete_language_proof(proof, "objective-c++", arguments) or proof.get("role") != CPP_ROLE or declaration_role(proof["declarations"]) != CPP_ROLE:
                raise RuntimeError("Framework input-role contains incomplete/supported/mixed or unknown declarations: " + framework.name)
            if not complete_language_proof(objc, "objective-c", arguments) or any(d["category"] not in {"cpp", "inert"} for d in objc["declarations"]):
                raise RuntimeError("Framework input-role lacks a complete ObjC compatibility audit: " + framework.name)
            for audit in [proof, objc]:
                if any(d.get("header") not in record["inputSHA256"] for d in audit["declarations"]):
                    raise RuntimeError("Framework input-role audit refers to an unowned header")
                for name, digest in audit["dependencies"].items():
                    dependency = Path(name)
                    if not dependency.is_file() or hashlib.sha256(dependency.read_bytes()).hexdigest() != digest:
                        raise RuntimeError("Framework input-role parser dependency changed: " + name)
        roles[framework.name] = record
    return roles


def framework_inputs(framework: Path) -> dict:
    # Compare every reachable header, not just the entry header: an unchanged
    # umbrella can include a changed declaration in a sibling/private header.
    files = [p for directory in ["Headers", "PrivateHeaders", "Modules"]
             for p in (framework / directory).rglob("*")
             if p.is_file() and (directory != "Modules" or p.suffix == ".modulemap")]
    return {p.relative_to(framework).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(files)}


def module_names(module_text: str) -> list[str]:
    # Only top-level modules own a framework; nested submodules are not global
    # identities. Strip comments before counting braces in the module map.
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', module_text, flags=re.DOTALL)
    depth = 0
    names = []
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|\b(extern\s+)?module\s+([A-Za-z_]\w*(?:\.\w+)*)|[{}]', text):
        if token.group(2) and not token.group(1) and depth == 0:
            names.append(token.group(2))
        elif token.group() == "{":
            depth += 1
        elif token.group() == "}":
            depth -= 1
    return names


def write_verified_header_alias_overlay(inventory: list[dict], destination: Path) -> list[dict]:
    """Give identical module-qualified header copies their existing owner.

    -I/-F order and bytes stay intact. Clang's pragma-once identity and module
    lookup use the real canonical file through a documented VFS alias.
    """
    aliases = {}
    evidence = {}
    verified_trees = {}
    for owner in inventory:
        if owner["status"] != "SELECTED":
            continue
        for header in owner["publicUmbrellaHeaders"]:
            canonical = Path(header["path"])
            relative = canonical.relative_to(Path(owner["path"]) / "Headers").as_posix()
            for module in owner["modules"]:
                key = "Headers/" + module + "/" + relative
                for carrier in inventory:
                    if carrier["path"] == owner["path"] or key not in carrier["inputSHA256"]:
                        continue
                    alias = Path(carrier["path"]) / key
                    if carrier["inputSHA256"][key] != header["sha256"]:
                        raise RuntimeError("Conflicting public header alias bytes: " + str(alias) + " vs " + str(canonical))
                    pair = (owner["path"], module, carrier["path"])
                    if pair not in verified_trees:
                        # Identical entry bytes are insufficient if a relative
                        # include would pick up a changed sibling declaration.
                        if any(k.startswith("PrivateHeaders/") for k in owner["inputSHA256"]):
                            raise RuntimeError("Public header alias private dependency context is not proven: " + str(alias))
                        tree = {k[len("Headers/"):]: v for k, v in owner["inputSHA256"].items() if k.startswith("Headers/")}
                        prefix = "Headers/" + module + "/"
                        if any(carrier["inputSHA256"].get(prefix + name) != digest for name, digest in tree.items()):
                            raise RuntimeError("Conflicting public header alias dependency tree: " + str(alias))
                        verified_trees[pair] = {"files": len(tree), "sha256": hashlib.sha256(json.dumps(tree, sort_keys=True).encode()).hexdigest()}
                    alias_name, target = alias.as_posix(), canonical.as_posix()
                    if alias_name in aliases and aliases[alias_name] != target:
                        raise RuntimeError("Conflicting public header alias owners: " + alias_name)
                    aliases[alias_name] = target
                    evidence[alias_name] = {"module": module, "alias": alias_name, "canonical": target,
                                            "sha256": header["sha256"], "ownerSearchPriority": owner["searchPriority"],
                                            "matchingOwnerHeaderTree": verified_trees[pair]}
    if any(target in aliases and aliases[target] != target for target in aliases.values()):
        raise RuntimeError("Public header aliases would replace another selected module owner")
    destination.write_text(json.dumps({"version": 0, "use-external-names": True,
        "roots": [{"type": "file", "name": alias, "external-contents": target} for alias, target in sorted(aliases.items())]}, indent=2) + "\n", encoding="utf-8")
    records = [evidence[alias] for alias in sorted(evidence)]
    destination.with_suffix(".evidence.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    return records


def write_public_umbrella(sdk: Path, destination: Path, extra_headers: list[Path],
                          framework_search_paths: list[Path] | None = None, role_receipts: dict | None = None,
                          compiler_arguments: list[str] | None = None) -> list[dict]:
    inventory = []
    public_headers = []
    # SubFrameworks is an include-search dependency, not another public root.
    # Importing its FocusEngine headers directly duplicates UIKit declarations
    # even with the selected Xcode clang. UIKit imports its own dependencies.
    # Clang searches explicit -F paths in order before the SDK's standard root.
    # Resolving/sorting all paths together destroys that ownership priority.
    framework_roots = [*(framework_search_paths or []), sdk / "System/Library/Frameworks"]
    seen_paths = set()
    owners = {}
    for priority, directory in enumerate(framework_roots):
        if directory.resolve() == (sdk / "System/Library/SubFrameworks").resolve():
            continue
        receipt = (role_receipts or {}).get(str(directory.resolve()))
        roles = verified_framework_roles(directory, compiler_arguments, receipt)
        for candidate in sorted(directory.glob("*.framework")):
            framework = candidate.resolve()
            if framework in seen_paths:
                continue
            seen_paths.add(framework)
            module_map = framework / "Modules/module.modulemap"
            module_text = module_map.read_text() if module_map.is_file() else ""
            modules = module_names(module_text)
            identities = ["framework:" + framework.name, *("module:" + name for name in modules)]
            inputs = framework_inputs(framework)
            record = {"framework": framework.name, "path": str(framework),
                      "searchPath": str(directory), "searchPriority": priority,
                      "modules": modules, "inputSHA256": inputs,
                      "inputManifestSHA256": hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest(),
                      "moduleMapSHA256": hashlib.sha256(module_map.read_bytes()).hexdigest() if module_map.is_file() else None,
                      "publicUmbrellaHeaders": []}
            previous = [owners[identity] for identity in identities if identity in owners]
            if previous:
                owner = previous[0]
                equal = all(p is owner for p in previous) and inputs == owner["inputSHA256"]
                record.update({"status": "DEDUPLICATED_IDENTICAL" if equal else "CONFLICT",
                               "selectedFrameworkPath": owner["path"]})
                inventory.append(record)
                if not equal:
                    # Retain both manifests even on failure, before the wrapper's
                    # temporary module directory is removed.
                    destination.with_suffix(".inventory.json").write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
                    raise RuntimeError("Conflicting framework/module headers: " + owner["path"] + " vs " + str(framework))
                for identity in identities:
                    owners[identity] = owner
                continue
            record["status"] = "SELECTED"
            for identity in identities:
                owners[identity] = record
            role = roles.get(candidate.name)
            if role is not None:
                record["inputRole"] = role["role"]
                record["inputRoleProof"] = role["proof"]
                record["roleManifestSHA256"] = hashlib.sha256((receipt or directory / ROLE_MANIFEST).read_bytes()).hexdigest()
                if role["role"] == CPP_ROLE:
                    record["status"] = "INCLUDE_SEARCH_ONLY_CPP"
                    inventory.append(record)
                    continue
            header_root = framework / "Headers"
            names = re.findall(r'umbrella\s+header\s+"([^"]+)"', module_text)
            found = [header_root / name for name in names if (header_root / name).is_file()]
            if not found and module_map.is_file():
                # Explicit module-map headers are the authoritative public
                # roots. A same-named convenience header need not include them
                # all, and a case-insensitive filesystem may accept "yoga.h"
                # where the module owns "Yoga.h", losing module ownership.
                names = re.findall(r'^\s*(?:textual\s+)?header\s+"([^"]+)"', module_text, re.MULTILINE)
                found = [header_root / name for name in names if (header_root / name).is_file()]
            if not found and module_map.is_file():
                named = header_root / f"{framework.stem}.h"
                if named.is_file():
                    found = [named]
                elif re.search(r'umbrella\s+"', module_text):
                    private = re.findall(r'private\s+header\s+"([^"]+)"', module_text)
                    found = [p for p in sorted(header_root.glob("*.h"))
                             if not p.name.endswith("-Swift.h") and p.name not in private]
            public_headers.extend(found)
            record["publicUmbrellaHeaders"] = [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in found]
            inventory.append(record)
    if not public_headers:
        raise RuntimeError("Selected SDK has no public framework entry headers")
    headers = public_headers + extra_headers
    if any(not p.is_file() for p in headers):
        raise RuntimeError("Actual metadata input header missing")
    destination.write_text('#import <UIKit/UIKit.h>\n' + "\n".join('#import "' + str(p) + '"' for p in headers) + "\n", encoding="utf-8")
    destination.with_suffix(".inventory.json").write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
    return inventory


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--produce-roles", type=Path, required=True)
    parser.add_argument("--library", type=Path)
    parser.add_argument("--target")
    args = parser.parse_args()
    if sys.platform != "darwin" and args.library is None:
        raise SystemExit("Actual installed compiler library is required for framework-role inspection")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    clang = Path(subprocess.check_output(["xcrun", "--find", "clang"], text=True).strip()).resolve()
    library = args.library or clang.parent.parent / "lib/libclang.dylib"
    target = args.target
    if target:
        canonical_target(target)
    compiler_args = ["-isysroot", sdk, *(["-target", target] if target else []),
                     "-F" + str(args.produce_roles), "-I" + str(args.produce_roles / "react.framework/Headers")]
    manifest = produce_role_inventory(args.produce_roles, compiler_args, library, classify=bool(target))
    print(json.dumps({"roles": {r["framework"]: r["role"] for r in manifest["frameworks"]}}))
