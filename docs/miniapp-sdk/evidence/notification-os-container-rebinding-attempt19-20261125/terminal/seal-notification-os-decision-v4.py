"""Prepare the exact notification OS decision from actual finalized upstream proofs.
Oracle-only draft; native owner alone may execute after actual full52 PASS.
No test/build/install or product mutation is performed by this sealer.
"""

from pathlib import Path
import datetime, fcntl, hashlib, json, math, os, plistlib, subprocess, uuid

ROOT = Path("/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete")
CTRL = ROOT / "build/primary-control"
SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
TREE = "f7a6596a1ef53d8d962ceb9f619460ffa19ee91e"
SDK_SOURCE = "a2c8a1b1be746461272ba77254603304567c309d"
MINI_BUILD_SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
AI_BUILD_SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
EXPECTED_TEST_BUILD_STATUS = "PASS"
PAIRED_ID = "paired52-continuation-v5"
BUILD_BINDINGS = "build/primary-control/focused19-v11/native-result/built-input-bindings.json"
BUILD_SHA = "71831b770ee518a6d926650704c509a53d74c41540bd51d743de431b7ca0c640"  # Bind only the actual new consumer product receipt.
STAGED_INPUTS = "build/primary-control/focused19-v11/native-result/staged-inputs.json"
STAGED_SHA = "ab3d55ab809ff78a5a93f28dc058c20e76f98a2a1176f8b6228ce9b3d319d976"  # Bind only the actual new staged-input receipt.
METADATA = "build/primary-control/remaining-native-product-metadata-v11.json"  # Bind only the actual post-build current-source metadata.
METADATA_SHA = "b1163811263ef4b648e6d5e265c012cbbf5f946e504f5bd084d28fe13514d724"
DERIVED = Path("/Users/m1/caches/DerivedData/hanlin-ai-ce49e30d-miniapp-complete")
PRODUCTS = DERIVED / "Build/Products"
DEVICE = "E742FBCD-8FF0-4130-B143-7F8328637138"
ORIGINAL_CHARGE = 26.137203625010443
ORIGINAL_SELECTOR = "AI_HLYTests/HanlinUnifiedHostServicesE2ETests/actualNativeScriptImportsTheGeneratedTypedFacadeAndCallsEveryEngine"
ORIGINAL_COMPANION = "build/primary-control/companion-native-v1/decision.json"
ORIGINAL_COMPANION_SHA = "e4c47637ab828da11bdbd3ba9dc6bc2453dbf9c0214e6640949bd3138de563b3"
NOTIFICATION_REVIEW = "build/primary-control/companion-native-v1/notification-package/result-review.json"
NOTIFICATION_SHA = "4396672e8dd3fe2546d89d108c2e57eeb98a48f386171a93bee5e0322ee98999"
LEDGER = CTRL / "companion-native-v1/ledger.json"
ORIGINAL_LEDGER_SHA = "0601f21cbf3d2433dec7e5ce7fb66806555bcca6e4577e92b94f265c7a255068"

def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def read(path):
    return json.loads(Path(path).read_text())

def run(argv, timeout=30):
    return subprocess.check_output(argv, cwd=ROOT, text=True, timeout=timeout).strip()

def repository_path(value):
    path = (ROOT / value).resolve()
    assert path.is_relative_to(ROOT) and path.is_file(), str(path)
    return path

