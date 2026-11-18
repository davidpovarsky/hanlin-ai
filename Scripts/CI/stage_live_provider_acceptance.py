"""One opt-in original-app live account seed; export bounded non-secret evidence."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

LOG = Path(os.environ["LOG_DIR"])
EVIDENCE = Path("build/live-provider-evidence")
SELECTOR = "AI_HLYUITests/AgentRuntimeConversationUITests/testLiveGeminiPythonConsentAndColdReopen"
MODEL = "gemini-3.8-flash"


def call(argv, timeout=60, required=True):
    from stage_simulator_fixtures import run_bounded
    result = run_bounded(argv, timeout_seconds=timeout)
    if required and result.returncode:
        raise RuntimeError("Native live-provider preparation command failed: " + argv[1])
    return result


def owned_simulator():
    simulator = (LOG / "simulator-udid.txt").read_text(encoding="utf-8").strip()
    devices = json.loads(call(["xcrun", "simctl", "list", "devices", "-j"]).stdout)["devices"]
    device = next(d for group in devices.values() for d in group if d["udid"] == simulator)
    expected = "Hanlin-Phase2-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
    if device["name"] != expected:
        raise RuntimeError("Live credentials require this job's newly owned simulator")
    return simulator


def container(simulator):
    raw = call(["xcrun", "simctl", "get_app_container", simulator, "com.itorah.chavrusachat", "data"], 120).stdout.strip()
    result = Path(raw).resolve(strict=True)
    if not result.is_dir():
        raise RuntimeError("Original app data container is unavailable")
    return result


def stage():
    key = os.environ.get("HANLIN_LIVE_GEMINI_API_KEY", "")
    if not key:
        raise RuntimeError("Existing live provider credential is not configured")
    simulator = owned_simulator()
    app = Path((LOG / "app-path.txt").read_text(encoding="utf-8").strip())
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info["CFBundleIdentifier"] != "com.itorah.chavrusachat":
        raise RuntimeError("Live seed requires the original AI product")
    call(["xcrun", "simctl", "install", simulator, str(app)], 300)
    # Record ownership before the first secret write, so cleanup also runs
    # after a partial filesystem write or later input failure.
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "stage.json").write_text(json.dumps({"status": "OWNED",
        "model": MODEL,
        "source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "simulator": simulator, "scope": "Original SDK provider; secret only in owned private input",
        "credential_exported": False}, indent=2) + "\n", encoding="utf-8")
    target = container(simulator) / "Library/Application Support/HanlinLiveProviderAcceptance"
    target.mkdir(mode=0o700, parents=True, exist_ok=False)
    file = target / "provider.json"
    descriptor = os.open(file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as output:
        json.dump({"apiKey": key, "model": MODEL}, output)
    print("Existing live provider credential staged privately; no secret in launch arguments or artifacts.")


def finish():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    proof = {"status": "NOT_RUN", "scope": "Original iOS app, live Gemini, original CPython and persisted conversation",
             "model": MODEL, "selector": SELECTOR, "credential_exported": False}
    staged = EVIDENCE / "stage.json"
    try:
        if not staged.exists():
            raise RuntimeError("Live credential stage did not complete")
        simulator = owned_simulator()
        data = container(simulator)
        log = (LOG / "08-nativescript-production-ui-tests.log").read_text(encoding="utf-8", errors="replace")
        nonces = set(re.findall(r"HANLIN_LIVE_PROVIDER_CHALLENGE=([A-Fa-f0-9-]{36})", log))
        completed = set(re.findall(r"HANLIN_LIVE_PROVIDER_COMPLETED=([A-Fa-f0-9-]{36})", log))
        if len(nonces) != 1 or completed != nonces:
            raise RuntimeError("The live UI scenario did not complete its unique original conversation")
        nonce = next(iter(nonces))
        expected = "LIVE_HANLIN_" + nonce + ":3.14.6:86817"
        witnesses = []
        jobs = data / "Library/Application Support/HanlinRuntime/v1/jobs/localPython"
        for file in jobs.glob("*/job.json"):
            record = json.loads(file.read_text(encoding="utf-8"))
            result = record.get("result") or {}
            if expected not in result.get("stdout", ""):
                continue
            if record.get("state") != "completed" or result.get("exitCode") != 0 or result.get("wasCancelled") or result.get("didTimeOut"):
                raise RuntimeError("The observed original Python job did not finish successfully")
            witnesses.append({"execution_id": record["executionID"], "state": record["state"],
                "exit_code": result["exitCode"], "stdout": result["stdout"],
                "job_receipt_sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
        if len(witnesses) != 1:
            raise RuntimeError("Exactly one actual original Python job must contain the unique live challenge")
        tests = LOG / "08-nativescript-production-ui-test-results.json"
        call([sys.executable, "Scripts/CI/verify_selected_tests.py", "--results", str(tests), "--selectors", SELECTOR])
        nodes = list(json.loads(tests.read_text(encoding="utf-8")).get("testNodes", []))
        cases = []
        while nodes:
            node = nodes.pop()
            nodes.extend(node.get("children", []))
            if node.get("nodeType") == "Test Case":
                cases.append(node)
        if len(cases) != 1 or cases[0].get("result") != "Passed":
            raise RuntimeError("The exact live native case must pass once with zero failed or skipped cases")
        shutil.copy2(tests, EVIDENCE / "native-test-results.json")
        result_bundle = LOG / "NativeScriptProductionE2EResult.xcresult"
        summary = call(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle)])
        (EVIDENCE / "native-summary.json").write_text(summary.stdout, encoding="utf-8")
        proof.update(status="EXECUTED_PASS", conversation_id=nonce, runtime_jobs=witnesses,
            transport="Canonical GoogleProvider via HanlinChatEngine; mock provider flags absent",
            source_sha=json.loads(staged.read_text(encoding="utf-8"))["source_sha"])
    except Exception as error:
        proof.update(status="NOT_ACCEPTED", error=str(error))
        tests = LOG / "08-nativescript-production-ui-test-results.json"
        if tests.is_file():
            shutil.copy2(tests, EVIDENCE / "native-test-results.json")
    finally:
        if staged.exists():
            try:
                simulator = owned_simulator()
                # Only this fresh CI device ever received the live account.
                # Its private database is not retained or exported.
                call(["xcrun", "simctl", "shutdown", simulator], 30, required=False)
                call(["xcrun", "simctl", "delete", simulator], 60)
                proof["credential_cleanup"] = "OWNED_SIMULATOR_REMOVED"
            except Exception as error:
                proof.update(status="NOT_ACCEPTED", credential_cleanup="FAILED", cleanup_error=str(error))
        else:
            proof["credential_cleanup"] = "NO_CREDENTIAL_STAGED"
        (EVIDENCE / "acceptance.json").write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
        key = os.environ.get("HANLIN_LIVE_GEMINI_API_KEY", "").encode()
        safe = bool(key) or not staged.exists()
        for file in EVIDENCE.rglob("*"):
            if file.is_file() and key and key in file.read_bytes():
                file.unlink()
                safe = False
        if safe and os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                output.write("sanitized=true\n")
        if not safe:
            raise RuntimeError("Live evidence is not sanitized; artifact upload is rejected")
    print(json.dumps({k:proof.get(k) for k in ["status", "model", "credential_cleanup", "error"]}))
    return 0 if proof["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["stage"]:
        stage()
    elif sys.argv[1:] == ["finish"]:
        sys.exit(finish())
    else:
        raise SystemExit("Expected stage or finish")
