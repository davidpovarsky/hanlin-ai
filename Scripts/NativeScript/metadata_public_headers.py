"""Public framework entry headers shared by SDK probes and the app metadata phase."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re


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


def write_public_umbrella(sdk: Path, destination: Path, extra_headers: list[Path],
                          framework_search_paths: list[Path] | None = None,
                          framework_names: set[str] | None = None) -> list[dict]:
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
        for candidate in sorted(directory.glob("*.framework")):
            if framework_names is not None and candidate.name not in framework_names:
                continue
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
            header_root = framework / "Headers"
            names = re.findall(r'umbrella\s+header\s+"([^"]+)"', module_text)
            found = [header_root / name for name in names if (header_root / name).is_file()]
            if not found and module_map.is_file():
                named = header_root / f"{framework.stem}.h"
                if named.is_file():
                    found = [named]
                elif re.search(r'umbrella\s+"', module_text):
                    private = re.findall(r'private\s+header\s+"([^"]+)"', module_text)
                    found = [p for p in sorted(header_root.glob("*.h"))
                             if not p.name.endswith("-Swift.h") and p.name not in private]
                else:
                    names = re.findall(r'^\s*(?:textual\s+)?header\s+"([^"]+)"', module_text, re.MULTILINE)
                    found = [header_root / name for name in names if (header_root / name).is_file()]
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