def reference(path):
    path = repository_path(path)
    return {"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size, "sha256": digest(path)}

def authenticate(row):
    path = repository_path(row["path"])
    assert digest(path) == row["sha256"], str(path)
    if "bytes" in row:
        assert path.stat().st_size == row["bytes"], str(path)
    return path

def add_required(required, row):
    path = repository_path(row["path"])
    name = path.relative_to(ROOT).as_posix()
    if name in ("build/primary-control/state.json", "build/primary-control/companion-native-v1/ledger.json"):
        return
    if name in required:
        assert required[name]["sha256"] == row["sha256"], name
    required[name] = {"path": name, "sha256": row["sha256"]}

def clean_terminal(row):
    assert row["source"] == SOURCE and row["chargeCommitted"] is True
    assert not row["remainingOwnedProcessGroup"] and not row["cleanupErrors"] and not row["sourceErrors"]

def current_product(row):
    path = Path(row["path"]).resolve()
    assert path.is_relative_to(PRODUCTS) and path.is_file(), str(path)
    assert path.stat().st_size == row.get("bytes", row.get("size")), str(path)
    assert digest(path) == row["sha256"], str(path)
    return path

def authenticate_metadata():
    assert isinstance(METADATA, str) and isinstance(METADATA_SHA, str), "Actual current product metadata is not bound"
    path = authenticate({"path": METADATA, "sha256": METADATA_SHA})
    metadata = read(path)
    assert metadata["schema"] == 1 and metadata["source"] == SOURCE and metadata["sourceTree"] == TREE
    assert authenticate(metadata["builtInputBindings"]) == repository_path(BUILD_BINDINGS)
    assert metadata["builtInputBindings"]["sha256"] == BUILD_SHA
    rows = metadata["files"]
    assert len(rows) == 4 and len({row["path"] for row in rows}) == 4
    roles = {row["role"]: row for row in rows}
    assert set(roles) == {"aiXctestrun", "miniXctestrun", "uiRunnerInfo", "uiRunnerExecutable"}
    for row in rows:
        current_product(row)
    # These are the actual legacy target dictionaries in the authenticated plists.
    ai = plistlib.loads(Path(roles["aiXctestrun"]["path"]).read_bytes())["AI_HLYTests"]
    assert ai["TestBundlePath"] == "__TESTHOST__/PlugIns/AI_HLYTests.xctest"
    assert ai["TestHostPath"] == "__TESTROOT__/Debug-iphonesimulator/AI_Hanlin.app"
    mini = plistlib.loads(Path(roles["miniXctestrun"]["path"]).read_bytes())["HanlinMiniAppsUITests"]
    assert mini["TestBundlePath"] == "__TESTHOST__/PlugIns/HanlinMiniAppsUITests.xctest"
    assert mini["TestHostPath"] == "__TESTROOT__/Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app"
    assert mini["UITargetAppPath"] == "__TESTROOT__/Debug-iphonesimulator/HanlinMiniApps.app"
    info_path = Path(roles["uiRunnerInfo"]["path"]).resolve()
    assert info_path == PRODUCTS / "Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    assert info["CFBundleIdentifier"] == metadata["runner"]["bundleID"]
    assert info["CFBundleIdentifier"].endswith(".xctrunner")
    assert info["CFBundleExecutable"] == metadata["runner"]["executable"]
    assert info_path.parent / info["CFBundleExecutable"] == Path(roles["uiRunnerExecutable"]["path"]).resolve()
    return path, roles

def base_decision():
    assert run(["git", "rev-parse", "HEAD"]) == SOURCE
    assert run(["git", "rev-parse", "HEAD^{tree}"]) == TREE
    controller = authenticate(CONFIG["controller"])
    authenticate(CONFIG["originalController"])
    primary_path = CTRL / "state.json"
    primary = read(primary_path)
    assert primary["source"] == SOURCE and primary["status"] in ("COMPLETED", "FAIL", "PAUSED_AFTER_PHASE")
    primary_ref = reference(primary_path)
    paired_path = CTRL / PAIRED_ID / "state.json"
    paired = read(paired_path)
    clean_terminal(paired)
    assert paired["id"] == PAIRED_ID and paired["sourceTree"] == TREE
    assert paired["status"] == paired["original52"] == "EXECUTED_PASS"
    assert paired["ownedSimulatorCleanup"]["device"] == DEVICE
    assert paired["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    decision_path = paired_path.with_name("decision.json")
    assert digest(decision_path) == paired["decisionSHA256"]
    previous = read(decision_path)
    assert previous["source"] == SOURCE and previous["sourceTree"] == TREE
    assert previous["producerSource"] == SDK_SOURCE and previous["derivedData"] == str(DERIVED)
    evidence = Path(paired["pairedEvidence"]).resolve()
    assert evidence.is_relative_to(CTRL)
    child_path = evidence / "state.json"
    assert digest(child_path) == paired["childStateSHA256"] == paired["actualAcceptance"]["sha256"]
    child = read(child_path)
    assert child["source"] == SOURCE and child["tree"] == TREE
    assert child["status"] == child["original52"] == child["original25"] == child["original27"] == "EXECUTED_PASS"
    assert not child["sourceErrors"] and not child["cleanupErrors"] and not child["errors"]
    for label, count in (("OriginalRuntimes", 25), ("Paired", 27)):
        group = child["groups"][label]
        assert group["status"] == "PASS" and group["exitCode"] == 0 and group["resultFinalized"]
        assert group["selectors"] == previous["groups"][label]["selectors"]
        summary = group["summary"]
        assert summary["totalTestCount"] == summary["passedTests"] == count
        assert summary["failedTests"] == summary["skippedTests"] == 0
    assert primary["phases"]["split-paired-acceptance"]["status"] == "PASS"
    assert primary["phases"]["split-paired-acceptance"]["continuationDecisionSHA256"] == paired["decisionSHA256"]
    charge = primary["continuationCharges"][-1]
    assert charge["id"] == PAIRED_ID and charge["decisionSHA256"] == paired["decisionSHA256"]
    assert charge["chargedSeconds"] == paired["chargedSeconds"]
    ownership = evidence / "created-simulator.txt"
    assert str(uuid.UUID(ownership.read_text().strip())).upper() == DEVICE == child["simulator"]

    built_path = authenticate(previous["setup"]["builtInputBindings"])
    assert built_path == repository_path(BUILD_BINDINGS) and digest(built_path) == BUILD_SHA
    built = read(built_path)
    assert built["source"] == SOURCE and built["originalTestBuilds"] == EXPECTED_TEST_BUILD_STATUS
    assert "authenticatedMiniReuse" not in built and "authenticatedAIReuse" not in built
    assert built["miniBuildProducerSource"] == MINI_BUILD_SOURCE and built["aiBuildProducerSource"] == AI_BUILD_SOURCE
    assert built["SDKProducerSource"] == SDK_SOURCE
    assert built["files"] == previous["productFiles"] and len(built["files"]) == 35
    assert len({row["path"] for row in built["files"]}) == 35
    baseline_products = {str(current_product(row)): row for row in built["files"]}
    metadata_path, metadata_roles = authenticate_metadata()
    products = [{**row, "role": "retainedProduct"} for row in built["files"]]
    products.extend(dict(row) for row in metadata_roles.values())
    for role, suffix in CONFIG["productAliases"].items():
        row = baseline_products[str(PRODUCTS / suffix)]
        products.append({**row, "role": role})
    products.append({**metadata_roles[CONFIG["xctestrunRole"]], "role": "xctestrun"})

    staged_path = authenticate(previous["setup"]["stagedInputs"])
    assert staged_path == repository_path(STAGED_INPUTS) and digest(staged_path) == STAGED_SHA
    staged = read(staged_path)
    assert staged["source"] == SOURCE
    expected = staged["unchanged"] + [{"name": staged["replacement"]["name"], **staged["replacement"]["after"]}]
    expected.sort(key=lambda row: row["name"])
    assert expected == previous["stagedFiles"] and len(expected) == len({row["name"] for row in expected}) == 11
    assert child["stagedInputsVerified"]["files"] == expected
    assert child["stagedInputsVerified"]["authority"] == previous["setup"]["stagedInputs"]
    # The completed child observed this final path while booted; the device is now Shutdown.
    final = child["stagedInputsFinalVerified"]
    assert final["schema"] == 1 and final["source"] == SOURCE and final["simulator"] == DEVICE
    assert final["status"] == "EXECUTED_PASS" and not final["differences"] and "error" not in final
    assert final["preTestObservationPreserved"] is True and final["lookupExitCode"] == 0
    assert final["authority"] == previous["setup"]["stagedInputs"]
    identities = [{key: row[key] for key in ("name", "bytes", "sha256")} for row in expected]
    assert final["files"] == identities
    final_receipt_path = authenticate({"path": final["receiptPath"], "sha256": final["receiptSHA256"]})
    assert final_receipt_path == evidence / "staged-inputs-final-verification.json"
    assert read(final_receipt_path) == {key: value for key, value in final.items() if key not in ("receiptPath", "receiptSHA256")}

    documents = Path(final["documentsRoot"])
    assert documents.name == "Documents" and documents.is_dir() and not documents.is_symlink()
    assert documents == documents.resolve(strict=True)
    container = documents.parent
    expected_parent = Path("/Users/m1/Library/Developer/CoreSimulator/Devices") / DEVICE / "data/Containers/Data/Application"
    assert container.parent == expected_parent
    container_uuid = str(uuid.UUID(container.name)).upper()
    assert container_uuid == container.name.upper()
    final_metadata = final["metadata"]
    retained_metadata_path = authenticate(final_metadata)
    assert retained_metadata_path == evidence / "final-mini-container-metadata.plist"
    retained_metadata = plistlib.loads(retained_metadata_path.read_bytes())
    assert retained_metadata["MCMMetadataIdentifier"] == final_metadata["identifier"] == "com.itorah.hanlinminiapps"
    assert final_metadata["containerUUID"] == container_uuid
    metadata_source = container / ".com.apple.mobile_container_manager.metadata.plist"
    assert Path(final_metadata["sourcePath"]) == metadata_source
    assert metadata_source.is_file() and not metadata_source.is_symlink()
    metadata_bytes = metadata_source.read_bytes()
    current_metadata = plistlib.loads(metadata_bytes)
    assert current_metadata["MCMMetadataIdentifier"] == "com.itorah.hanlinminiapps"
    # MCMMetadataUUID is metadata identity, not the container directory UUID.
    current_container_metadata = {"sourcePath": str(metadata_source), "bytes": len(metadata_bytes),
        "sha256": hashlib.sha256(metadata_bytes).hexdigest(), "identifier": current_metadata["MCMMetadataIdentifier"],
        "containerUUID": container_uuid, "MCMMetadataUUID": current_metadata.get("MCMMetadataUUID")}
    observed = []
    for row in identities:
        assert Path(row["name"]).name == row["name"]
        path = documents / row["name"]
        assert path.is_file() and not path.is_symlink(), row["name"]
        assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], row["name"]
        observed.append({"name": row["name"], "path": str(path), "bytes": row["bytes"], "sha256": row["sha256"]})

    required = {}
    for row in previous["requiredFiles"]:
        add_required(required, row)
    sdk = CONFIG["sdk"]
    assert sdk["producerSource"] == SDK_SOURCE
    for key in ("manifestPath", "manifestSHA256", "archiveSHA256", "inputSHA256", "sourceInputCount"):
        assert previous["sdk"][key] == sdk[key]
    manifest_path = authenticate({"path": sdk["manifestPath"], "sha256": sdk["manifestSHA256"]})
    manifest = read(manifest_path)
    assert manifest["inputSHA256"] == sdk["inputSHA256"]
    assert len(manifest["sourceInputs"]) == len({row["path"] for row in manifest["sourceInputs"]}) == 235
    for row in manifest["sourceInputs"] + CONFIG["extraRequiredSourceFiles"]:
        add_required(required, row)
    assert digest(ROOT / "AI_HLY/RuntimeHostResources.zip") == sdk["archiveSHA256"] == built["hostArchiveSHA256"]
    for row in products:
        if row["role"] in ("aiHostResource", "miniHostResource"):
            assert row["sha256"] == sdk["archiveSHA256"]
    refs = [reference(path) for path in (paired_path, decision_path, child_path, built_path, staged_path, metadata_path, ownership, manifest_path, controller,
        final_receipt_path, retained_metadata_path)]
    for row in refs:
        add_required(required, row)
    for row in required.values():
        authenticate(row)
    node = CONFIG["originalNode"]
    for key, value in node.items():
        assert previous["originalNode"][key] == value
    assert Path(node["path"]).stat().st_size == 116870064 and digest(node["path"]) == node["sha256"]

    resource = dict(previous["resourceAssessment"])
    assert resource["decision"] == "FITS_MEASURED_NEXT_PHASE"
    disk = run(["df", "-k", "/System/Volumes/Data"])
    free = int(disk.splitlines()[-1].split()[3]) * 1024
    need = resource["estimatedIncrementalBytes"] + resource["concurrentAndOSAllowanceBytes"]
    assert free >= need, {"freeBytes": free, "retainedApprovedBoundBytes": need}
    resource.update(observedAt=utc(), observedFreeBytes=free, df=disk, authority=reference(decision_path),
        basis="Fresh free-space observation using the existing paired decision's conservative retained-product/result components unchanged for this one remaining test; no new size quota.")
    decision = dict(CONFIG["fixedFields"])
    decision.update(root=str(ROOT), source=SOURCE, sourceTree=TREE, originalController=CONFIG["originalController"],
        outputDirectory="build/primary-control/" + CONFIG["id"], primaryStateSHA256=primary_ref["sha256"],
        activeBaselineSeconds=primary["activeElapsedSeconds"], originalNode=node, sdk=sdk, derivedData=str(DERIVED),
        preparedTrackedDiffSHA256=hashlib.sha256(subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=ROOT, timeout=30)).hexdigest(),
        pairedTerminal=reference(paired_path), simulator={"udid": DEVICE, "ownershipSHA256": digest(ownership)},
        requiredFiles=list(required.values()), productFiles=products,
        productProvenance={"source": SOURCE, "receipts": refs}, resourceAssessment=resource)
    observation = {"source": SOURCE, "observedAt": utc(), "pairedTerminal": reference(paired_path),
        "pairedChild": reference(child_path), "builtInputBindings": reference(built_path), "stagedInputs": reference(staged_path),
        "productMetadata": reference(metadata_path), "originalTestBuilds": EXPECTED_TEST_BUILD_STATUS,
        "finalStagedInputs": reference(final_receipt_path),
        "finalContainerMetadata": reference(retained_metadata_path), "currentContainerMetadata": current_container_metadata,
        "miniBuildProducerSource": MINI_BUILD_SOURCE,
        "aiBuildProducerSource": AI_BUILD_SOURCE, "SDKProducerSource": SDK_SOURCE,
        "device": DEVICE, "documentsRoot": str(documents), "files": observed, "mutationPerformed": False}
    return decision, {"primary": primary, "paired": paired, "required": required, "observation": observation,
        "metadataRoles": metadata_roles, "primaryPath": primary_path}

