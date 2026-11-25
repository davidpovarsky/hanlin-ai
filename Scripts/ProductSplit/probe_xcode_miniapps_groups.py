#!/usr/bin/env python3
"""One actual Xcode account-resource probe, never product acceptance or upload."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import time

from signing_profile_preflight import _write_probe_project

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--entitlements", required=True)
    parser.add_argument("--expected-entitlements-sha256", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--distribution-export", action="store_true",
                        help="Use the installed distribution identity after an unsigned local probe archive")
    args = parser.parse_args()
    if os.geteuid() == 0 or Path.home() != Path("/Users/m1"):
        raise SystemExit("Use the existing normal m1 SSH signing session")
    if not re.fullmatch("[0-9a-f]{40}", args.source_sha):
        raise SystemExit("Exact source SHA required")
    entitlements = Path(args.entitlements).resolve()
    raw = entitlements.read_bytes()
    if hashlib.sha256(raw).hexdigest() != args.expected_entitlements_sha256:
        raise SystemExit("Original source entitlement identity changed")
    required = plistlib.loads(raw)
    if required != {"com.apple.security.application-groups":
                    ["group.com.itorah.chavrusachat", "group.com.itorah.shared"]}:
        raise SystemExit("Probe is limited to the original MiniApps Share entitlement dictionary")
    key = Path.home() / ".appstoreconnect/private_keys/AuthKey_BMFQPP6252.p8"
    if not key.is_file():
        raise SystemExit("The installed authorized ASC key is unavailable")
    work = Path(args.directory).resolve()
    work.mkdir(parents=True, exist_ok=False)
    work.chmod(0o700)
    started = datetime.now(timezone.utc).isoformat()
    free_before = os.statvfs("/System/Volumes/Data")
    free_before = free_before.f_bavail * free_before.f_frsize
    # This one-C-file project has no dependencies, simulator or shared mutable cache.
    project = _write_probe_project(work)
    identity_before = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        text=True, capture_output=True, check=True).stdout
    identities_before = sorted(set(re.findall(r"\b[0-9A-F]{40}\b", identity_before)))
    if "644940FCF25D1730DBD1BF7596AEBA7229E2B8FD" not in identities_before:
        raise SystemExit("The verified existing distribution identity is not available")
    authentication = ["-allowProvisioningUpdates", "-authenticationKeyPath", str(key),
                      "-authenticationKeyID", "BMFQPP6252",
                      "-authenticationKeyIssuerID", "b5ac6a24-597d-4c46-924e-712ad41bf667"]
    argv = ["xcodebuild", "-project", str(project), "-scheme", "ProfileDiscovery",
            "-configuration", "Release", "-destination", "generic/platform=iOS",
            "-derivedDataPath", str(work / "DerivedData"),
            "-archivePath", str(work / "ProfileDiscovery.xcarchive"), "archive",
            "PRODUCT_BUNDLE_IDENTIFIER=com.itorah.hanlinminiapps.share",
            "CODE_SIGN_STYLE=Automatic", "DEVELOPMENT_TEAM=NA6HPWARQ2",
            "CODE_SIGN_ENTITLEMENTS=" + str(entitlements), "APS_ENVIRONMENT=production",
            "COMPILER_INDEX_STORE_ENABLE=NO"]
    if args.distribution_export:
        # Avoid asking Apple for a new development identity. No account request
        # is permitted during this dependency-free unsigned discovery archive.
        argv += ["CODE_SIGNING_ALLOWED=NO"]
    else:
        argv += authentication
    receipt = {
        "scope": "REAL_XCODE_ACCOUNT_RESOURCE_PROBE_ONLY_NOT_ORIGINAL_APP_ACCEPTANCE",
        "started_at": started, "source_sha": args.source_sha,
        "source_entitlements_sha256": args.expected_entitlements_sha256,
        "bundle_id": "com.itorah.hanlinminiapps.share", "team": "NA6HPWARQ2",
        "required_entitlements": required, "user": "m1", "effective_uid": os.geteuid(),
        "command": argv, "identities_before": identities_before,
        "mode": "existing-distribution-export" if args.distribution_export else "automatic-development",
        "free_bytes_before": free_before, "status": "RUNNING",
        "deadline_seconds": 180, "no_upload_or_install_requested": True,
    }
    result = work / "receipt.json"
    result.write_text(json.dumps(receipt, indent=2) + "\n")
    log_path = work / "xcodebuild-private.log"
    deadline = time.monotonic() + 180
    receipt["stages"] = []
    with log_path.open("xb") as log:
        os.chmod(log_path, 0o600)

        def owned_stage(command, label):
            stage = {"label": label, "command": command,
                     "started_at": datetime.now(timezone.utc).isoformat()}
            receipt["stages"].append(stage)
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                stage.update(status="NOT_STARTED_DEADLINE", exit_code=-1)
                return -1
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            stage["owned_pid"] = process.pid
            result.write_text(json.dumps(receipt, indent=2) + "\n")
            try:
                code = process.wait(timeout=remaining)
                stage.update(exit_code=code, status="EXECUTED_PASS" if code == 0 else "EXECUTED_FAIL")
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = process.returncode
                stage.update(exit_code=code, status="TIMED_OUT_RECONCILE_APPLE_STATE_BEFORE_RETRY")
            stage["finished_at"] = datetime.now(timezone.utc).isoformat()
            result.write_text(json.dumps(receipt, indent=2) + "\n")
            return code

        code = owned_stage(argv, "unsigned-discovery-archive" if args.distribution_export
                           else "automatic-development-provisioning")
        if code == 0 and args.distribution_export:
            app = work / "ProfileDiscovery.xcarchive/Products/Applications/ProfileDiscovery.app"
            # An actual local ad-hoc signature carries the exact original source
            # entitlements into Xcode's distribution-profile discovery. It is
            # never represented as an Apple distribution signature or product.
            code = owned_stage(["codesign", "--force", "--sign", "-", "--timestamp=none",
                                "--entitlements", str(entitlements), str(app)],
                               "local-ad-hoc-entitlement-discovery-only")
            if code == 0:
                options = work / "ExportOptions.plist"
                options.write_bytes(plistlib.dumps({
                    "method": "app-store-connect", "destination": "export",
                    "signingStyle": "automatic", "teamID": "NA6HPWARQ2",
                    "signingCertificate": "644940FCF25D1730DBD1BF7596AEBA7229E2B8FD",
                    "uploadSymbols": False, "manageAppVersionAndBuildNumber": False,
                    "stripSwiftSymbols": True,
                }))
                code = owned_stage(
                    ["xcodebuild", "-exportArchive", "-archivePath", str(work / "ProfileDiscovery.xcarchive"),
                     "-exportPath", str(work / "export"), "-exportOptionsPlist", str(options),
                     *authentication],
                    "distribution-export-with-existing-identity")
        receipt.update(exit_code=code,
                       status=("DISTRIBUTION_RESOURCE_PROBE_EXPORTED" if args.distribution_export
                               else "PROBE_ARCHIVED") if code == 0 else "PROBE_FAILED")
    raw_log = log_path.read_bytes()
    safe_log = raw_log.decode("utf-8", errors="replace")
    safe_log = re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[REDACTED_JWT]", safe_log)
    safe_log = re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
                      "[REDACTED_PRIVATE_KEY]", safe_log, flags=re.S)
    safe_path = work / "xcodebuild-sanitized.txt"
    safe_path.write_text(safe_log)
    after = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                           text=True, capture_output=True, check=True).stdout
    identities_after = sorted(set(re.findall(r"\b[0-9A-F]{40}\b", after)))
    free_after = os.statvfs("/System/Volumes/Data")
    receipt.update(
        finished_at=datetime.now(timezone.utc).isoformat(),
        identities_after=identities_after,
        original_identities_preserved=set(identities_before).issubset(identities_after),
        newly_available_identities=sorted(set(identities_after) - set(identities_before)),
        private_log_sha256=hashlib.sha256(raw_log).hexdigest(),
        sanitized_log_sha256=hashlib.sha256(safe_path.read_bytes()).hexdigest(),
        free_bytes_after=free_after.f_bavail * free_after.f_frsize,
        diagnostics=[line for line in safe_log.splitlines()
                     if any(word in line.lower() for word in ["error:", "failed", "provision", "certificate", "account"])
                     and len(line) < 1500][-35:],
    )
    result.write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))
    return 0 if receipt["exit_code"] == 0 else 1

if __name__ == "__main__":
    raise SystemExit(main())
