"""Explicit single in-place app upgrade setup for the saved-Shortcut pilots.

The read-only observer cannot invoke this mutation. A separately launched owned
process waits for its baseline-bound authorization, records an exclusive intent,
performs at most one original simctl install300, and retains every outcome.
"""
from pathlib import Path
import argparse
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import time

import shortcut_migration_contract as contract
import observe_shortcut_surfaces as shared
import observe_shortcut_native_lists as lists
import observe_shortcut_long_running as products
from simulator_entitlements import read_simulator_entitlements

require = shared.require


def fresh_json(path, value):
    path = Path(path)
    require(path.parent.is_dir() and not path.parent.is_symlink()
            and not path.exists() and not path.is_symlink(), "Migration evidence must be fresh and owned")
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")


def source_rows(root, source, engine):
    require(contract.git(root, "rev-parse", "HEAD").decode().strip() == source,
            "The current migration source differs from the original paired run")
    rows = {}
    for name in contract.source_files(engine):
        raw = contract.git(root, "show", source + ":" + name)
        row = contract.file_record(root / name)
        require(shared.digest(raw) == row["sha256"] and len(raw) == row["bytes"],
                "An actual migration source differs from admitted Git")
        rows[name] = row
    return rows




def prepare(root, derived, evidence, state, device, engine, command):
    root, evidence = Path(root), Path(evidence)
    old_path = os.environ.get("SHORTCUT_MIGRATION_OLD_ADMISSION", "")
    old_sha = os.environ.get("SHORTCUT_MIGRATION_OLD_ADMISSION_SHA256", "")
    old = contract.admit_old(old_path, old_sha, engine, root)
    current_app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    current = contract.product(current_app, "current")
    require(contract.original_parameters_equal(current["metadata"]["originalParameters"],
                                               old["value"]["app"]["metadata"]["originalParameters"]),
            "The original five emitted parameter records/defaults changed")
    require(current["configuration"] == old["value"]["app"]["configuration"],
            "The original storage/App Group namespace changed")
    source = source_rows(root, state["sha"], engine)
    current_runtime = contract.runtime_archive_contract(root / "AI_HLY/RuntimeHostResources.zip")
    require(current["runtimeArchive"]["archive"] == {
                key: current_runtime["archive"][key] for key in ("bytes", "sha256")}
            and current["runtimeArchive"]["manifest"] == current_runtime["manifest"],
            "The actual current app does not bundle its prepared Host/SDK bytes")
    old_app = Path(old["value"]["app"]["path"])
    require(old_app != current_app, "Old and current built products must remain distinct")
    command(["codesign", "--verify", "--deep", "--strict", str(old_app)],
            "migration-old-signature.log")
    old_info = plistlib.loads((old_app / "Info.plist").read_bytes())
    old_signing = read_simulator_entitlements(old_app / old_info["CFBundleExecutable"])
    current_info = plistlib.loads((current_app / "Info.plist").read_bytes())
    current_signing = read_simulator_entitlements(current_app / current_info["CFBundleExecutable"])
    groups = "com.apple.security.application-groups"
    require(old_signing["entitlements"].get(groups) == current_signing["entitlements"].get(groups)
            and "group.com.itorah.chavrusachat" in old_signing["entitlements"].get(groups, []),
            "The actual old/current group entitlements differ")
    descriptor = contract.descriptor_copy(derived, evidence)
    runner = Path(descriptor["installation"]["host"])
    test = Path(descriptor["installation"]["test"])
    runner_info = plistlib.loads((runner / "Info.plist").read_bytes())
    require(type(runner_info.get("CFBundleIdentifier")) is str
            and runner_info["CFBundleIdentifier"].endswith(".xctrunner"), "Invalid actual AI UI runner")
    work = evidence / "shortcut-migration-fixture"
    work.mkdir()
    archive = work / lists.engine_contract(engine)["archive"]
    source_archive = contract.checked_file(old["value"]["fixture"]["archive"])
    with archive.open("xb") as output, source_archive.open("rb") as original:
        shutil.copyfileobj(original, output)
    require(contract.file_record(archive) == contract.file_record(source_archive),
            "The once-imported old-compatible archive changed during retention")
    value = {
        "schema": 1, "scope": "miniapp_shortcut_migration_" + engine + "_os", "engine": engine,
        "sourceSHA": state["sha"], "root": str(root), "device": device,
        "oldAdmission": {"path": str(Path(old_path)), "bytes": old["bytes"], "sha256": old_sha},
        "old": old["value"]["app"], "current": current,
        "sourceFiles": source, "descriptor": descriptor,
        "runnerBundleID": runner_info["CFBundleIdentifier"],
        "runner": products.product_records(runner), "test": products.product_records(test),
        "testRelativePath": test.relative_to(runner).as_posix(),
        "archive": {"path": str(archive), **contract.file_record(archive)},
        "oldSDKManifest": old["value"]["sdkManifest"],
        "currentRuntimeArchive": current_runtime,
        "oldSigning": old_signing, "currentSigning": current_signing,
        "expectedMethod": contract.METHODS[engine],
        "scopeLimit": "One genuine old-five to current-nine saved legacy JSON array; no native-list editor",
    }
    path = evidence / "shortcut-migration-inputs.json"
    fresh_json(path, value)
    return {"path": str(path), **contract.file_record(path), "oldAppPath": str(old_app),
            "runnerBundleID": value["runnerBundleID"], "descriptor": descriptor}


