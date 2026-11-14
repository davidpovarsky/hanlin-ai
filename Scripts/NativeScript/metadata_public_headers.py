"""Public framework entry headers shared by SDK probes and the app metadata phase."""
import hashlib
import json
from pathlib import Path
import re


def write_public_umbrella(sdk: Path, destination: Path, extra_headers: list[Path],
                          framework_search_paths: list[Path] | None = None) -> list[dict]:
    inventory = []
    public_headers = []
    # SubFrameworks is an include-search dependency, not another public root.
    # Importing its FocusEngine headers directly duplicates UIKit declarations
    # even with the selected Xcode clang. UIKit imports its own dependencies.
    framework_roots = [sdk / "System/Library/Frameworks", *(framework_search_paths or [])]
    frameworks = sorted({p.resolve() for directory in framework_roots
                         if directory.resolve() != (sdk / "System/Library/SubFrameworks").resolve()
                         for p in directory.glob("*.framework")})
    for framework in frameworks:
        module_map = framework / "Modules/module.modulemap"
        module_text = module_map.read_text() if module_map.is_file() else ""
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
        inventory.append({"framework": framework.name,
                          "moduleMapSHA256": hashlib.sha256(module_map.read_bytes()).hexdigest() if module_map.is_file() else None,
                          "publicUmbrellaHeaders": [{"path": str(p), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in found]})
    if not public_headers:
        raise RuntimeError("Selected SDK has no public framework entry headers")
    headers = public_headers + extra_headers
    if any(not p.is_file() for p in headers):
        raise RuntimeError("Actual metadata input header missing")
    destination.write_text('#import <UIKit/UIKit.h>\n' + "\n".join('#import "' + str(p) + '"' for p in headers) + "\n", encoding="utf-8")
    destination.with_suffix(".inventory.json").write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")
    return inventory