def original_companion():
    original_path = authenticate({"path": ORIGINAL_COMPANION, "sha256": ORIGINAL_COMPANION_SHA})
    review_path = authenticate({"path": NOTIFICATION_REVIEW, "sha256": NOTIFICATION_SHA})
    original, review = read(original_path), read(review_path)
    assert original["allowanceSeconds"] == 1200 and original["paired4500Separate"] is True
    assert original["scope"] == ["HanlinNotificationInvocationTests", ORIGINAL_SELECTOR]
    assert review["status"] == "EXECUTED_PASS" and review["failed"] == review["skipped"] == 0
    return original_path, review_path, review

def finish(decision, context, extra_refs):
    decision_path = CTRL / (CONFIG["id"] + "-decision.json")
    observation_path = CTRL / (CONFIG["id"] + "-seal-inputs.json")
    receipt_path = CTRL / (CONFIG["id"] + "-decision-receipt.json")
    assert not (ROOT / decision["outputDirectory"]).exists()
    assert not any(path.exists() for path in (decision_path, observation_path, receipt_path))
    assert set(decision) == set(CONFIG["decisionFields"])
    assert digest(context["primaryPath"]) == decision["primaryStateSHA256"]
    assert digest(LEDGER) == decision["companionLedgerSHA256"]
    assert run(["git", "rev-parse", "HEAD"]) == SOURCE
    for row in extra_refs:
        add_required(context["required"], row)
        decision["productProvenance"]["receipts"].append(row)
    for row in context["required"].values():
        authenticate(row)
    # These are audit records in primary-control, never product or queue writes.
    with observation_path.open("x") as stream:
        json.dump(context["observation"], stream, indent=2); stream.write("\n")
    observation_ref = reference(observation_path)
    add_required(context["required"], observation_ref)
    decision["requiredFiles"] = list(context["required"].values())
    decision["productProvenance"]["receipts"].append(observation_ref)
    with decision_path.open("x") as stream:
        json.dump(decision, stream, indent=2); stream.write("\n")
    receipt = {"schema": 1, "status": "SEALED_NOT_LAUNCHED", "source": SOURCE, "sourceTree": TREE,
        "decision": reference(decision_path), "sealer": reference(Path(__file__).resolve()),
        "controller": CONFIG["controller"], "sealedAt": utc(), "fieldCount": len(decision),
        "productRows": len(decision["productFiles"]), "originalProductRows": 35, "stagedInputCount": 11,
        "inputObservation": observation_ref, "activeBaselineSeconds": decision["activeBaselineSeconds"],
        "allowanceSeconds": decision["allowanceSeconds"], "actualPairedStatus": context["paired"]["status"],
        "phaseExecution": "NOT_RUN", "SDKProducerSource": SDK_SOURCE,
        "miniBuildProducerSource": MINI_BUILD_SOURCE, "aiBuildProducerSource": AI_BUILD_SOURCE}
    with receipt_path.open("x") as stream:
        json.dump(receipt, stream, indent=2); stream.write("\n")
    print(json.dumps(receipt))