def stage_fixture(inputs, documents):
    path = contract.checked_file({key: inputs[key] for key in ("path", "bytes", "sha256")})
    value = shared.read_document(path, path.parent)["value"]
    source = contract.checked_file(value["archive"])
    destination = Path(documents) / source.name
    require(destination.parent.is_dir() and not destination.parent.is_symlink()
            and not destination.exists() and not destination.is_symlink(),
            "The fresh baseline container already has a migration archive")
    with destination.open("xb") as output, source.open("rb") as original:
        shutil.copyfileobj(original, output)
    require(contract.file_record(destination) == contract.file_record(source),
            "The one old-compatible import archive changed")
    return {"path": str(destination), **contract.file_record(destination),
            "scope": "Ordinary original importer input only; not an installed package or acceptance result"}


def test_command(argv, inputs):
    value = shared.read_document(Path(inputs["path"]), Path(inputs["path"]).parent)["value"]
    descriptor = contract.descriptor_current(value["descriptor"])
    expected = "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/" + value["expectedMethod"]
    require(argv[0] == "xcodebuild" and argv.count("test-without-building") == 1
            and [item for item in argv if item.startswith("-only-testing:")] == ["-only-testing:" + expected],
            "Unexpected migration test selection")
    require(argv[argv.index("-scheme") + 1] == "AI_HLY"
            and argv[argv.index("-parallel-testing-enabled") + 1] == "NO",
            "The original AI test route changed")
    result = ["xcodebuild", "-xctestrun", descriptor]
    for name in ("-destination", "-parallel-testing-enabled", "-collect-test-diagnostics",
                 "-resultBundlePath", "-test-timeouts-enabled", "-maximum-test-execution-time-allowance"):
        require(argv.count(name) == 1, "A required original test argument is absent/ambiguous")
        result += [name, argv[argv.index(name) + 1]]
    result += ["test-without-building", "-only-testing:" + expected]
    fresh_json(Path(inputs["path"]).parent / "migration-test-command.json",
               {"schema": 1, "originalCommand": argv, "command": result,
                "descriptor": value["descriptor"],
                "difference": "Only the new migration scope uses its checked AI-only descriptor; all original test bounds/selection are retained."})
    return result


def start(root, evidence, inputs, state):
    output_path = Path(evidence) / "migration-upgrade-setup.log"
    output = output_path.open("x")
    argv = [sys.executable, str(Path(root) / "Scripts/ProductSplit/upgrade_shortcut_migration.py"),
            "--inputs", inputs["path"], "--inputs-sha256", inputs["sha256"],
            "--evidence", str(evidence), "--duration", "2100"]
    process = subprocess.Popen(argv, cwd=root, stdout=output, stderr=subprocess.STDOUT)
    state["migration_upgrade_setup"] = {"argv": argv, "pid": process.pid,
        "scope": "Explicit setup mutation: at most one baseline-authorized simctl install; not the read-only observer"}
    return process, output


