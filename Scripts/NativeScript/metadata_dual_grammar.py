"""Bound requests and verification for the opt-in, retained dual AST producer."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import uuid


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def objc_arguments(full: list[str], standard_library: str) -> list[str]:
    result = []
    index = 0
    while index < len(full):
        argument = full[index]
        if argument in {"-x", "-std"}:
            index += 1
            if index == len(full):
                raise RuntimeError("Incomplete dual grammar argument")
        elif not argument.startswith("-std="):
            result.append(argument)
        index += 1
    return [*result, "-x", "objective-c", "-std=gnu17", "-isystem", standard_library]


def create_request(destination: Path, full_root: Path, objc_root: Path, context: dict,
                   sdk: Path, bound_paths: list[Path]) -> dict:
    standard_library = sdk / "usr/include/c++/v1"
    if not standard_library.is_dir():
        raise RuntimeError("Actual SDK C++ standard-library directory is missing")
    paths = sorted({path.resolve(strict=True) for path in [full_root, objc_root, *bound_paths]})
    request = {"schemaVersion": 2, "mergePolicyVersion": 2, "aliasPolicyVersion": 2,
        "mode": "retained-dual-grammar", "nonce": str(uuid.uuid4()),
        "fullRootSHA256": sha(full_root), "objcRoot": str(objc_root.resolve(strict=True)),
        "objcRootSHA256": sha(objc_root), "contextSHA256": context["contextSHA256"],
        "generatorSHA256": context["generatorSHA256"],
        "standardLibraryDirectory": str(standard_library.resolve(strict=True)),
        "fullArguments": context["arguments"],
        "boundFiles": [{"path": str(path), "sha256": sha(path)} for path in paths]}
    with destination.open("x", encoding="utf-8", newline="\n") as file:
        json.dump(request, file, indent=2)
        file.write("\n")
    return request


def validate_receipt(binary: Path, request_path: Path, context: dict, tool: Path) -> dict:
    request = json.loads(request_path.read_text(encoding="utf-8"))
    receipt_path = binary.with_name(binary.name + ".dual-grammar.json")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if receipt.get("schemaVersion") != 2 or receipt.get("mergePolicyVersion") != 2 or \
       receipt.get("status") != "COMPLETE" or receipt.get("mode") != "retained-dual-grammar" or \
       receipt.get("requestSHA256") != sha(request_path) or receipt.get("contextSHA256") != context["contextSHA256"] or \
       request.get("generatorSHA256") != sha(tool) or request.get("generatorSHA256") != context["generatorSHA256"]:
        raise RuntimeError("Incomplete or stale dual grammar result identity")
    proof = receipt["proof"]
    cpp, objc = proof["cpp"], proof["objc"]
    if proof.get("mergePolicyVersion") != 2 or cpp["language"] != "objective-c++" or objc["language"] != "objective-c" or \
       cpp["arguments"] != context["arguments"] or cpp["rootSHA256"] != request["fullRootSHA256"] or \
       objc["rootSHA256"] != request["objcRootSHA256"] or objc["arguments"] != objc_arguments(context["arguments"], request["standardLibraryDirectory"]):
        raise RuntimeError("Actual dual grammar roots or argument vectors differ")
    if any(cpp[key] != objc[key] for key in ["compiler", "target", "resourceDirectory", "actualSearchDirectories"]) or \
       cpp["compiler"] != context["compiler"] or any(unit.get("diagnosticErrorCount") != 0 for unit in [cpp, objc]):
        raise RuntimeError("Actual dual compiler/search/diagnostic context is unproven")
    for bound in request["boundFiles"]:
        if sha(Path(bound["path"])) != bound["sha256"]:
            raise RuntimeError("Bound dual grammar input changed during generation")
    for unit in [cpp, objc]:
        if not unit["sourceDependencies"]:
            raise RuntimeError("Actual source dependency closure is empty")
        if any(sha(Path(path)) != digest for path, digest in unit["sourceDependencies"].items()):
            raise RuntimeError("Actual parsed dependency changed after serialization")
    if receipt.get("consumerEntries") != 2 or receipt.get("cacheReuse") != "DISABLED" or \
       not receipt.get("lifetime", {}).get("bothSourceManagersReadAfterSerialization"):
        raise RuntimeError("Retained dual AST execution or lifetime is unproven")
    destinations = receipt["destinations"]
    if Path(destinations["binary"]).resolve() != binary.resolve() or receipt.get("metadataSHA256") != sha(binary):
        raise RuntimeError("Dual metadata binary identity mismatch")
    seen = set()
    for output in receipt["outputs"]:
        relative = Path(output["path"])
        if relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise RuntimeError("Invalid dual output manifest path")
        if relative.as_posix() == "metadata.bin":
            path = binary
        elif relative.as_posix() == "umbrella.h":
            path = Path(destinations["umbrella"])
        elif relative.parts[0] in {"yaml", "types"} and len(relative.parts) > 1:
            base = Path(destinations[relative.parts[0]])
            path = base.joinpath(*relative.parts[1:])
            if not path.resolve().is_relative_to(base.resolve()):
                raise RuntimeError("Dual output escapes its declared destination")
        else:
            raise RuntimeError("Unknown dual output manifest member")
        if path.is_symlink() or not path.is_file() or path in seen or sha(path) != output["sha256"] or path.stat().st_size != output["bytes"]:
            raise RuntimeError("Dual serialized output is missing, duplicated or changed")
        seen.add(path)
    if binary not in seen:
        raise RuntimeError("Dual result has no authenticated binary output")
    return receipt