CONFIG = json.loads(r'''{
  "id": "notification-os-v1",
  "controller": {
    "path": "build/primary-control/notification-os-v6.py",
    "sha256": "379008353af52593df805257d076ed13c1df93e13b9b39f76782738a8fff9535"
  },
  "originalController": {
    "path": "build/primary-control/paired52-continuation-v3.py",
    "sha256": "dad6581212134987b666a5161ab33994e6d79b57ed38108faba6ffb22c3bb520"
  },
  "originalNode": {
    "path": "/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete-tools/node-v24.5.0-darwin-arm64/bin/node",
    "sha256": "336b5b3ebc5deb86df842102b20b6e4761605b7a667823e68dda7761b91a161b",
    "version": "24.5.0"
  },
  "sdk": {
    "producerSource": "a2c8a1b1be746461272ba77254603304567c309d",
    "manifestPath": "build/primary-control/focused19-inputs/miniapp-sdk.json",
    "manifestSHA256": "4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92",
    "archiveSHA256": "7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc",
    "inputSHA256": "ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2",
    "sourceInputCount": 235
  },
  "decisionFields": [
    "schema",
    "id",
    "owner",
    "authorization",
    "allowanceSeconds",
    "separateFromPaired4500AndCompanion1200",
    "selector",
    "expectedTests",
    "root",
    "source",
    "sourceTree",
    "originalController",
    "outputDirectory",
    "primaryStateSHA256",
    "activeBaselineSeconds",
    "preparedTrackedDiffSHA256",
    "requiredFiles",
    "sdk",
    "derivedData",
    "productFiles",
    "uiRunnerInfoPlist",
    "productProvenance",
    "pairedTerminal",
    "ns5Terminal",
    "simulator",
    "companionLedgerSHA256",
    "resourceAssessment",
    "originalNode"
  ],
  "fixedFields": {
    "schema": 1,
    "id": "notification-os-v1",
    "owner": "/root/native_execution",
    "authorization": {
      "by": "/root",
      "scope": "separate original notification OS probe"
    },
    "selector": "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines",
    "expectedTests": 1,
    "allowanceSeconds": 900,
    "separateFromPaired4500AndCompanion1200": true
  },
  "extraRequiredSourceFiles": [
    {
      "path": "Scripts/CI/verify_selected_tests.py",
      "bytes": 2000,
      "sha256": "4ae4a28934341461b364a9b83fb891ca214da64cf3046635278fb4e6837caad5"
    },
    {
      "path": "Scripts/CI/observe_notification_os_delivery.py",
      "bytes": 18899,
      "sha256": "f6cf4e040f592fa94ebf9fd813b6e03d125d5c7c32dc2d2a43f3b42cdb33d085"
    },
    {
      "path": "Fixtures/Widgets/Hanlin-ScriptWidget-Actions.scripting",
      "bytes": 825,
      "sha256": "33c717e2a454d8831364cb24b15b9e9e799cd3161b526013a15efe46485ebccb"
    },
    {
      "path": "HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift",
      "bytes": 91719,
      "sha256": "da0fa21f26b677f4d18f8e1972208b39e30401a127e9dd2a9643e0fe8d7ad17c"
    },
    {
      "path": "DemoMiniApps/hanlin-script-parity.hanlinNativeScript",
      "bytes": 7512,
      "sha256": "2e48509336edba2b301490422102dbf25cb7f1b894430d52994febdc1c33c199"
    },
    {
      "path": "Scripts/ProductSplit/run_paired_acceptance.py",
      "sha256": "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
    },
    {
      "path": "AI_HLY/RuntimeHostResources.zip",
      "sha256": "7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc"
    },
    {
      "path": "AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo",
      "bytes": 325929,
      "sha256": "74d6f9437647e09cf0a323175fa8468971430543740f04f8fb688f899b6dae20"
    }
  ],
  "productAliases": {
    "miniAppExecutable": "Debug-iphonesimulator/HanlinMiniApps.app/HanlinMiniApps",
    "miniRuntimeImage": "Debug-iphonesimulator/HanlinMiniApps.app/HanlinMiniApps.debug.dylib",
    "miniHostResource": "Debug-iphonesimulator/HanlinMiniApps.app/RuntimeHostResources.zip",
    "uiTestExecutable": "Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app/PlugIns/HanlinMiniAppsUITests.xctest/HanlinMiniAppsUITests"
  },
  "xctestrunRole": "miniXctestrun"
}''')

