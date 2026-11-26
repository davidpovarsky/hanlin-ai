"""Archive/export the original products using the owner's existing local identity.

No upload, tester invitation, notification, profile revocation or device registration.
Build unsigned device archives, then export using only the existing distribution
certificate. No development identity is created, and no private key is exported
or backed up. Secrets stay in a temporary private directory/keychain; retained logs
redact credential identifiers and tokens.
"""
from __future__ import annotations
import argparse
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
from extension_inventory import signing_targets_for_owner, embedded_product_bundles
from unsigned_product_archives import (
    PRODUCTS, archive_arguments, prepare_archive_inputs, create_archives, restore_archives, sha256,
    record_archive_capacity,
)
from resolve_signing_profiles import (
    resolve_original_profiles, install_profile, remove_installed_profiles,
)

from signing_profile_preflight import (
    installed_profile_receipt, retain_distribution_logs, run_profile_discovery_preflight,
    retain_owned_xcode_signing_logs, run_owned_process,
)

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(os.environ["SPLIT_EVIDENCE"]) / "signed-products"

def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--archive-only", action="store_true",
                      help="Create exact unsigned transfer archives; no signing material is read")
    mode.add_argument("--export-existing", type=Path, metavar="MANIFEST",
                      help="Export the original verified unsigned archives without rebuilding")
    parser.add_argument("--producer-receipt", type=Path)
    parser.add_argument("--archive-output", type=Path)
    parser.add_argument("--manifest-sha256")
    parser.add_argument("--expected-source", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument("--existing-identity", metavar="SHA1",
                        help="Use this already-unlocked local distribution identity; never export its key")
    options = parser.parse_args(argv)
    if options.archive_only and not options.producer_receipt:
        parser.error("--archive-only requires --producer-receipt")
    if options.export_existing and (not options.manifest_sha256 or not options.expected_source):
        parser.error("--export-existing requires --manifest-sha256 and --expected-source")
    if options.archive_only and options.existing_identity:
        parser.error("--archive-only does not use a signing identity")
    if options.export_existing and os.environ.get("SPLIT_SIGNING_PREFLIGHT_ONLY", "false").lower() == "true":
        parser.error("--export-existing cannot be combined with signing preflight only")
    return options


def installed_distribution_identity(identifier, quiet):
    """Read only the public certificate for the existing trusted keychain identity."""
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes
    from cryptography.x509.oid import NameOID

    identifier = identifier.upper()
    if not re.fullmatch(r"[0-9A-F]{40}", identifier):
        raise ValueError("Existing distribution identity must be its exact SHA1 fingerprint")
    identities = quiet(["security", "find-identity", "-v", "-p", "codesigning"])
    if not re.search(r'(?m)^\s*\d+\)\s+' + identifier + r'\s+"', identities):
        raise ValueError("Existing distribution identity is not available for local code signing")
    public_certificates = quiet(["security", "find-certificate", "-a", "-p"])
    matches = {}
    for pem in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
                          public_certificates, flags=re.S):
        cert = x509.load_pem_x509_certificate(pem.encode())
        if cert.fingerprint(hashes.SHA1()).hex().upper() == identifier:
            matches[cert.fingerprint(hashes.SHA256()).hex()] = cert
    if len(matches) != 1:
        raise ValueError("Existing keychain identity must match one public certificate")
    digest, cert = next(iter(matches.items()))
    now = datetime.now(timezone.utc)
    teams = [item.value for item in cert.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)]
    names = [item.value for item in cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)]
    checks = {"os_codesigning_trust": True,
              "valid_dates": cert.not_valid_before_utc <= now < cert.not_valid_after_utc,
              "team_matches": bool(os.environ.get("APPLE_TEAM_ID")) and os.environ["APPLE_TEAM_ID"] in teams,
              "distribution_identity": any(name.startswith("Apple Distribution:") for name in names)}
    if not all(checks.values()):
        raise ValueError("Existing local distribution certificate failed the original resource checks")
    return {"status": "READY_RESOURCE", "checks": checks, "mode": "installed-keychain",
            "expiration": cert.not_valid_after_utc.isoformat(),
            "public_certificate_sha256": digest, "os_codesigning_trust": "VERIFIED"}, digest, identifier


