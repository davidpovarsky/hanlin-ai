#!/usr/bin/env python3
"""Read authenticated preparation artifacts; never build, typecheck or run SDK code."""
from pathlib import Path
import datetime
import difflib
import gzip
import hashlib
import io
import json
import re
import subprocess
import zipfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCE = "999599c242c064564c40866a1979c463f1d0e95f"
COMPARISON = "2f1cfa6e4a702475acfe80ad68bf82c5320902f5"
ORIGIN = json.loads((HERE / "artifact-origin.json").read_text())
STAGE = Path(ORIGIN["ownedStaging"])
sha = lambda value: hashlib.sha256(value).hexdigest()
def write_json(name, value):
    (HERE / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
def git_bytes(path, commit=SOURCE):
    return subprocess.check_output(["git", "show", commit + ":" + path], cwd=REPO)
def record_bytes(path, value):
    target = HERE / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(value)
    return {"path": path, "bytes": len(value), "sha256": sha(value)}
def gz_record(path, value):
    retained = record_bytes(path + ".gz", gzip.compress(value, mtime=0))
    return {**retained, "originalBytes": len(value), "originalSHA256": sha(value), "compression": "gzip", "mtime": 0}

report = json.loads((HERE / "raw/app-split-evidence/miniapp-documentation-snippets.json").read_text())
assert report["status"] == "EXECUTED_PASS"
assert len(report["projects"]) == 4
assert all(p["validation"]["succeeded"] and not p["validation"]["diagnostics"] for p in report["projects"])
assert report["sourceBlockCount"] == 14 and report["jsonBlockCount"] == 7 and len(report["excluded"]) == 8
assert report["registration"]["registrations"] == ["main"] == [report["registration"]["expectedName"]]
assert sha(git_bytes(report["registration"]["nativePath"])) == report["registration"]["nativeSessionSHA256"]
assert all(sha(git_bytes(row["path"])) == row["sha256"] for row in report["checkerInputs"])

with zipfile.ZipFile(ORIGIN["archivePath"]) as outer:
    widget_zip = outer.read("app-split-evidence/prepared-native/HanlinExpoWidgetRuntimeSupport.zip")
    with zipfile.ZipFile(io.BytesIO(widget_zip)) as support:
        widget_receipt_name = next(n for n in support.namelist() if n.endswith("/original-runtime-receipt.json"))
        widget_receipt = support.read(widget_receipt_name)
        widget = json.loads(widget_receipt)
        widget_prefix = widget_receipt_name.rsplit("/", 1)[0] + "/"
        assert sha(support.read(widget_prefix + "ExpoWidgets.bundle")) == widget["bundleSHA256"]
        assert sha(support.read(widget_prefix + "ExpoWidgetsLayoutRegistry.json")) == widget["registrySHA256"]
    widget_retained = record_bytes("raw/preparation-output/original-runtime-receipt.json", widget_receipt)
    sdk_version = outer.read("app-split-evidence/paired-product/sdk.txt").decode().strip()
    record_bytes("raw/app-split-evidence/paired-product/sdk.txt", outer.read("app-split-evidence/paired-product/sdk.txt"))
    raw_toolchain = outer.read("app-split-evidence/foreground/raw-origin/raw-001-toolchain.stdout.log")
    toolchain_retained = gz_record("raw/app-split-evidence/foreground-toolchain.stdout.log", raw_toolchain)

patch = gzip.decompress((HERE / "raw/app-split-evidence/upstream-inputs.patch.gz").read_bytes())
patch_paths = re.findall(r"^diff --git a/(.+) b/\1$", patch.decode(), re.MULTILINE)
assert set(patch_paths) == {
    "Scripts/Expo/package-lock.json", "Scripts/MiniApps/upstream-resolution.json",
    "Scripts/NativeScript/package-lock.json", "Scripts/NativeScript/package.json"
}
shadow = STAGE / "original-input-patch"
shadow.mkdir(exist_ok=False)
for path in patch_paths:
    target = shadow / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(git_bytes(path))
patch_file = STAGE / "retained-upstream-inputs.patch"
patch_file.write_bytes(patch)
commands = []
for argv in [["git", "apply", "--check", str(patch_file)], ["git", "apply", str(patch_file)]]:
    result = subprocess.run(argv, cwd=shadow, capture_output=True)
    commands.append({"argv": argv, "cwd": str(shadow), "exit": result.returncode,
                     "stdout": result.stdout.decode(), "stderr": result.stderr.decode()})
    assert result.returncode == 0, commands[-1]
write_json("preparation-patch-replay.json", {"scope": "Reconstruct four retained build-input files in owned temporary storage; no product execution.", "commands": commands})

with zipfile.ZipFile(ORIGIN["nestedArchive"]["path"]) as sdk_zip:
    manifest_bytes = sdk_zip.read("MiniAppSDK/miniapp-sdk.json")
    manifest = json.loads(manifest_bytes)
    assert sha(manifest_bytes) == report["sdk"]["manifestSHA256"]
    assert manifest["inputSHA256"] == report["sdk"]["inputSHA256"]
    assert sha(json.dumps(manifest["sourceInputs"], ensure_ascii=False, separators=(",", ":")).encode()) == manifest["inputSHA256"]
    manifest_retained = gz_record("raw/miniapp-sdk.json", manifest_bytes)
    file_index = {}
    for row in manifest["files"]:
        if row["path"] in file_index:
            assert row == file_index[row["path"]]
        file_index[row["path"]] = row
    checked = {}
    cache = {}
    def sdk_bytes(relative):
        if relative not in cache:
            value = sdk_zip.read("MiniAppSDK/" + relative)
            row = file_index[relative]
            assert len(value) == row["bytes"] and sha(value) == row["sha256"], relative
            checked[relative] = {"path": relative, "bytes": len(value), "sha256": sha(value)}
            cache[relative] = value
        return cache[relative]

    ns_package_path = "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/package.json"
    widget_path = "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle/original-runtime-receipt.json"
    ns_package = sdk_bytes("nativescript/node_modules/@hanlin/host-services/package.json")
    assert json.loads(ns_package) == json.loads(git_bytes(ns_package_path))
    ns_retained = record_bytes("raw/preparation-output/nativescript-host-services-package.json", ns_package)
    before_widget = json.loads(git_bytes(widget_path))
    changed_widget_keys = [key for key in set(before_widget) | set(widget) if before_widget.get(key) != widget.get(key)]
    assert set(changed_widget_keys) == {"inputSHA256", "packageLockSHA256"}
    assert widget["packageLockSHA256"] == sha((shadow / "Scripts/Expo/package-lock.json").read_bytes())
    assert all(sha(git_bytes(row["path"])) == row["sha256"] for row in widget["nativeSources"])

    inputs = []
    for row in manifest["sourceInputs"]:
        baseline = git_bytes(row["path"])
        comparison = git_bytes(row["path"], COMPARISON)
        assert comparison == baseline, row["path"]
        current = baseline
        disposition = "EXACT_GIT_SOURCE"
        if row["path"] in patch_paths:
            current = (shadow / row["path"]).read_bytes()
            disposition = "EXACT_RETAINED_UPSTREAM_PATCH"
        elif row["path"] == ns_package_path:
            current = ns_package
            disposition = "ACTUAL_PREPARATION_JSON_KEY_ORDER_ONLY"
        elif row["path"] == widget_path:
            current = widget_receipt
            disposition = "ACTUAL_ORIGINAL_WIDGET_RECEIPT_UPDATED_LOCK_AND_INPUT_DIGEST"
        assert sha(current) == row["sha256"], (row["path"], sha(current), row["sha256"])
        inputs.append({**row, "baseSHA256": sha(baseline), "comparisonBaseMatches": True, "disposition": disposition})
    write_json("source-input-reconciliation.json", {
        "sourceCommit": SOURCE, "comparisonCommit": COMPARISON,
        "sourceInputs": inputs, "count": len(inputs),
        "exactBaseMatches": sum(x["sha256"] == x["baseSHA256"] for x in inputs),
        "actualPreparationChanges": [x for x in inputs if x["sha256"] != x["baseSHA256"]],
        "inputSHA256": manifest["inputSHA256"], "unexplainedDifferences": [],
        "rootDirtyAGENTS": "Observed by initial read, untouched and outside these SDK inputs.",
        "widgetReceipt": {"artifact": widget_retained, "changedKeys": sorted(changed_widget_keys),
                          "nativeSourcesMatchBase": len(widget["nativeSources"]), "bundleAndRegistryMatchActualSupportArchive": True},
        "nativeScriptPackage": {"artifact": ns_retained, "jsonValueEqualsBase": True},
        "boundary": "This identifies the actual prepared source, including authentic build outputs. It does not describe all222 as unchanged Git bytes."
    })

    docs = []
    for row in manifest["files"]:
        if row["path"].startswith("docs/"):
            data = sdk_bytes(row["path"])
            assert data == git_bytes(row["path"]) == git_bytes(row["path"], COMPARISON)
            docs.append(checked[row["path"]])
    for row in report["documentation"]:
        data = sdk_bytes(row["path"])
        assert row["stagedSDKMatches"] and sha(data) == row["sha256"] == row["stagedSDKSHA256"]
    assert len(docs) == 25 and len(report["documentation"]) == 6
    assert not any("/evidence/" in row["path"] for row in manifest["files"])
    write_json("documentation-identity.json", {
        "status": "BYTE_IDENTITY_VERIFIED", "sourceCommit": SOURCE, "comparisonCommit": COMPARISON,
        "allShippedDocumentation": docs, "checkedGuidePaths": [x["path"] for x in report["documentation"]],
        "excludedRepositoryEvidencePresent": False
    })

    snippets = []
    declared = [item for project in report["projects"] for item in project["snippets"]] + report["excluded"]
    for row in declared:
        lines = sdk_bytes(row["document"]).decode().split("\n")
        opening = lines[row["line"] - 2]
        fence = re.match(r"^ {0,3}(" + chr(96) + r"{3,}|~{3,})", opening)
        assert fence, (row["id"], opening)
        marker = fence.group(1)
        body = []
        for line in lines[row["line"] - 1:]:
            if re.fullmatch(r" {0,3}" + re.escape(marker[0]) + "{" + str(len(marker)) + r",}\s*", line):
                break
            indentation = len(opening) - len(opening.lstrip(" "))
            body.append(line[min(indentation, len(line) - len(line.lstrip(" "))):])
        else:
            raise AssertionError("No closing fence: " + row["id"])
        data = ("\n".join(body) + "\n").encode()
        assert sha(data) == row["sha256"], row["id"]
        snippets.append({"id": row["id"], "document": row["document"], "line": row["line"],
                         "sha256": row["sha256"], "bytes": len(data),
                         "disposition": row.get("mode", "EXPLICIT_NONAUTHORING_EXCLUSION"),
                         **({"reason": row["reason"]} if "reason" in row else {})})
    assert len(snippets) == 29 and len({x["id"] for x in snippets}) == 29
    write_json("snippet-source-identity.json", {
        "status": "AUTHENTIC_EXECUTED_REPORT_RECONCILED_TO_EXACT_SHIPPED_BYTES",
        "sourceBlocks": report["sourceBlockCount"], "jsonBlocks": report["jsonBlockCount"],
        "explicitExclusions": len(report["excluded"]), "snippets": snippets,
        "registration": report["registration"], "checkerInputs": report["checkerInputs"],
        "newValidationOrExecution": False
    })

    catalog_path = "Scripts/MiniApps/Examples/index.json"
    catalog = json.loads(git_bytes(catalog_path))
    exported_index = json.loads(sdk_bytes(manifest["examplesIndexPath"]))
    expected_projects = []
    for project in catalog["projects"]:
        author = json.loads(git_bytes("Scripts/MiniApps/Examples/" + project["directory"] + "/hanlin.authoring.json"))
        expected_projects.append({**project, "path": "examples/" + project["directory"], "entry": author["entry"]})
    assert exported_index == {"schemaVersion": 1, "projects": expected_projects}
    for engine in ["expo", "nativescript"]:
        assert manifest["engines"][engine]["examples"] == [p for p in expected_projects if p["engine"] == engine]
    source_names = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", SOURCE, "--", "Scripts/MiniApps/Examples"], cwd=REPO, text=True).splitlines()
    expected_files = {p for p in source_names if p != catalog_path}
    example_rows = []
    for row in manifest["files"]:
        if not row["path"].startswith("examples/") or row["path"] == "examples/index.json":
            continue
        source_path = "Scripts/MiniApps/Examples/" + row["path"].removeprefix("examples/")
        data = sdk_bytes(row["path"])
        assert data == git_bytes(source_path) == git_bytes(source_path, COMPARISON)
        assert source_path in expected_files
        example_rows.append({**checked[row["path"]], "sourcePath": source_path})
    assert {x["sourcePath"] for x in example_rows} == expected_files
    assert len(example_rows) == 28 and len(expected_projects) == 4
    prior_path = "docs/miniapp-sdk/evidence/sdk-complete-examples-20261124/complex-proof-reuse.json"
    prior_bytes = git_bytes(prior_path)
    prior = json.loads(prior_bytes)
    by_source = {x["sourcePath"]: x for x in example_rows}
    assert len(prior["files"]) == 15
    for row in prior["files"]:
        assert by_source[row["path"]]["sha256"] == row["sha256"]
    write_json("example-identity.json", {
        "status": "ALL_CURRENT_EXPORTED_EXAMPLES_BYTE_MATCH", "projects": expected_projects,
        "sourceProjectFiles": example_rows, "projectFiles": len(example_rows), "indexFiles": 1,
        "sdkIndex": checked["examples/index.json"], "sourceIndexSHA256": sha(git_bytes(catalog_path)),
        "engineMetadataIndexMatches": True,
        "frozenComplexSourceProof": {"path": prior_path, "sha256": sha(prior_bytes), "matchedSourceFiles": 15,
                                   "originalSDKManifestSHA256": prior["sdkManifestSHA256"],
                                   "originalResults": prior["originalResults"], "newBuildOrExperiment": False},
        "boundary": "Exact current export and historical source/build provenance. No old package build is relabelled as newly executed against this SDK."
    })

    package_rows = []
    for engine in ["expo", "nativescript"]:
        for name, version in manifest["engines"][engine]["packageVersions"].items():
            relative = engine + "/node_modules/" + name + "/package.json"
            data = sdk_bytes(relative)
            package = json.loads(data)
            assert package["version"] == version, (engine, name, package["version"], version)
            package_rows.append({"engine": engine, "requestedName": name, "actualName": package["name"],
                                 "version": package["version"], **checked[relative]})
    compiler_rows = []
    for engine, implementation in [("expo", "expo/node_modules/@typescript/old/lib/typescript.js"),
                                   ("nativescript", "nativescript/node_modules/typescript/lib/typescript.js")]:
        declared_compiler = manifest["engines"][engine]["typescript"]
        loader = manifest["engines"][engine]["typescriptPath"]
        sdk_bytes(loader)
        data = sdk_bytes(implementation)
        actual = re.search(rb'var version = "([^"]+)";', data)
        assert actual and actual.group(1).decode() == declared_compiler["compilerVersion"]
        implementation_package_path = implementation.rsplit("/lib/", 1)[0] + "/package.json"
        package = json.loads(sdk_bytes(implementation_package_path))
        assert package["version"] == declared_compiler["compilerVersion"]
        compiler_rows.append({"engine": engine, "declaredIdentity": declared_compiler,
                              "loader": checked[loader], "implementation": checked[implementation],
                              "implementationPackage": checked[implementation_package_path],
                              "implementationVersion": package["version"], "executedVersion": declared_compiler["compilerVersion"]})
    assert manifest["engines"]["scriptwidget"]["typescript"] == manifest["engines"]["expo"]["typescript"]
    facade_rows = []
    mappings = [
        ("Packages/HanlinExpoUI/", "expo/node_modules/@hanlin/expo-ui/"),
        ("Packages/HanlinExpoNativeAPIJS/", "expo/node_modules/@hanlin/expo-native-api/"),
        ("Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services/", "nativescript/node_modules/@hanlin/host-services/")
    ]
    for source_row in manifest["sourceInputs"]:
        path = source_row["path"]
        for prefix, target in mappings:
            if path.startswith(prefix):
                suffix = path.removeprefix(prefix)
                relative = target + suffix
                if relative in file_index and (suffix.startswith("src/") or suffix.endswith((".ts", ".tsx", ".js", ".mjs")) or suffix == "package.json"):
                    data = sdk_bytes(relative)
                    assert sha(data) == source_row["sha256"]
                    facade_rows.append({**checked[relative], "sourcePath": path})
    widget_rows = []
    for path in ["scriptwidget/original-api.d.ts", "scriptwidget/service-types.d.ts", "scriptwidget/host-globals.d.ts",
                 "scriptwidget/native-api.json", "scriptwidget/widget-manifest.schema.json", "scriptwidget/manifest-validation.mjs"]:
        data = sdk_bytes(path)
        source_path = "Scripts/MiniApps/" + path
        assert data == git_bytes(source_path)
        widget_rows.append({**checked[path], "sourcePath": source_path})
    configs = {}
    for engine in ["expo", "nativescript", "scriptwidget"]:
        conf = json.loads(sdk_bytes(manifest["engines"][engine]["tsconfigPath"]))
        assert conf["compilerOptions"]["strict"] is True
        assert conf["compilerOptions"]["skipLibCheck"] is (engine == "nativescript")
        configs[engine] = {"config": conf, "manifestPolicy": manifest["engines"][engine].get("typeCheckingPolicy")}
    for project in report["projects"]:
        validation = project["validation"]
        engine = project["engine"]
        assert validation["sdk"]["compilerVersion"] == manifest["engines"][engine]["typescript"]["compilerVersion"]
        assert validation["typecheck"]["strict"] is True
        assert validation["typecheck"]["skipLibCheck"] is (engine == "nativescript")
    native_catalog = json.loads(sdk_bytes("scriptwidget/native-api.json"))
    write_json("toolchain-and-public-types.json", {
        "status": "ACTUAL_EXPORTED_IDENTITIES_MATCH_AUTHENTIC_VALIDATION_REPORT",
        "runtimeHost": json.loads((HERE / "raw/runtime-host/host-metadata.json").read_text()),
        "installations": {e: manifest["engines"][e]["installation"] for e in ["expo", "nativescript"]},
        "packageVersions": package_rows, "compilers": compiler_rows,
        "scriptwidgetCompilerSharedWithExpo": True, "configuration": configs,
        "hostContract": manifest["engines"]["expo"]["hostContract"],
        "scriptwidgetNativeAPISummary": manifest["engines"]["scriptwidget"]["nativeAPISummary"],
        "localFacadeFiles": facade_rows, "scriptwidgetTypesAndContracts": widget_rows,
        "actualValidationProjects": [{"name": p["name"], "engine": p["engine"], "validation": p["validation"]} for p in report["projects"]],
        "appleSDKVersionFromRetainedBuildMetadata": sdk_version,
        "foregroundToolchainRetained": toolchain_retained,
        "boundary": "Source/identity reconciliation of actual original compiler/type inputs and prior executed guide checks. No compiler, typecheck, app or OS operation was executed by this proof."
    })
    host_authoring = sdk_zip.read("miniapp-authoring.mjs")
    assert host_authoring == git_bytes("AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs")
    write_json("checked-artifact-files.json", {
        "sdkManifest": manifest_retained, "manifestFileCount": len(manifest["files"]),
        "checkedFiles": sorted(checked.values(), key=lambda x:x["path"]),
        "checkedFileCount": len(checked),
        "hostAuthoring": {"path": "miniapp-authoring.mjs", "sha256": sha(host_authoring), "matchesCurrentSource": True},
        "boundary": "Only needed SDK docs/examples/public facade/compiler/config members were read. Full archive extraction and a new full dependency-content audit were not performed."
    })
    write_json("inspection-summary.json", {
        "status": "SDK05_CURRENT_SHIPPING_IDENTITY_PASS",
        "sourceCommit": SOURCE, "comparisonCommit": COMPARISON,
        "sdkManifestSHA256": sha(manifest_bytes), "sdkInputSHA256": manifest["inputSHA256"],
        "documentationFiles": len(docs), "checkedGuides": len(report["documentation"]),
        "snippetSourceBlocks": report["sourceBlockCount"], "snippetJSONBlocks": report["jsonBlockCount"],
        "explicitExclusions": len(report["excluded"]), "authenticValidationProjects": len(report["projects"]),
        "diagnostics": 0, "exampleProjects": len(expected_projects), "exampleSourceFiles": len(example_rows),
        "frozenComplexSourcesMatched": len(prior["files"]),
        "sourceInputs": len(inputs), "exactBaseMatches": sum(x["sha256"] == x["baseSHA256"] for x in inputs),
        "explainedPreparationOutputs": sum(x["sha256"] != x["baseSHA256"] for x in inputs),
        "unexplainedDifferences": 0, "localFacadeFiles": len(facade_rows),
        "checkedArtifactFiles": len(checked), "newTests": 0, "newBuilds": 0, "newFreshAgentExperiments": 0,
        "native52": "NOT_RUN; first MiniApps application build timed out in original run",
        "checkedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat()
    })
print(json.dumps(json.loads((HERE / "inspection-summary.json").read_text()), indent=2))