def main():
    with (CTRL / "native-continuation-owner.lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        decision, context = base_decision()
        original_path, review_path, review = original_companion()
        ns5_path = CTRL / "companion-native-v1-ns5/state.json"
        ns5 = read(ns5_path)
        clean_terminal(ns5)
        assert ns5["id"] == "companion-native-v1-ns5"
        # Preserve the existing OS wrapper's allowed terminal statuses.
        assert ns5["status"] in ("EXECUTED_PASS", "FAILED", "TIMED_OUT")
        assert ns5["ownedSimulatorCleanup"]["device"] == DEVICE and ns5["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
        ns5_decision_path = ns5_path.with_name("decision.json")
        assert digest(ns5_decision_path) == ns5["decisionSHA256"]
        ns5_decision = read(ns5_decision_path)
        assert ns5_decision["source"] == SOURCE and ns5_decision["sourceTree"] == TREE
        assert ns5_decision["pairedTerminal"] == decision["pairedTerminal"]
        assert ns5_decision["selector"] == ORIGINAL_SELECTOR + "()"
        before_path = ns5_path.with_name("companion-ledger-before.json")
        assert digest(before_path) == ORIGINAL_LEDGER_SHA
        before, ledger = read(before_path), read(LEDGER)
        assert ledger["maximumActiveSeconds"] == before["maximumActiveSeconds"] == 1200
        assert len(before["charges"]) == 1 and len(ledger["charges"]) == 2
        assert ledger["charges"][:1] == before["charges"]
        assert before["charges"][0]["id"] == "companion-native-v1-notification-package"
        assert before["charges"][0]["elapsedSeconds"] == before["activeElapsedSeconds"] == ORIGINAL_CHARGE
        assert before["charges"][0]["logSHA256"] == review["logSHA256"]
        charge = ledger["charges"][-1]
        assert charge["id"] == ns5["id"] and charge["source"] == SOURCE and charge["status"] == ns5["status"]
        assert charge["elapsedSeconds"] == ns5["chargedSeconds"] and charge["decisionSHA256"] == ns5["decisionSHA256"]
        assert charge["logSHA256"] == ns5["logSHA256"] and charge["selector"] == ORIGINAL_SELECTOR + "()"
        assert ledger["activeElapsedSeconds"] == math.fsum(row["elapsedSeconds"] for row in ledger["charges"]) == ns5["cumulativeCompanionSeconds"]
        assert digest(LEDGER) == ns5["companionLedgerAfterSHA256"]
        assert charge in context["primary"]["companionCharges"]
        assert context["primary"]["activeElapsedSeconds"] == ns5["cumulativeActiveSeconds"]
        assert ledger["remainingSelectors"] == ([] if ns5["status"] == "EXECUTED_PASS" else [ORIGINAL_SELECTOR])
        decision.update(ns5Terminal=reference(ns5_path), companionLedgerSHA256=digest(LEDGER),
            uiRunnerInfoPlist=context["metadataRoles"]["uiRunnerInfo"]["path"])
        context["observation"].update(ns5Terminal=reference(ns5_path), companionLedgerAfterNS5=reference(LEDGER),
            actualNS5Status=ns5["status"])
        refs = [reference(path) for path in (original_path, review_path, ns5_path, ns5_decision_path, before_path)]
        finish(decision, context, refs)

if __name__ == "__main__":
    main()