def main(argv=None):
    options_cli = parse_arguments(argv)
    if options_cli.archive_only:
        return create_archives(ROOT, options_cli.archive_output or OUT.parent / "unsigned-archives",
                               options_cli.producer_receipt)
    OUT.mkdir(parents=True, exist_ok=False)
    state = {"sha": options_cli.expected_source if options_cli.export_existing else os.environ["GITHUB_SHA"],
             "run_id": os.environ.get("GITHUB_RUN_ID") if options_cli.export_existing else os.environ["GITHUB_RUN_ID"],
             "status": "NOT_RUN", "products": [], "physical_device": "NOT_RUN",
             "publication": "NOT_REQUESTED", "release_decision": "NO_GO",
             "scope": "Actual original iOS device archives and local App Store export only; separate product/device acceptance gates still apply."}
    private_values = [os.environ.get(k, "") for k in
        ["ASC_KEY_P8", "ASC_KEY_ID", "ASC_ISSUER_ID", "APPLE_TEAM_ID",
         "APPLE_CERTIFICATE_P12_B64", "APPLE_CERTIFICATE_PASSWORD"]]
    commands = []
    imported_manifest = None
    imported_archives = {}
    if options_cli.export_existing:
        state["scope"] = "Export exact verified unsigned product archives with the existing identity; no product rebuild."

    def sanitize(text):
        for value in sorted((v for v in private_values if v), key=len, reverse=True):
            text = text.replace(value, "[REDACTED]")
        text = re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
                      "[PRIVATE KEY REDACTED]", text, flags=re.S)
        return re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b",
                      "[JWT REDACTED]", text)

    with tempfile.TemporaryDirectory(prefix="hanlin-authorized-signing-", dir=os.environ.get("RUNNER_TEMP")) as directory:
        folder = Path(directory)
        folder.chmod(0o700)
        keychain = folder / "owner.keychain-db"
        old_default = None
        old_search = None
        installed_profiles = []

        def run(argv, label, timeout=60, required=True):
            started = time.monotonic()
            raw = folder / (label + ".raw")
            wall_started = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
            with raw.open("wb") as stream:
                result, owned_pid = run_owned_process(argv, ROOT, stream, timeout)
            wall_ended = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S")
            raw_output = raw.read_text(errors="replace")
            safe = sanitize(raw_output)
            raw.unlink(missing_ok=True)
            target = OUT / (label + ".log")
            target.write_text(safe, encoding="utf-8")
            try:
                distribution_logs = retain_distribution_logs(
                    raw_output, OUT / (label + "-distribution-logs"), sanitize)
            except Exception as error:
                # Always retain the primary native failure even if diagnostics
                # are unavailable; never replace it with a log-copy error.
                distribution_logs = [{"status": "RETENTION_FAILED", "error": sanitize(str(error))}]
            native_signing_logs = None
            if result and Path(str(argv[0])).name == "xcodebuild":
                try:
                    native_signing_logs = retain_owned_xcode_signing_logs(
                        owned_pid, wall_started, wall_ended, OUT / (label + "-owned-signing.json"), sanitize)
                except Exception as error:
                    native_signing_logs = {"status": "RETENTION_FAILED", "error": sanitize(str(error))}
            commands.append({"operation": label, "exit": result, "seconds": time.monotonic() - started,
                             "log_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                             "distribution_logs": distribution_logs,
                             "owned_pid": owned_pid, "native_signing_logs": native_signing_logs})
            if result and required:
                raise RuntimeError(label + " failed; see sanitized log (exit " + str(result) + ")")
            return result, safe

        def quiet(argv):
            result = subprocess.run([str(v) for v in argv], capture_output=True, timeout=30)
            if result.returncode:
                raise RuntimeError("Private keychain setup/cleanup operation failed")
            return result.stdout.decode().strip()

        try:
            if options_cli.export_existing:
                head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
                if head != options_cli.expected_source:
                    raise ValueError("Export checkout does not match the original archive source")
                imported_manifest, imported_archives = restore_archives(
                    options_cli.export_existing, options_cli.manifest_sha256,
                    options_cli.expected_source, folder / "unsigned-archives")
                current_patch = subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=ROOT)
                if hashlib.sha256(current_patch).hexdigest() != imported_manifest["producer"]["sourcePatch"]["sha256"]:
                    raise ValueError("Export checkout tracked patch differs from the exact archive producer")
                for item in imported_manifest["sdkSourceInputs"]["files"]:
                    path = ROOT / item["path"]
                    if not path.resolve().is_relative_to(ROOT.resolve()) or sha256(path) != item["sha256"]:
                        raise ValueError("Export checkout SDK source differs from archive producer: " + item["path"])
                state["archive_producer"] = {
                    "source": imported_manifest["sourceCommit"],
                    "manifest_sha256": options_cli.manifest_sha256,
                    "producer": imported_manifest["producer"]}
            required = ["APPLE_TEAM_ID", "ASC_KEY_P8", "ASC_KEY_ID", "ASC_ISSUER_ID"]
            if not options_cli.existing_identity:
                required += ["APPLE_CERTIFICATE_P12_B64", "APPLE_CERTIFICATE_PASSWORD"]
            missing = [key for key in required if not os.environ.get(key)]
            if missing:
                raise RuntimeError("Missing secret names: " + ", ".join(missing))
            if os.environ.get("GITHUB_REPOSITORY") != "davidpovarsky/hanlin-ai":
                raise RuntimeError("Signing is scoped to the owner's existing repository")
            if options_cli.existing_identity:
                cert, cert_sha, distribution_identity = installed_distribution_identity(options_cli.existing_identity, quiet)
                state["existing_distribution_identity"] = cert
            else:
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
            state["installed_profile_readback"] = {}
            installed_profile_receipt(profiles, profile_directories, state["installed_profile_readback"])
            preflight_only = os.environ.get("SPLIT_SIGNING_PREFLIGHT_ONLY", "false").lower() == "true"
            _, sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], "device-sdk")
            if int(sdk.strip().split(".")[0]) != 27:
                raise RuntimeError("The current stable iOS 27 SDK is required")
            run(["xcodebuild", "-version"], "xcode-version")
            run(["xcrun", "swiftc", "--version"], "swift-version")
            state["provisioning_preflight"] = {}
            run_profile_discovery_preflight(
                folder, profiles, os.environ["APPLE_TEAM_ID"], distribution_identity,
                cert_sha, run, state["provisioning_preflight"])
            if not preflight_only and not options_cli.export_existing:
                prepare_archive_inputs(ROOT, OUT, run)
            export_options = folder / "ExportOptions.plist"
            options = {
                "method": "app-store-connect", "destination": "export",
                "signingStyle": "manual", "teamID": os.environ["APPLE_TEAM_ID"],
                "signingCertificate": distribution_identity, "uploadSymbols": False,
                "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True
            }
            product_archives = [] if preflight_only else PRODUCTS
            for role, scheme, bundle in product_archives:
                product = {"role": role, "bundle_id": bundle, "archive": "NOT_RUN", "export": "NOT_RUN",
                           "entitlements": "NOT_RUN"}
                state["products"].append(product)
                selected_bundles = {target.bundle for target in signing_targets_for_owner(role)}
                options["provisioningProfiles"] = {b: profile_mapping[b] for b in selected_bundles}
                export_options.write_bytes(plistlib.dumps(options))
                export_options.chmod(0o600)
                export = OUT / role
                if options_cli.export_existing:
                    archive = imported_archives[role]["path"]
                    product["archive"] = "REUSED_VERIFIED_ARCHIVE"
                    product["archive_sha256"] = imported_archives[role]["record"]["archiveSHA256"]
                    product["archive_tree_sha256"] = imported_archives[role]["record"]["treeSHA256"]
                else:
                    archive = ROOT / "build/ReleaseArchives" / (scheme + ".xcarchive")
                    archive.parent.mkdir(exist_ok=True)
                    capacity_before = record_archive_capacity(ROOT, OUT, role, "before-archive")
                    result, _ = run(archive_arguments(ROOT, scheme, archive),
                                    role + "-archive", 3300, required=False)
                    product["archive_capacity"] = [capacity_before,
                        record_archive_capacity(ROOT, OUT, role, "after-archive", capacity_before)]
                    product["archive"] = "EXECUTED_PASS" if result == 0 else "EXECUTED_FAIL"
                    if result:
                        continue
                info = plistlib.loads((archive / "Info.plist").read_bytes())
                application = info.get("ApplicationProperties", {})
                if application.get("CFBundleIdentifier") != bundle:
                    raise RuntimeError("Archive identity does not match the original product")
                product["version"] = application.get("CFBundleShortVersionString")
                product["build"] = application.get("CFBundleVersion")
                product["profile_cache_at_export"] = {}
                installed_profile_receipt(
                    [profile for profile in profiles if profile["bundle"] in selected_bundles],
                    profile_directories, product["profile_cache_at_export"])
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
                targets = embedded_product_bundles(apps[0])
                expected = {target.bundle: (target.role, target.entitlements)
                            for target in signing_targets_for_owner(role)}
                observed = {}
                for target in targets:
                    bundle_info = plistlib.loads((target / "Info.plist").read_bytes())
                    identity = bundle_info["CFBundleIdentifier"]
                    if identity not in expected or identity in observed:
                        raise RuntimeError("Unexpected or duplicate signed extension or product")
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
            if preflight_only:
                state["status"] = "PROVISIONING_PREFLIGHT_PASS"
                state["scope"] = "Original identity and entitlement provisioning preflight only; original product archives were not run."
            else:
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
    return 0 if state["status"] in {"EXECUTED_PASS", "PROVISIONING_PREFLIGHT_PASS"} and state["cleanup"] == "PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
