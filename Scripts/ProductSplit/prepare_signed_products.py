"""Archive/export the original products using the owner's existing local identity.

No upload, tester invitation, notification, profile revocation or device registration.
Build unsigned device archives, then export using only the existing distribution
certificate. No development identity is created, and no private key is exported
or backed up. Secrets stay in a temporary private directory/keychain; retained logs
redact credential identifiers and tokens.
"""
from __future__ import annotations
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

from audit_release_resources import ROLES, certificate, decode, evaluate_profile
from resolve_signing_profiles import (
    resolve_original_profiles, install_profile, remove_installed_profiles,
)

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ["SPLIT_EVIDENCE"]) / "signed-products"

def main():
    OUT.mkdir(parents=True, exist_ok=False)
    state = {"sha": os.environ["GITHUB_SHA"], "run_id": os.environ["GITHUB_RUN_ID"],
             "status": "NOT_RUN", "products": [], "physical_device": "NOT_RUN",
             "publication": "NOT_REQUESTED", "release_decision": "NO_GO",
             "scope": "Actual original iOS device archives and local App Store export only; separate product/device acceptance gates still apply."}
    private_values = [os.environ.get(k, "") for k in
        ["ASC_KEY_P8", "ASC_KEY_ID", "ASC_ISSUER_ID", "APPLE_TEAM_ID",
         "APPLE_CERTIFICATE_P12_B64", "APPLE_CERTIFICATE_PASSWORD"]]
    commands = []

    def sanitize(text):
        for value in sorted((v for v in private_values if v), key=len, reverse=True):
            text = text.replace(value, "[REDACTED]")
        text = re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
                      "[PRIVATE KEY REDACTED]", text, flags=re.S)
        return re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b",
                      "[JWT REDACTED]", text)

    with tempfile.TemporaryDirectory(prefix="hanlin-authorized-signing-", dir=os.environ["RUNNER_TEMP"]) as directory:
        folder = Path(directory)
        folder.chmod(0o700)
        keychain = folder / "owner.keychain-db"
        old_default = None
        old_search = None
        installed_profiles = []

        def run(argv, label, timeout=60, required=True):
            started = time.monotonic()
            raw = folder / (label + ".raw")
            with raw.open("wb") as stream:
                try:
                    process = subprocess.run([str(v) for v in argv], cwd=ROOT,
                                             stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
                    result = process.returncode
                except subprocess.TimeoutExpired:
                    result = -1
            safe = sanitize(raw.read_text(errors="replace"))
            raw.unlink(missing_ok=True)
            target = OUT / (label + ".log")
            target.write_text(safe, encoding="utf-8")
            commands.append({"operation": label, "exit": result, "seconds": time.monotonic() - started,
                             "log_sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
            if result and required:
                raise RuntimeError(label + " failed; see sanitized log (exit " + str(result) + ")")
            return result, safe

        def quiet(argv):
            result = subprocess.run([str(v) for v in argv], capture_output=True, timeout=30)
            if result.returncode:
                raise RuntimeError("Private keychain setup/cleanup operation failed")
            return result.stdout.decode().strip()

        try:
            required = ["APPLE_TEAM_ID", "APPLE_CERTIFICATE_P12_B64", "APPLE_CERTIFICATE_PASSWORD",
                        "ASC_KEY_P8", "ASC_KEY_ID", "ASC_ISSUER_ID"]
            missing = [key for key in required if not os.environ.get(key)]
            if missing:
                raise RuntimeError("Missing secret names: " + ", ".join(missing))
            if os.environ.get("GITHUB_REPOSITORY") != "davidpovarsky/hanlin-ai":
                raise RuntimeError("Signing is scoped to the owner's existing repository")
            cert, cert_sha = certificate()
            state["existing_distribution_identity"] = cert
            if cert["status"] != "READY_RESOURCE":
                raise RuntimeError("Existing distribution identity failed the resource checks")
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates
            _, distribution_cert, _ = load_key_and_certificates(
                decode(os.environ["APPLE_CERTIFICATE_P12_B64"]),
                os.environ["APPLE_CERTIFICATE_PASSWORD"].encode())
            # Export must use this already-existing identity, never request a new one.
            distribution_identity = distribution_cert.fingerprint(hashes.SHA1()).hex().upper()
            cert_path = folder / "distribution.p12"
            cert_path.write_bytes(decode(os.environ["APPLE_CERTIFICATE_P12_B64"]))
            cert_path.chmod(0o600)
            password = secrets.token_hex(24)
            private_values.append(password)
            old_default = shlex.split(quiet(["security", "default-keychain", "-d", "user"]))[0]
            old_search = shlex.split(quiet(["security", "list-keychains", "-d", "user"]))
            quiet(["security", "create-keychain", "-p", password, keychain])
            quiet(["security", "set-keychain-settings", "-lut", "10800", keychain])
            quiet(["security", "unlock-keychain", "-p", password, keychain])
            quiet(["security", "import", cert_path, "-P", os.environ["APPLE_CERTIFICATE_PASSWORD"],
                   "-T", "/usr/bin/codesign", "-f", "pkcs12", "-k", keychain])
            quiet(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                   "-s", "-k", password, keychain])
            quiet(["security", "list-keychains", "-d", "user", "-s", keychain, *old_search])
            quiet(["security", "default-keychain", "-d", "user", "-s", keychain])
            cert_path.unlink()
            identities = quiet(["security", "find-identity", "-v", "-p", "codesigning", keychain])
            if not re.search(r'(?m)^\s*\d+\)\s+' + distribution_identity + r'\s+"', identities):
                raise RuntimeError("The existing distribution identity is not trusted for local code signing")
            state["existing_distribution_identity"]["os_codesigning_trust"] = "VERIFIED"
            state["provisioning_profiles"] = []
            profiles = resolve_original_profiles(cert_sha, folder, state["provisioning_profiles"])
            # Xcode's current cache and the established legacy cache both receive
            # the same verified bytes. Cleanup removes only this job's own files.
            profile_directories = [
                Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                Path.home() / "Library/MobileDevice/Provisioning Profiles",
            ]
            for profile in profiles:
                install_profile(profile, profile_directories, installed_profiles)
            profile_mapping = {profile["bundle"]: profile["uuid"] for profile in profiles}
            _, sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], "device-sdk")
            if int(sdk.strip().split(".")[0]) != 27:
                raise RuntimeError("The current stable iOS 27 SDK is required")
            run(["xcodebuild", "-version"], "xcode-version")
            run(["xcrun", "swiftc", "--version"], "swift-version")
            derived = ROOT / "build/ReleaseDerivedData"
            packages = ROOT / "build/SourcePackages"
            common = ["xcodebuild", "-project", "AI_HLY.xcodeproj",
                      "-clonedSourcePackagesDirPath", packages,
                      "-skipPackagePluginValidation", "-skipMacroValidation"]
            run(common + ["-scheme", "AI_HLY", "-resolvePackageDependencies"], "resolve-original-packages", 600)
            run([sys.executable, "Scripts/CI/stage_a2ui_schemas.py", "--source-packages-path", packages,
                 "--derived-data-path", derived, "--evidence", OUT / "original-a2ui-schemas"],
                 "original-schema-generator", 360)
            export_options = folder / "ExportOptions.plist"
            options = {
                "method": "app-store-connect", "destination": "export",
                "signingStyle": "manual", "teamID": os.environ["APPLE_TEAM_ID"],
                "signingCertificate": distribution_identity, "uploadSymbols": False,
                "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True
            }
            for role, scheme, bundle in [("miniapps", "HanlinMiniApps", "com.itorah.hanlinminiapps"),
                                         ("ai", "AI_HLY", "com.itorah.chavrusachat")]:
                product = {"role": role, "bundle_id": bundle, "archive": "NOT_RUN", "export": "NOT_RUN",
                           "entitlements": "NOT_RUN"}
                state["products"].append(product)
                selected_bundles = {b for r, b, _, _ in ROLES
                                    if (r == "miniapps") == (role == "miniapps")}
                options["provisioningProfiles"] = {b: profile_mapping[b] for b in selected_bundles}
                export_options.write_bytes(plistlib.dumps(options))
                export_options.chmod(0o600)
                archive = ROOT / "build/ReleaseArchives" / (scheme + ".xcarchive")
                archive.parent.mkdir(exist_ok=True)
                export = OUT / role
                result, _ = run(common + ["-scheme", scheme, "-configuration", "Release",
                    "-destination", "generic/platform=iOS", "-derivedDataPath", derived,
                    "-archivePath", archive, "archive",
                    "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGN_IDENTITY=", "PROVISIONING_PROFILE_SPECIFIER=",
                    "PROVISIONING_PROFILE="],
                    role + "-archive", 3300, required=False)
                product["archive"] = "EXECUTED_PASS" if result == 0 else "EXECUTED_FAIL"
                if result:
                    continue
                info = plistlib.loads((archive / "Info.plist").read_bytes())
                application = info.get("ApplicationProperties", {})
                if application.get("CFBundleIdentifier") != bundle:
                    raise RuntimeError("Archive identity does not match the original product")
                product["version"] = application.get("CFBundleShortVersionString")
                product["build"] = application.get("CFBundleVersion")
                result, _ = run(["xcodebuild", "-exportArchive", "-archivePath", archive,
                    "-exportPath", export, "-exportOptionsPlist", export_options],
                    role + "-export", 600, required=False)
                product["export"] = "EXECUTED_PASS" if result == 0 else "EXECUTED_FAIL"
                if result:
                    continue
                ipas = list(export.glob("*.ipa"))
                if len(ipas) != 1:
                    raise RuntimeError("Export must contain exactly one product IPA")
                product["ipa_sha256"] = hashlib.sha256(ipas[0].read_bytes()).hexdigest()
                product["ipa_file"] = str(ipas[0].relative_to(OUT))
                extract = folder / (role + "-export")
                with zipfile.ZipFile(ipas[0]) as package:
                    for member in package.infolist():
                        if member.filename.startswith("/") or ".." in Path(member.filename).parts:
                            raise RuntimeError("Unsafe IPA member")
                    package.extractall(extract)
                apps = list((extract / "Payload").glob("*.app"))
                if len(apps) != 1:
                    raise RuntimeError("Exported product has an ambiguous app payload")
                run(["codesign", "--verify", "--deep", "--strict", apps[0]], role + "-signature")
                targets = [apps[0], *apps[0].glob("PlugIns/*.appex")]
                expected = {b: (name, path) for name, b, _, path in ROLES if name != "miniapps"} if role == "ai" else {
                    b: (name, path) for name, b, _, path in ROLES if name == "miniapps"}
                observed = {}
                for target in targets:
                    bundle_info = plistlib.loads((target / "Info.plist").read_bytes())
                    identity = bundle_info["CFBundleIdentifier"]
                    if identity not in expected:
                        raise RuntimeError("Unexpected signed extension or product")
                    name, source = expected[identity]
                    decoded = subprocess.run(["security", "cms", "-D", "-i", str(target / "embedded.mobileprovision")],
                                             capture_output=True, timeout=20, check=True)
                    check = evaluate_profile(plistlib.loads(decoded.stdout),
                        plistlib.loads((ROOT / source).read_bytes()), identity,
                        os.environ["APPLE_TEAM_ID"], cert_sha, datetime.now(timezone.utc))
                    signed = subprocess.run(["codesign", "--display", "--entitlements", "-", "--xml", str(target)],
                                            capture_output=True, timeout=20, check=True)
                    raw_entitlements = signed.stdout + signed.stderr
                    start = raw_entitlements.find(b"<?xml")
                    end = raw_entitlements.find(b"</plist>", start)
                    if start < 0 or end < start:
                        raise RuntimeError("Signed product did not expose its real entitlements")
                    signed_profile = plistlib.loads(decoded.stdout)
                    signed_profile["Entitlements"] = plistlib.loads(raw_entitlements[start:end + len(b"</plist>")])
                    actual = evaluate_profile(signed_profile, plistlib.loads((ROOT / source).read_bytes()),
                                              identity, os.environ["APPLE_TEAM_ID"], cert_sha,
                                              datetime.now(timezone.utc))
                    check["actual_signature_entitlements"] = actual["checks"]["required_entitlements_covered"]
                    check["actual_signature_identity"] = actual["checks"]["bundle_matches"]
                    if actual["status"] != "READY_RESOURCE":
                        check["status"] = "BLOCKED"
                        check["actual_signature_missing_keys"] = actual["missing_or_mismatched_entitlement_keys"]
                    observed[identity] = check
                if set(observed) != set(expected) or any(v["status"] != "READY_RESOURCE" for v in observed.values()):
                    product["profile_checks"] = observed
                    raise RuntimeError("Exported profiles do not cover every original product entitlement")
                product.update(entitlements="EXECUTED_PASS", profile_checks=observed)
            state["status"] = "EXECUTED_PASS" if len(state["products"]) == 2 and all(
                p["entitlements"] == "EXECUTED_PASS" for p in state["products"]) else "SIGNING_OR_BUILD_FAILED"
        except Exception as error:
            state["error"] = sanitize(str(error))
            if state["status"] == "NOT_RUN":
                state["status"] = "PREPARATION_FAILED"
        finally:
            cleanup_errors = []
            try:
                remove_installed_profiles(installed_profiles)
            except Exception as error:
                cleanup_errors.append(sanitize(str(error)))
            for argv in [
                ["security", "default-keychain", "-d", "user", "-s", old_default] if old_default else None,
                ["security", "list-keychains", "-d", "user", "-s", *old_search] if old_search else None,
                ["security", "delete-keychain", keychain] if keychain.exists() else None
            ]:
                if argv:
                    try: quiet(argv)
                    except Exception: cleanup_errors.append("keychain restore/cleanup failed")
            state["cleanup"] = "PASS" if not cleanup_errors else "FAILED"
            if cleanup_errors:
                state["cleanup_errors"] = cleanup_errors
            (OUT / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
            (OUT / "acceptance.json").write_text(json.dumps(state, indent=2) + "\n")
            shutil.copy2(OUT / "acceptance.json", OUT.parent / "acceptance.json")
            print(json.dumps(state))
    return 0 if state["status"] == "EXECUTED_PASS" and state["cleanup"] == "PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