def finish(handle, state):
    process, output = handle
    try:
        if process.poll() is None:
            process.terminate()
        try:
            code = process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            code = process.wait(timeout=10)
    finally:
        output.close()
    state["migration_upgrade_setup"]["exitCode"] = code
    return code


def installed_product(value, stage):
    roots = shared.product_roots(value["device"], contract.APP)
    require(contract.same_product(contract.product(roots["app"], stage), value[stage]),
            "The actual installed app differs from the admitted " + stage + " product")
    return roots


def preserved_containers(roots, baseline):
    actual = {key: str(roots[key]) for key in ("data", "group", "extensions")}
    require(actual == baseline, "An app upgrade changed the real data/group/extension container")
    return actual


def run_install(value, evidence, stopped):
    argv = ["xcrun", "simctl", "install", value["device"], value["current"]["path"]]
    record = {"argv": argv, "timeoutSeconds": 300, "startedAt": time.time(),
              "stopActions": [], "operation": "One actual in-place app install; no uninstall/reset/reimport"}
    started = time.monotonic()
    with (evidence / "migration-install.stdout.log").open("xb") as stdout, \
            (evidence / "migration-install.stderr.log").open("xb") as stderr:
        process = subprocess.Popen(argv, stdout=stdout, stderr=stderr, start_new_session=True)
        record.update(pid=process.pid, pgid=os.getpgid(process.pid))
        require(record["pgid"] == process.pid, "The install process group is not owned")
        fresh_json(evidence / "migration-install-launch.json", record)
        while process.poll() is None and not stopped() and time.monotonic() - started < 300:
            time.sleep(0.25)
        if process.poll() is None:
            record["stopReason"] = "Owned setup stopped" if stopped() else "Original install300 deadline"
            if os.getpgid(process.pid) == process.pid:
                os.killpg(process.pid, signal.SIGTERM); record["stopActions"].append("SIGTERM owned group")
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                if os.getpgid(process.pid) == process.pid:
                    os.killpg(process.pid, signal.SIGKILL); record["stopActions"].append("SIGKILL owned group")
                process.wait(timeout=5)
        record.update(exitCode=process.returncode, seconds=time.monotonic() - started, finishedAt=time.time())
    fresh_json(evidence / "migration-install-result.json", record)
    require(record["exitCode"] == 0 and not record.get("stopReason"),
            "The single actual app upgrade failed; it will not be repeated")
    return record


