"""Run the original Widget sample producer and bind its derived files.

Only the original producer writes the 24 sample archives and SHA256.json.
Validation recomputes hashes through its original read-only exports; it neither
writes fixtures nor treats a self-consistent replacement archive as authored.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import time

RECEIPT_ENV = "HANLIN_WIDGET_FIXTURE_PRODUCER_RECEIPT"
PRODUCER = "Scripts/Widgets/build-sample-packages.mjs"
MANIFEST = "Fixtures/Widgets/SHA256.json"
MIRRORS = ("Fixtures/Widgets", "AI_HLYUITests/Fixtures",
           "AI_HLYTests/Fixtures/WidgetEngineFixtures.bundle")
CODE_INPUTS = (
    "Scripts/ProductSplit/prepare_widget_fixtures.py",
    "Scripts/CI/Tests/test_widget_fixture_producer.py",
    PRODUCER, "Scripts/Widgets/samples.mjs", "Scripts/Widgets/deterministic-zip.mjs",
    "Scripts/MiniApps/resolve-upstreams.mjs",
    "Scripts/MiniApps/refresh-original-sources.mjs", "Scripts/MiniApps/upstream-fetch.mjs",
)
EFFECTIVE_INPUTS = ("Scripts/Expo/package.json", "Scripts/Expo/package-lock.json",
                    "Scripts/MiniApps/upstream-resolution.json",
                    "build/acceptance/miniapp-upstreams/resolution.json")
VERSIONS = ("@expo/ui", "expo-widgets", "react")
PRODUCER_TIMEOUT = 60
MAX_RECEIPT_AGE = 210 * 60

# This is the original producer's hash/manifest projection, using its exact
# authored sample and ZIP exports. There are no filesystem write operations.
RECIPE = r"""
import {createHash} from 'node:crypto';
import {widgetSamples} from './Scripts/Widgets/samples.mjs';
import {deterministicZip} from './Scripts/Widgets/deterministic-zip.mjs';
const mirrors = ['Fixtures/Widgets', 'AI_HLYUITests/Fixtures', 'AI_HLYTests/Fixtures/WidgetEngineFixtures.bundle'];
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const outputs = {}, hashes = [];
for (const sample of widgetSamples) {
  const bytes = deterministicZip(sample.files), name = `${sample.name}.${sample.extension}`;
  for (const mirror of mirrors) outputs[`${mirror}/${name}`] = {sha256:digest(bytes), bytes:bytes.length};
  hashes.push({archive:name, sha256:digest(bytes), bytes:bytes.length,
    engine:sample.engine, expected:sample.expected,
    sources:Object.fromEntries(Object.entries(sample.files).map(([name,value])=>[name,digest(value)]))});
}
const manifest = Buffer.from(JSON.stringify(hashes, null, 2) + '\n');
outputs['Fixtures/Widgets/SHA256.json'] = {sha256:digest(manifest), bytes:manifest.length};
console.log(JSON.stringify({nodeVersion:process.version, outputs}));
"""


class FixturePreparationError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise FixturePreparationError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def equal_json(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(equal_json(left[key], right[key]) for key in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(equal_json(a, b) for a, b in zip(left, right))
    return left == right


def parse_json(raw):
    def members(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate JSON member: " + key)
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=members,
                      parse_constant=lambda value: (_ for _ in ()).throw(
                          FixturePreparationError("Non-finite JSON: " + value)))


def safe_path(path, root, missing=False):
    root, path = Path(root).resolve(strict=True), Path(path)
    require(path.is_absolute() and path.is_relative_to(root), "Path left its admitted root")
    current = root
    for part in path.relative_to(root).parts:
        require(part not in ("", ".", ".."), "Unsafe path component")
        current /= part
        require(not current.is_symlink(), "Fixture provenance cannot follow symlinks")
    if missing and not path.exists():
        return path
    info = path.stat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size <= 1024**3,
            "Expected one bounded regular file")
    return path


def file_identity(path, root):
    path = safe_path(path, root)
    before = path.stat()
    with path.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    after = path.stat()
    require((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
            (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns), "File changed while hashing")
    return {"sha256": checksum, "bytes": after.st_size}


def git_bytes(root, source, name):
    return subprocess.check_output(["git", "-C", str(root), "show", source + ":" + name], timeout=15)


def source_head(root, source):
    require(isinstance(source, str) and re.fullmatch(r"[0-9a-f]{40}", source), "Exact source SHA required")
    actual = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], timeout=15).decode().strip()
    require(actual == source, "Source checkout changed")


def context(root, source):
    require(os.environ.get("GITHUB_ACTIONS") == "true" and os.environ.get("GITHUB_SHA") == source,
            "The original GitHub source binding is required")
    workspace = os.environ.get("GITHUB_WORKSPACE", "")
    require(workspace and Path(workspace).is_absolute() and Path(workspace).resolve() == root,
            "Wrong actual workspace")
    run, attempt = os.environ.get("GITHUB_RUN_ID", ""), os.environ.get("GITHUB_RUN_ATTEMPT", "")
    require(re.fullmatch(r"[1-9][0-9]*", run) and re.fullmatch(r"[1-9][0-9]*", attempt),
            "The current run and attempt are required")
    return {"runID": run, "runAttempt": attempt}


def evidence_path(root):
    raw = os.environ.get("SPLIT_EVIDENCE", "")
    path = Path(raw)
    require(raw and path.is_absolute() and path.is_relative_to(root), "Original paired evidence root required")
    return path / "widget-fixture-producer"


def node_identity():
    command = shutil.which("node")
    require(command is not None, "Original pinned Node is unavailable")
    path = Path(command).resolve(strict=True)
    value = file_identity(path, path.parent)
    version = subprocess.check_output([str(path), "--version"], timeout=15).decode().strip()
    require(version == "v24.5.0", "The original paired workflow's pinned Node 24.5.0 is required")
    return {"path": str(path), "version": version, **value}


def input_identity(root, source):
    source_head(root, source)
    code = {}
    for name in CODE_INPUTS:
        current = file_identity(root / name, root)
        require(current["sha256"] == digest(git_bytes(root, source, name)), "Modified producer code: " + name)
        code[name] = current
    effective = {name: file_identity(root / name, root) for name in EFFECTIVE_INPUTS}
    package, lock, resolved, applied = [parse_json((root / name).read_bytes()) for name in EFFECTIVE_INPUTS]
    require(type(applied.get("schemaVersion")) is int and applied["schemaVersion"] == 1
            and applied.get("status") == "applied-awaiting-native-build", "Original resolver did not apply successfully")
    require(type(resolved.get("schemaVersion")) is int and resolved["schemaVersion"] == 1
            and all(equal_json(applied.get(key), value) for key, value in resolved.items()), "Effective resolver records differ")
    require(applied.get("packageLockSHA256", {}).get("Expo") == effective[EFFECTIVE_INPUTS[1]]["sha256"],
            "The actual Expo lock differs from the applied resolver")
    for name in VERSIONS:
        version = resolved.get("versions", {}).get("expo", {}).get(name)
        require(isinstance(version, str) and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?", version),
                "The resolver must bind an exact sample dependency")
        require(package.get("dependencies", {}).get(name) == version
                and lock.get("packages", {}).get("", {}).get("dependencies", {}).get(name) == version
                and lock.get("packages", {}).get("node_modules/" + name, {}).get("version") == version,
                "Actual package, lock and resolved sample versions differ: " + name)
    return {"code": code, "effective": effective, "node": node_identity()}


def output_names(root, source):
    rows = parse_json(git_bytes(root, source, MANIFEST))
    require(isinstance(rows, list) and len(rows) == 8, "The original eight sample definitions are required")
    names = [row.get("archive") for row in rows]
    require(all(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9-]+\.(?:hanlinExpo|scripting)", name)
                for name in names) and len(set(names)) == 8, "Invalid original sample inventory")
    return {str(Path(mirror) / name) for mirror in MIRRORS for name in names} | {MANIFEST}


def recipe_identity(root, source, node):
    result = subprocess.run([node["path"], "--input-type=module", "-e", RECIPE], cwd=root,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    require(result.returncode == 0 and len(result.stdout) <= 1024**2,
            "Original read-only sample recipe failed")
    value = parse_json(result.stdout)
    outputs = value.get("outputs")
    require(value.get("nodeVersion") == node["version"] and isinstance(outputs, dict)
            and set(outputs) == output_names(root, source), "Read-only recipe changed its output inventory")
    for row in outputs.values():
        require(isinstance(row, dict) and set(row) == {"bytes", "sha256"}
                and type(row["bytes"]) is int and 0 < row["bytes"] <= 1024**3
                and isinstance(row["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
                "Invalid authored recipe output")
    return outputs


def output_identity(root, names):
    return {name: file_identity(root / name, root) for name in sorted(names)}


def atomic_json(path, value):
    temporary = path.with_name(path.name + ".tmp-" + str(os.getpid()))
    require(not path.exists(), "A producer receipt already exists")
    with temporary.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, sort_keys=True, indent=2)
        stream.write("\n")
    os.replace(temporary, path)


def prepare(root, source, evidence):
    root, evidence = Path(root).resolve(strict=True), Path(evidence)
    github = context(root, source)
    require(evidence == evidence_path(root), "Wrong original paired producer evidence directory")
    # Check every existing ancestor without granting any arbitrary write path.
    safe_path(evidence / "receipt.json", root, missing=True)
    evidence.mkdir(parents=True, exist_ok=False)
    started, clock = time.time(), time.monotonic()
    try:
        before = input_identity(root, source)
        expected = recipe_identity(root, source, before["node"])
        for name in expected:
            safe_path(root / name, root, missing=True)
        argv = ["node", PRODUCER]
        with (evidence / "producer.stdout.log").open("xb") as stdout, (evidence / "producer.stderr.log").open("xb") as stderr:
            result = subprocess.run(argv, cwd=root, stdout=stdout, stderr=stderr, timeout=PRODUCER_TIMEOUT)
        require(result.returncode == 0, "The original producer failed")
        after = input_identity(root, source)
        outputs = output_identity(root, expected)
        require(equal_json(after, before), "Original producer inputs changed during execution")
        require(equal_json(outputs, expected), "Generated outputs differ from the original authored recipe")
        value = {"schema": 1, "kind": "original-widget-fixture-producer", "sourceSHA": source,
                 "workspace": str(root), "github": github, "startedAt": started, "finishedAt": time.time(),
                 "elapsedSeconds": time.monotonic() - clock,
                 "producer": {"argv": argv, "exitCode": 0, "timeoutSeconds": PRODUCER_TIMEOUT},
                 "inputsBefore": before, "inputsAfter": after, "outputs": outputs,
                 "recipeSHA256": digest(RECIPE.encode()),
                 "stdout": file_identity(evidence / "producer.stdout.log", root),
                 "stderr": file_identity(evidence / "producer.stderr.log", root)}
        atomic_json(evidence / "receipt.json", value)
        return value
    except Exception as error:
        atomic_json(evidence / "failure.json", {"schema": 1, "sourceSHA": source, "github": github,
                    "startedAt": started, "finishedAt": time.time(), "status": "FAILED", "error": str(error)})
        raise


def validate_receipt(root, source):
    root = Path(root).resolve(strict=True)
    github = context(root, source)
    evidence = evidence_path(root)
    path = Path(os.environ.get(RECEIPT_ENV, ""))
    require(path.is_absolute() and path == evidence / "receipt.json", "Missing or wrong original producer receipt")
    safe_path(path, root)
    require(path.stat().st_size <= 2 * 1024**2, "Producer receipt exceeded its bound")
    value = parse_json(path.read_bytes())
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("kind") == "original-widget-fixture-producer"
            and value.get("sourceSHA") == source and value.get("workspace") == str(root)
            and equal_json(value.get("github"), github), "Producer receipt belongs to another source or attempt")
    for key in ("startedAt", "finishedAt", "elapsedSeconds"):
        require(type(value.get(key)) in (int, float) and math.isfinite(value[key]), "Invalid producer time")
    require(0 <= time.time() - value["finishedAt"] <= MAX_RECEIPT_AGE
            and 0 < value["startedAt"] <= value["finishedAt"] and value["elapsedSeconds"] > 0,
            "Stale or reversed producer receipt")
    require(equal_json(value.get("producer"), {"argv": ["node", PRODUCER], "exitCode": 0, "timeoutSeconds": PRODUCER_TIMEOUT})
            and type(value["producer"]["exitCode"]) is int
            and value.get("recipeSHA256") == digest(RECIPE.encode()), "Original producer did not succeed")
    inputs = input_identity(root, source)
    require(equal_json(value.get("inputsBefore"), inputs) and equal_json(inputs, value.get("inputsAfter")), "Bound producer inputs changed")
    for name in ("stdout", "stderr"):
        require(equal_json(value.get(name), file_identity(evidence / ("producer." + name + ".log"), root)),
                "Original producer output log changed")
    expected = recipe_identity(root, source, inputs["node"])
    actual = output_identity(root, expected)
    require(equal_json(value.get("outputs"), actual) and equal_json(actual, expected),
            "Derived fixtures must match the bound original producer and authored recipe")
    require(equal_json(input_identity(root, source), inputs), "Inputs changed during read-only recipe verification")
    return actual


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--source", required=True)
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    prepare(args.root, args.source, args.evidence)
