import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time

work = Path(__file__).resolve().parent
original = work.parent / "anytype-original-sqlite-relocation-451b4ed3-runtime"
device = "2F225B23-3149-4384-906F-8865483CBE41"
bundle = "com.davidpovarsky.chavrusatext"
platform = Path("Debug-iphonesimulator")
runner = "Maktabah-iOSUITests-Runner.app"
selector = "Maktabah-iOSUITests/ProductionAnnotationEditorAcceptanceTests/testOrdinaryPreparationBackfillsFiveThousandSavedSQLiteNotes"
outcome = {"status": "FAIL", "fixture_stage": "rooted_retained_original_2406", "test_commit": "c15e148ed11bfdc03dea4119ac49672fa86253b2"}
def run(*args, timeout=420):
    return subprocess.check_output([str(x) for x in args], text=True, stderr=subprocess.STDOUT, timeout=timeout).strip()
def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()
def native_counts():
    container = Path(run("xcrun", "simctl", "get_app_container", device, bundle, "data")).resolve()
    assert container.parts[-5] == "data" and device in container.parts
    database = container / "Library/Application Support/Maktabah-Debug/Annotations.sqlite"
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as connection:
        original_count, original_uuid = connection.execute("select count(*),count(distinct ckRecordId) from annotations").fetchone()
        ready, = connection.execute("select count(*) from otzaria_annotation_exchange_heads where namespace='otzaria.annotation.backfill.v1'").fetchone()
        native, revisions, min_rev, max_rev = connection.execute("select count(*),sum(revision),min(revision),max(revision) from otzaria_annotation_exchange_heads where namespace='otzaria.local.annotation'").fetchone()
    return container, database, dict(original=original_count, distinct=original_uuid, prepared=ready,
                    native=native, revisions=revisions, min_rev=min_rev, max_rev=max_rev)

try:
    assert (work / "build.exit").read_text().strip() == "0"
    deadline = time.monotonic() + 300
    while not (original / "retained-original.exit").exists() and time.monotonic() < deadline:
        time.sleep(3)
    assert (original / "retained-original.exit").exists()
    (work / "previous-test-provenance-sha256.txt").write_text(sha(original / "retained-original-result.json") + "\n")
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "-j"))["devices"]
    current = next(d for group in devices.values() for d in group if d["udid"] == device)
    if current["state"] == "Shutdown":
        run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    container, database, initial = native_counts()
    outcome["initial"] = initial
    assert initial == dict(original=5000, distinct=5000, prepared=5000, native=2406, revisions=2406, min_rev=1, max_rev=1)
    products = work / "Products"
    old = original / "Products"
    app = Path("Maktabah.app")
    run("codesign", "--verify", "--deep", "--strict", products / platform / runner)
    run("codesign", "--verify", "--deep", "--strict", products / platform / app)
    outcome["original_app_sha256"] = sha(products / platform / app / "Maktabah.debug.dylib")
    outcome["original_sdk_sha256"] = sha(products / platform / app / "Frameworks/AnytypeOriginalEditor.framework/AnytypeOriginalEditor")
    outcome["xctest_sha256"] = sha(products / platform / runner / "PlugIns/Maktabah-iOSUITests.xctest/Maktabah-iOSUITests")
    outcome["test_source_sha256"] = sha(work / "Maktabah-iOSUITests/ProductionAnnotationEditorAcceptanceTests.swift")
    assert outcome["original_app_sha256"] == sha(old / platform / app / "Maktabah.debug.dylib")
    assert outcome["test_source_sha256"] == "ebd7eb6ce028bc40358ff064a15e619805e7fc24ef019a5238290a9cb9ffbb63"
    receipt = next(old.glob("*.xctestrun"))
    assert sha(products / receipt.name) == sha(receipt)
    env = dict(os.environ)
    for flag in ("OTZARIA_ORIGINAL_EDITOR_QUALIFICATION", "OTZARIA_ORIGINAL_EDITOR_PROCESS_RESUME"):
        env.pop(flag, None)
        env.pop("TEST_RUNNER_" + flag, None)
    env.update(TEST_RUNNER_FAITHFUL_VIEWPORT_DIRECTORY=str(container / "Documents"),
               TEST_RUNNER_OTZARIA_ANNOTATION_ACCEPTANCE_DATABASE=str(database),
               TEST_RUNNER_OTZARIA_RESUME_EXISTING_SQLITE_BACKFILL_FIXTURE="1")
    result = work / "OriginalSQLiteRetainedFixture.xcresult"
    args = ["xcodebuild", "test-without-building", "-xctestrun", str(products / receipt.name),
            "-destination", "platform=iOS Simulator,id=" + device, "-parallel-testing-enabled", "NO",
            "-collect-test-diagnostics", "never", "-test-timeouts-enabled", "YES",
            "-maximum-test-execution-time-allowance", "14400", "-only-testing:" + selector,
            "-resultBundlePath", str(result)]
    (work / "actual-test-command.json").write_text(json.dumps(args) + "\n")
    with (work / "actual-original-failure-phases.log").open("wb") as observer, (work / "actual-xctest.log").open("wb") as log:
        phases = subprocess.Popen(["xcrun", "simctl", "spawn", device, "log", "stream", "--level", "info",
                                  "--predicate", 'eventMessage CONTAINS "OriginalAnytypeSQLitePhase"'],
                                 stdout=observer, stderr=subprocess.STDOUT)
        try:
            outcome["apple_exit"] = subprocess.run(args, env=env, cwd=work, stdout=log,
                                                   stderr=subprocess.STDOUT, timeout=14900).returncode
        finally:
            phases.terminate()
            phases.wait(timeout=30)
    _, _, terminal = native_counts()
    outcome["terminal"] = terminal
    summary = work / "apple-xctest-summary.json"
    actual = run("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", result)
    summary.write_text(actual + "\n")
    checked = json.loads(actual)
    outcome["apple_summary_sha256"] = sha(summary)
    assert outcome["apple_exit"] == 0 and checked["passedTests"] == 1 and checked["failedTests"] == checked["skippedTests"] == 0
    assert terminal == dict(original=5000, distinct=5000, prepared=5000, native=5000, revisions=5000, min_rev=1, max_rev=1)
    outcome["status"] = "PASS_EXACT_5000_ORIGINAL_APP_SQLITE_ROWS_AND_COLD_REOPEN"
except Exception as error:
    outcome["error"] = type(error).__name__ + ": " + str(error)
finally:
    (work / "retained-original-result.json").write_text(json.dumps(outcome, indent=2, sort_keys=True) + "\n")
    (work / "retained-original.exit").write_text("0\n" if outcome["status"].startswith("PASS_") else "1\n")
    print(json.dumps(outcome), flush=True)