def upgrade_once(inputs, expected_sha, evidence, authorization, stopped):
    """The only app-install mutation in this new setup process."""
    intent_path = evidence / "migration-upgrade-intent.json"
    require(not intent_path.exists() and not intent_path.is_symlink(),
            "An actual or uncertain upgrade intent already exists; never repeat installation")
    document = shared.read_document(inputs, evidence)
    require(document["sha256"] == expected_sha, "The migration setup input manifest changed")
    value = document["value"]
    require(value["scope"] in contract.SCOPES and contract.SCOPES[value["scope"]] == value["engine"],
            "The setup scope/engine changed")
    auth = authorization["value"]
    require(auth["schema"] == 1 and auth["status"] == "BASELINE_AND_UI_TERMINATION_VERIFIED"
            and auth["inputsSHA256"] == expected_sha and auth["device"] == value["device"]
            and auth["engine"] == value["engine"], "No baseline-bound upgrade authorization")
    contract.expected_values(auth["runID"])
    runner = shared.os_container(value["device"], value["runnerBundleID"], "data")
    directory = runner / "Documents/HanlinSystemSurfaceObservation" / auth["runID"]
    request = shared.read_document(directory / "request.json", runner)
    require(request["sha256"] == auth["requestSHA256"]
            and request["value"]["phase"] == "migration-upgrade-requested",
            "The actual UI has not retained its baseline and terminated both apps")
    termination = contract.terminated_apps(request["value"])
    require(termination == auth["termination"], "Actual pre-upgrade app-state observations changed")
    roots = installed_product(value, "old")
    preserved_containers(roots, auth["containers"])
    require(str(shared.os_container(value["device"], "com.apple.shortcuts", "data"))
            == auth["shortcutsData"], "The saved Shortcut container changed before upgrade")
    identity, catalog = lists.current_identity(roots, value["engine"])
    require(identity == auth["identity"], "The installed old action changed before upgrade")
    private = shared.read_document(Path(auth["baselinePrivate"]["path"]), roots["data"])
    require(private == auth["baselinePrivate"], "The baseline private result changed before upgrade")
    commands = shared.queue_documents(roots["extensions"])
    require(commands.get(auth["baselineInvocationID"]) == auth["baselineCommand"],
            "The baseline native terminal changed before upgrade")
    own = [key for key, row in commands.items()
           if row["value"].get("invocation", {}).get("identity") == identity["identity"]
           and row["value"]["invocation"].get("entityID") == lists.ACTION]
    require(own == [auth["baselineInvocationID"]],
            "An additional fixture action executed before upgrade")
    require(contract.same_product(contract.product(value["current"]["path"], "current"), value["current"]),
            "The retained current product changed before upgrade")
    contract.descriptor_current(value["descriptor"])
    # This exclusive durable intent precedes the single install. A restarted
    # setup process encounters it and fails; it must never retry an uncertain install.
    intent = {"schema": 1, "runID": auth["runID"], "device": value["device"], "engine": value["engine"],
              "authorizationSHA256": authorization["sha256"], "inputsSHA256": expected_sha,
              "oldProduct": value["old"], "currentProduct": value["current"], "at": time.time()}
    fresh_json(evidence / "migration-upgrade-intent.json", intent)
    require(not stopped(), "The setup was stopped before its one install")
    result = run_install(value, evidence, stopped)
    after = installed_product(value, "current")
    containers = preserved_containers(after, auth["containers"])
    require(str(shared.os_container(value["device"], "com.apple.shortcuts", "data"))
            == auth["shortcutsData"], "The saved Shortcut container changed at upgrade")
    new_identity, new_catalog = lists.current_identity(after, value["engine"])
    require(new_identity == identity and new_catalog == catalog,
            "In-place installation changed the existing package/entity/generation")
    require(shared.read_document(Path(auth["baselinePrivate"]["path"]), after["data"]) == private,
            "In-place installation lost the real baseline result")
    return {"schema": 1, "runID": auth["runID"], "status": "UPGRADED", "device": value["device"],
            "engine": value["engine"], "inputsSHA256": expected_sha, "installCount": 1,
            "install": result, "intent": {"path": str(evidence / "migration-upgrade-intent.json"),
                **contract.file_record(evidence / "migration-upgrade-intent.json")},
            "containers": containers, "shortcutsData": auth["shortcutsData"],
            "identity": identity, "baselinePrivate": private, "finishedAt": time.time(),
            "scope": "Actual one-time product installation and preserved data; second saved Shortcut run remains required"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--inputs-sha256", required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--duration", type=float, required=True)
    args = parser.parse_args()
    evidence = args.evidence.resolve(strict=True)
    require(args.inputs == evidence / "shortcut-migration-inputs.json" and 0 < args.duration <= 2100,
            "The upgrade setup must use its bounded owned attempt")
    stopped = [False]
    signal.signal(signal.SIGTERM, lambda *_: stopped.__setitem__(0, True))
    signal.signal(signal.SIGINT, lambda *_: stopped.__setitem__(0, True))
    end = time.monotonic() + args.duration
    path = evidence / "migration-upgrade-authorization.json"
    outcome = {"schema": 1, "status": "NOT_RUN_NO_BASELINE_AUTHORIZATION"}
    try:
        while not stopped[0] and time.monotonic() < end:
            if path.exists():
                authorization = shared.read_document(path, evidence)
                outcome = upgrade_once(args.inputs, args.inputs_sha256, evidence, authorization, lambda: stopped[0])
                break
            time.sleep(0.25)
    except Exception as error:
        outcome = {"schema": 1, "status": "FAILED", "error": type(error).__name__ + ": " + str(error),
                   "scope": "Actual setup failure retained; no install retry or fabricated completion"}
    fresh_json(evidence / "migration-upgrade-result.json", outcome)
    print(json.dumps(outcome, ensure_ascii=False))
    return 0 if outcome["status"] == "UPGRADED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
