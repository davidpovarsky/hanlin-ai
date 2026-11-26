#!/usr/bin/env python3
"""Install a pinned selected-product Hanlin SDK checkout for an original host."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import subprocess
import sys
import tempfile

REPOSITORY_URL = "https://github.com/davidpovarsky/hanlin-ai.git"
GENERATED = ("Package.swift", "docs/agent-sdk/unified-package-manifest.json")
RECEIPT = ".hanlin-sdk/installation.json"
APP_INTENTS_HOST_RESOURCES = "Packages/HanlinWidgetSDK/HostResources"
# Read canonical manifests and graph metadata before materializing product sources.
# Non-cone patterns deliberately exclude unrelated app resources and native blobs.
BOOTSTRAP_PATTERNS = (
    "/.gitignore", "/.gitattributes", "/Package.swift",
    "/Scripts/SDK/", "/Scripts/CI/IntegrationValidation/project_graph.py",
    "/Scripts/ProductSplit/extension_inventory.py",
    "/Packages/*/Package.swift", "/AI_HLY.xcodeproj/project.pbxproj",
    "/AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    "/docs/agent-sdk/unified-package-manifest.json", "/docs/native-artifacts.json",
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def run(arguments: list[str], *, cwd: Path | None = None, input_text: str | None = None) -> str:
    result = subprocess.run(arguments, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, input=input_text, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or
                           f"{arguments[0]} failed with exit {result.returncode}")
    return result.stdout.rstrip("\n")


def git(root: Path, *arguments: str) -> str:
    return run(["git", "-C", str(root), *arguments])


def read_lock(path: Path) -> dict:
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError("HanlinSDK.lock.json must be an object")
    revision = value.get("revision", "")
    products = value.get("products")
    if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("HanlinSDK.lock.json requires a full immutable 40-character commit revision")
    if not isinstance(products, list) or not products:
        raise ValueError("HanlinSDK.lock.json requires a nonempty products array")
    if not all(isinstance(name, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name) for name in products):
        raise ValueError("SDK products must be exact public product names")
    if len(set(products)) != len(products):
        raise ValueError("SDK product selection contains duplicate names")
    return {"revision": revision, "products": products}


def destination_path(host: Path, relative: str) -> Path:
    path = PurePosixPath(relative)
    if path.is_absolute() or "\\" in relative or any(part in ("", ".", "..") for part in relative.split("/")):
        raise ValueError("The SDK destination must be a directory inside the host")
    destination = host / path
    if not destination.resolve().is_relative_to(host.resolve()):
        raise ValueError("The SDK destination escapes the host")
    return destination


def default_cache() -> Path:
    if platform.system() == "Darwin":
        return Path.home() / "Library/Caches/HanlinSDK/native"
    return Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "hanlin-sdk/native"


def generated_hashes(root: Path) -> dict[str, str]:
    return {name: sha256(root / name) for name in GENERATED if (root / name).is_file()}


def native_artifact_tools():
    spec = importlib.util.spec_from_file_location("hanlin_native_ownership", Path(__file__).with_name("native_artifacts.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_owned_changes(root: Path, receipt: dict | None) -> None:
    """Only unchanged installer-generated output may be reset during an upgrade."""
    records = git(root, "status", "--porcelain=v1", "-z", "--untracked-files=normal").split("\0")
    native_owned = None
    for record in records:
        if not record:
            continue
        status, path = record[:2], record[3:]
        if "R" in status or "C" in status:
            raise ValueError(f"SDK checkout has an actual source edit; preserve it before installing: {path}")
        if path not in GENERATED:
            if native_owned is None:
                native_owned = native_artifact_tools().managed_source_outputs(root)
            if path in native_owned:
                continue
            raise ValueError(f"SDK checkout has an actual source edit; preserve it before installing: {path}")
        expected = (receipt or {}).get("generatedSHA256", {}).get(path)
        if not expected or not (root / path).is_file() or sha256(root / path) != expected:
            raise ValueError(f"Generated SDK file was edited outside the installer: {path}")


def reset_generated(root: Path) -> None:
    native = native_artifact_tools()
    owned = native.managed_source_outputs(root)
    for name in (*GENERATED, *owned):
        tracked = subprocess.run(["git", "-C", str(root), "ls-files", "--error-unmatch", "--", name],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if tracked:
            extra = ["--ignore-skip-worktree-bits"] if name in owned else []
            git(root, "restore", "--source=HEAD", "--staged", "--worktree", *extra, "--", name)
        elif (root / name).is_file():
            (root / name).unlink()
    if owned:
        path = root / ".hanlin-sdk/native-artifacts-installed.json"
        receipt = json.loads(path.read_text())
        receipt["paths"].pop(native.WIDGET_RUNTIME_ROOT, None)
        receipt.pop("preparedSourceSHA256", None)
        write_json(path, receipt)


def ignore_checkout(host: Path, destination: Path) -> None:
    relative = destination.relative_to(host).as_posix()
    ignored = subprocess.run(["git", "-C", str(host), "check-ignore", "--quiet", "--", relative + "/"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if not ignored:
        ignore = host / ".gitignore"
        text = ignore.read_text() if ignore.exists() else ""
        line = f"/{relative}/"
        if line not in text.splitlines():
            ignore.write_text(text + ("" if not text or text.endswith("\n") else "\n") + line + "\n")
    # Receipts describe generated installation state, never a fork of SDK sources.
    exclude = Path(git(destination, "rev-parse", "--git-path", "info/exclude"))
    if not exclude.is_absolute():
        exclude = destination / exclude
    exclude.parent.mkdir(parents=True, exist_ok=True)
    text = exclude.read_text() if exclude.exists() else ""
    if "/.hanlin-sdk/" not in text.splitlines():
        exclude.write_text(text + ("" if not text or text.endswith("\n") else "\n") + "/.hanlin-sdk/\n")


def repository_identity(value: str) -> str:
    if value.startswith("git@github.com:"):
        value = "https://github.com/" + value.removeprefix("git@github.com:")
    return value.rstrip("/").removesuffix(".git")


def has_commit(root: Path, revision: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", revision + "^{commit}"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def sparse_checkout(root: Path, patterns: list[str] | tuple[str, ...], *, materialize: bool) -> None:
    if materialize:
        run(["git", "-C", str(root), "sparse-checkout", "set", "--no-cone", "--stdin"],
            input_text="\n".join(patterns) + "\n")
    else:
        # Configure before the first checkout, so a blob-filtered clone never
        # downloads or writes unrelated native/app files even temporarily.
        git(root, "config", "core.sparseCheckout", "true")
        git(root, "config", "core.sparseCheckoutCone", "false")
        path = Path(git(root, "rev-parse", "--git-path", "info/sparse-checkout"))
        if not path.is_absolute():
            path = root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(patterns) + "\n")


def selected_source_paths(root: Path, description: dict) -> list[str]:
    paths = set()
    for target in description["targets"]:
        if target["type"] == "binary":
            continue
        default = ("Tests/" if target["type"] == "test" else "Sources/") + target["name"]
        path = target.get("path") or default
        resolved = (root / path).resolve()
        if not resolved.is_relative_to(root.resolve()) or resolved == root.resolve():
            raise ValueError(f"Unsupported canonical target path: {path}")
        paths.add(resolved.relative_to(root.resolve()).as_posix())
        # SwiftPM permits relative header directories outside the target root.
        for setting in target.get("settings", []):
            relative = setting.get("kind", {}).get("headerSearchPath", {}).get("_0")
            if relative:
                header = (resolved / relative).resolve()
                if not header.is_relative_to(root.resolve()) or header == root.resolve():
                    raise ValueError(f"Header search path escapes the selected SDK sources: {relative}")
                paths.add(header.relative_to(root.resolve()).as_posix())
    if any(target["name"] in {"TNSWidgets", "NSCWinterTC"} for target in description["targets"]):
        # The original packaged metadata launcher imports these canonical helpers.
        paths.update(("Scripts/NativeScript/metadata_public_headers.py",
                      "Scripts/NativeScript/build-metadata-tool.py"))
    if any(target["name"] == "HanlinScriptingWidgets" for target in description["targets"]):
        # AppIntents indexes this canonical table in the host main bundle.
        paths.add(APP_INTENTS_HOST_RESOURCES)
    return sorted(paths)


def source_patterns(paths: list[str]) -> list[str]:
    # An anchored directory pattern also includes its entire original resource tree.
    patterns = list(BOOTSTRAP_PATTERNS)
    for path in paths:
        escaped = "".join(chr(92) + character if character in "\\*?[]" else character for character in path)
        patterns.append("/" + escaped + ("" if path.endswith(".py") else "/"))
    return list(dict.fromkeys(patterns))


def prepare_checkout(host: Path, lock: dict, relative: str, repository: str = REPOSITORY_URL,
                     source_cache: Path | None = None) -> tuple[Path, dict | None]:
    destination = destination_path(host, relative)
    if source_cache:
        source_cache = source_cache.resolve(strict=True)
        if repository_identity(git(source_cache, "remote", "get-url", "origin")) != repository_identity(repository):
            raise ValueError("The shared Git cache must belong to the canonical Hanlin repository")
    receipt = None
    if destination.exists():
        if not (destination / ".git").exists():
            raise ValueError(f"SDK destination contains unmanaged files: {destination}")
        if repository_identity(git(destination, "remote", "get-url", "origin")) != repository_identity(repository):
            raise ValueError("SDK destination is not the canonical Hanlin repository")
        receipt_path = destination / RECEIPT
        receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
        verify_owned_changes(destination, receipt)
        reset_generated(destination)
        sparse_checkout(destination, BOOTSTRAP_PATTERNS, materialize=True)
        if git(destination, "rev-parse", "HEAD") != lock["revision"]:
            if not has_commit(destination, lock["revision"]):
                git(destination, "fetch", "--no-tags", "--depth=1", "origin", lock["revision"])
            git(destination, "checkout", "--detach", lock["revision"])
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".hanlin-sdk-clone-", dir=destination.parent) as temporary:
            checkout = Path(temporary) / "checkout"
            if source_cache:
                run(["git", "clone", "--shared", "--no-checkout", str(source_cache), str(checkout)])
                git(checkout, "remote", "set-url", "origin", repository)
            else:
                run(["git", "clone", "--filter=blob:none", "--no-checkout", repository, str(checkout)])
            if not has_commit(checkout, lock["revision"]):
                git(checkout, "fetch", "--no-tags", "--depth=1", "origin", lock["revision"])
            sparse_checkout(checkout, BOOTSTRAP_PATTERNS, materialize=False)
            git(checkout, "checkout", "--detach", lock["revision"])
            if git(checkout, "rev-parse", "HEAD") != lock["revision"]:
                raise ValueError("Fetched SDK revision does not match the host lock")
            checkout.rename(destination)
    if git(destination, "rev-parse", "HEAD") != lock["revision"]:
        raise ValueError("Installed SDK revision does not match the host lock")
    ignore_checkout(host, destination)
    return destination, receipt


def generate_profile(root: Path, products: list[str]) -> dict:
    generator = root / "Scripts/SDK/generate_manifest.py"
    if not generator.is_file():
        raise ValueError("Pinned source does not contain the shared SDK manifest generator")
    try:
        run([sys.executable, str(generator), "--products", *products], cwd=root)
        description = json.loads(run(["swift", "package", "--package-path", str(root), "dump-package"]))
        declared = {item["name"] for item in description["products"]}
        if declared != set(products):
            raise ValueError(f"Generated product closure differs from the host lock: {sorted(declared)}")
        return description
    except Exception:
        # These two files were verified as installer-owned before generation.
        reset_generated(root)
        raise


def install(host: Path, lock_path: Path, destination: str, cache: Path,
            *, repository: str = REPOSITORY_URL, source_cache: Path | None = None) -> dict:
    host = host.resolve(strict=True)
    lock = read_lock(lock_path)
    root, _ = prepare_checkout(host, lock, destination, repository, source_cache)
    receipt = {"schemaVersion": 1, "repository": repository, "revision": lock["revision"],
               "products": lock["products"], "state": "source-ready",
               "generatedSHA256": generated_hashes(root)}
    write_json(root / RECEIPT, receipt)
    description = generate_profile(root, lock["products"])
    # Generation already changed the two managed outputs. Persist their exact
    # ownership before path validation or sparse source fetching can fail, so an
    # interrupted installation remains retryable without admitting manual edits.
    receipt["generatedSHA256"] = generated_hashes(root)
    receipt["state"] = "profile-generated"
    write_json(root / RECEIPT, receipt)
    paths = selected_source_paths(root, description)
    patterns = source_patterns(paths)
    sparse_checkout(root, patterns, materialize=True)
    if any(target["name"] == "AI_Hanlin" for target in description["targets"]):
        # The full application manifest inventories its original Swift/resource
        # files. Regenerate only after this selected source tree is materialized.
        description = generate_profile(root, lock["products"])
    if APP_INTENTS_HOST_RESOURCES in paths:
        run([sys.executable, str(root / "Scripts/SDK/generate_app_intents_resources.py"), "--check"], cwd=root)
    receipt["checkoutMode"] = "sparse"
    receipt["sourcePaths"] = paths
    receipt["sparsePatterns"] = patterns
    receipt["generatedSHA256"] = generated_hashes(root)
    receipt["state"] = "profile-ready"
    binary_targets = [item for item in description["targets"] if item["type"] == "binary"]
    receipt["binaryTargets"] = [item["name"] for item in binary_targets]
    write_json(root / RECEIPT, receipt)
    managed_targets = []
    if binary_targets:
        catalog_path = root / "docs/native-artifacts.json"
        catalog = json.loads(catalog_path.read_text())
        managed = set(catalog["requiredTargets"])
        managed_targets = [item["name"] for item in binary_targets if item["name"] in managed]
        for item in binary_targets:
            if item["name"] not in managed and not item.get("url"):
                raise ValueError(f"Selected native target has no published artifact handler: {item['name']}")
        if managed_targets:
            run([sys.executable, str(root / "Scripts/SDK/native_artifacts.py"), "install",
                 "--catalog", str(catalog_path), "--root", str(root), "--cache", str(cache),
                 "--targets", *managed_targets], cwd=root)
    receipt["managedNativeTargets"] = managed_targets
    receipt["state"] = "installed"
    receipt["packageName"] = description["name"]
    receipt["hostRelativePath"] = destination
    write_json(root / RECEIPT, receipt)
    return receipt


def check(host: Path, lock_path: Path, relative: str) -> dict:
    lock = read_lock(lock_path)
    root = destination_path(host.resolve(strict=True), relative)
    receipt = json.loads((root / RECEIPT).read_text())
    verify_owned_changes(root, receipt)
    if (receipt["state"] != "installed" or receipt["revision"] != lock["revision"]
            or receipt["products"] != lock["products"] or git(root, "rev-parse", "HEAD") != lock["revision"]
            or generated_hashes(root) != receipt["generatedSHA256"]):
        raise ValueError("SDK installation does not match the host lock and generated profile")
    if APP_INTENTS_HOST_RESOURCES in receipt.get("sourcePaths", []):
        run([sys.executable, str(root / "Scripts/SDK/generate_app_intents_resources.py"), "--check"], cwd=root)
    # Check that managed native installation paths still exist without a download.
    if receipt.get("managedNativeTargets"):
        validation = json.loads(run([sys.executable, str(root / "Scripts/SDK/native_artifacts.py"), "verify-source",
             "--catalog", str(root / "docs/native-artifacts.json"), "--root", str(root),
             "--targets", *receipt["managedNativeTargets"]], cwd=root))
        catalog = json.loads((root / "docs/native-artifacts.json").read_text())
        native_receipt = json.loads((root / ".hanlin-sdk/native-artifacts-installed.json").read_text())
        # Use the same canonical dependency closure as installation, including
        # newly declared support dependencies in older full catalogs.
        selected = set(validation["selectedRecords"])
        records = [item for item in [*catalog["artifacts"], *catalog["supportArtifacts"]]
                   if item["target"] in selected]
        for item in records:
            paths = [item["installPath"]] if item["kind"] == "xcframework" else item["installPaths"]
            if any(native_receipt["paths"].get(path) != item["checksum"] or not (root / path).exists() for path in paths):
                raise ValueError("Managed native installation is incomplete; run the installer again")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-root", type=Path, required=True)
    parser.add_argument("--lock", type=Path, help="Default: HOST/HanlinSDK.lock.json")
    parser.add_argument("--destination", default="Vendor/HanlinSDK")
    parser.add_argument("--cache", type=Path, default=default_cache())
    parser.add_argument("--source-cache", type=Path, help="Borrow objects from an existing canonical Git checkout/mirror; keep it available")
    parser.add_argument("--check", action="store_true", help="Read-only installation/lock/profile check; no builds or downloads")
    args = parser.parse_args()
    lock_path = args.lock or args.host_root / "HanlinSDK.lock.json"
    result = (check(args.host_root, lock_path, args.destination) if args.check else
              install(args.host_root, lock_path, args.destination, args.cache, source_cache=args.source_cache))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, RuntimeError) as error:
        raise SystemExit(f"Hanlin SDK installation: {error}") from error
