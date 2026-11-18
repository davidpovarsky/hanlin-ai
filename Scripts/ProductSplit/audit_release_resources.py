"""Read-only release resource audit; no signing, installation, upload or notification.

Only sanitized facts leave memory. Private keys, decoded profiles, device identifiers,
API tokens and raw Apple responses are never retained in artifacts.
"""
from __future__ import annotations
import base64
from datetime import datetime, timezone
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ROLES = [
    ("ai", "com.itorah.chavrusachat", "APPLE_MAIN_PROVISIONING_PROFILE_B64", "AI_HLY/AI_HLY.entitlements"),
    ("miniapps", "com.itorah.hanlinminiapps", "APPLE_MINIAPPS_PROVISIONING_PROFILE_B64", "HanlinMiniAppsApp/HanlinMiniApps.entitlements"),
    ("share", "com.itorah.chavrusachat.share", "APPLE_SHARE_PROVISIONING_PROFILE_B64", "ChavrusaChatShare/ChavrusaChatShare.entitlements"),
    ("widgets", "com.itorah.chavrusachat.widgets", "APPLE_WIDGETS_PROVISIONING_PROFILE_B64", "HanlinScriptingWidgets/HanlinScriptingWidgets.entitlements"),
    ("translation", "com.itorah.chavrusachat.translation-provider", "APPLE_TRANSLATION_PROVISIONING_PROFILE_B64", "ChavrusaChatTranslationProvider/ChavrusaChatTranslationProvider.entitlements"),
    ("notification", "com.itorah.chavrusachat.notification-service", "APPLE_NOTIFICATION_SERVICE_PROVISIONING_PROFILE_B64", "ChavrusaChatNotificationService/ChavrusaChatNotificationService.entitlements"),
]

def utc(value):
    if not isinstance(value, datetime):
        raise ValueError("Missing expiration")
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)

def decode(value):
    return base64.b64decode("".join(value.split()), validate=True)

def entitlement_allows(granted, requested):
    if isinstance(requested, bool):
        return granted is requested
    if isinstance(requested, str):
        return isinstance(granted, str) and fnmatch.fnmatchcase(requested, granted)
    if isinstance(requested, list):
        if isinstance(granted, str):
            granted = [granted]
        return isinstance(granted, list) and all(
            any(entitlement_allows(candidate, value) for candidate in granted) for value in requested)
    return type(granted) is type(requested) and granted == requested

def evaluate_profile(profile, required, bundle, team, certificate_sha, now):
    entitlements = profile.get("Entitlements", {})
    def expand(value):
        if isinstance(value, str):
            return value.replace("$(APS_ENVIRONMENT)", "production").replace("$(TeamIdentifierPrefix)", team + ".")
        if isinstance(value, list):
            return [expand(item) for item in value]
        return value
    unsupported = sorted(key for key, value in required.items()
                         if not entitlement_allows(entitlements.get(key), expand(value)))
    certificates = {hashlib.sha256(value).hexdigest() for value in profile.get("DeveloperCertificates", [])
                    if isinstance(value, bytes)}
    expiry = utc(profile.get("ExpirationDate"))
    checks = {
        "team_matches": bool(team) and team in profile.get("TeamIdentifier", []),
        "bundle_matches": entitlements.get("application-identifier") == team + "." + bundle,
        "not_expired": expiry > now,
        "distribution_profile": entitlements.get("get-task-allow") is False
            and "ProvisionedDevices" not in profile and "ProvisionsAllDevices" not in profile,
        "certificate_matches": bool(certificate_sha) and certificate_sha in certificates,
        "required_entitlements_covered": not unsupported,
    }
    return {"status": "READY_RESOURCE" if all(checks.values()) else "BLOCKED",
            "checks": checks, "expiration": expiry.isoformat(),
            "missing_or_mismatched_entitlement_keys": unsupported}

def certificate():
    encoded = os.environ.get("APPLE_CERTIFICATE_P12_B64", "")
    if not encoded:
        return {"status": "MISSING", "secret_name": "APPLE_CERTIFICATE_P12_B64"}, None
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.serialization.pkcs12 import load_key_and_certificates
        from cryptography.x509.oid import NameOID
        key, cert, _ = load_key_and_certificates(decode(encoded), os.environ.get("APPLE_CERTIFICATE_PASSWORD", "").encode())
        if key is None or cert is None:
            raise ValueError("Certificate/private key pair unavailable")
        team = os.environ.get("APPLE_TEAM_ID", "")
        teams = [a.value for a in cert.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)]
        names = [a.value for a in cert.subject.get_attributes_for_oid(NameOID.COMMON_NAME)]
        public = lambda value: value.public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
        now = datetime.now(timezone.utc)
        before, after = cert.not_valid_before_utc, cert.not_valid_after_utc
        digest = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest()
        checks = {"private_key_matches": public(key.public_key()) == public(cert.public_key()),
                  "valid_dates": before <= now < after, "team_matches": bool(team) and team in teams,
                  "distribution_identity": any(name.startswith("Apple Distribution:") for name in names)}
        return {"status": "READY_RESOURCE" if all(checks.values()) else "BLOCKED",
                "checks": checks, "expiration": after.isoformat(), "public_certificate_sha256": digest}, digest
    except Exception as error:
        return {"status": "UNREADABLE", "error_kind": type(error).__name__}, None

def profiles(cert_sha):
    result = []
    for role, bundle, secret, path in ROLES:
        item = {"role": role, "bundle_id": bundle, "secret_name": secret,
                "entitlements_path": path, "entitlements_sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest()}
        encoded = os.environ.get(secret, "")
        if not encoded:
            item["status"] = "MISSING"
        else:
            try:
                with tempfile.TemporaryDirectory(prefix="hanlin-profile-audit-") as folder:
                    profile_path = Path(folder) / "input.mobileprovision"
                    profile_path.write_bytes(decode(encoded))
                    profile_path.chmod(0o600)
                    process = subprocess.run(["security", "cms", "-D", "-i", str(profile_path)],
                                             capture_output=True, timeout=20)
                    if process.returncode:
                        raise ValueError("CMS profile could not be read")
                    decoded = plistlib.loads(process.stdout)
                item.update(evaluate_profile(decoded, plistlib.loads((ROOT / path).read_bytes()),
                    bundle, os.environ.get("APPLE_TEAM_ID", ""), cert_sha, datetime.now(timezone.utc)))
            except Exception as error:
                item.update(status="UNREADABLE", error_kind=type(error).__name__)
        result.append(item)
    return result

class AppleReadFailure(Exception):
    pass

def apple_get(path, parameters):
    # Fixed Apple origin, GET only; no redirects or mutation methods.
    import jwt
    now = int(time.time())
    token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600,
                        "aud": "appstoreconnect-v1"},
                       decode(os.environ["ASC_KEY_P8"]), algorithm="ES256",
                       headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    request = urllib.request.Request("https://api.appstoreconnect.apple.com" + path + "?" +
        urllib.parse.urlencode(parameters), headers={"Authorization": "Bearer " + token}, method="GET")
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise AppleReadFailure("RESPONSE_TOO_LARGE")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        raise AppleReadFailure("HTTP_" + str(error.code)) from None

def exact_bundles(data, bundle):
    # Apple identifier filtering can include prefix matches such as extensions.
    # Count only the actual iOS/universal product, never its sibling IDs.
    return [item for item in data.get("data", [])
            if item.get("attributes", {}).get("identifier") == bundle
            and item.get("attributes", {}).get("platform") in {"IOS", "UNIVERSAL"}]

def portal_profile_checks(profiles_data, required, bundle, cert_sha):
    candidates = [p for p in profiles_data.get("data", [])
                  if p.get("attributes", {}).get("profileType") == "IOS_APP_STORE"
                  and p.get("attributes", {}).get("profileState") == "ACTIVE"]
    checks = []
    for candidate in candidates[:8]:
        try:
            response = apple_get("/v1/profiles/" + candidate["id"], {"fields[profiles]": "profileContent"})
            encoded = response["data"]["attributes"]["profileContent"]
            with tempfile.TemporaryDirectory(prefix="hanlin-portal-profile-") as folder:
                path = Path(folder) / "input.mobileprovision"
                path.write_bytes(decode(encoded))
                path.chmod(0o600)
                result = subprocess.run(["security", "cms", "-D", "-i", str(path)],
                                        capture_output=True, timeout=20)
                if result.returncode:
                    raise ValueError("Portal CMS profile could not be read")
                profile = plistlib.loads(result.stdout)
            evaluated = evaluate_profile(profile, required, bundle, os.environ.get("APPLE_TEAM_ID", ""),
                                         cert_sha, datetime.now(timezone.utc))
            evaluated["profile_sha256"] = hashlib.sha256(decode(encoded)).hexdigest()
            checks.append(evaluated)
        except Exception as error:
            checks.append({"status": "UNREADABLE",
                           "error_kind": str(error) if isinstance(error, AppleReadFailure) else type(error).__name__})
    return {"checked_profiles": checks,
            "compatible_profile_count": sum(p.get("status") == "READY_RESOURCE" for p in checks),
            "complete": len(candidates) <= 8 and not bool(profiles_data.get("links", {}).get("next"))}

def apple_resources(cert_sha=None):
    required = ["ASC_KEY_P8", "ASC_KEY_ID", "ASC_ISSUER_ID"]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        return {"status": "MISSING", "secret_names": missing}
    result = []
    for role, bundle, _, entitlement_path in ROLES[:2]:
        item = {"role": role, "bundle_id": bundle}
        try:
            data = apple_get("/v1/apps", {"filter[bundleId]": bundle, "fields[apps]": "bundleId", "limit": 2})
            apps = data.get("data", [])
            item["visible_app_store_record_count"] = len(apps)
            if len(apps) == 1:
                builds = apple_get("/v1/builds", {"filter[app]": apps[0]["id"],
                    "fields[builds]": "version,processingState,expired", "sort": "-uploadedDate", "limit": 3})
                item["recent_builds"] = [b.get("attributes", {}) for b in builds.get("data", [])]
        except Exception as error:
            item["app_store_read_error"] = str(error) if isinstance(error, AppleReadFailure) else type(error).__name__
        try:
            data = apple_get("/v1/bundleIds", {"filter[identifier]": bundle,
                "fields[bundleIds]": "identifier,platform", "limit": 200})
            bundles = exact_bundles(data, bundle)
            item["visible_registered_bundle_count"] = len(bundles)
            item["identifier_filter_candidate_count"] = len(data.get("data", []))
            item["bundle_list_complete"] = not bool(data.get("links", {}).get("next"))
            if len(bundles) == 1 and item["bundle_list_complete"]:
                try:
                    capability_data = apple_get("/v1/bundleIds/" + bundles[0]["id"] + "/bundleIdCapabilities", {})
                    item["capability_types"] = sorted(c["attributes"]["capabilityType"]
                        for c in capability_data.get("data", []) if c.get("attributes", {}).get("capabilityType"))
                    item["capability_list_complete"] = not bool(capability_data.get("links", {}).get("next"))
                except Exception as error:
                    item["capability_read_error"] = str(error) if isinstance(error, AppleReadFailure) else type(error).__name__
                data = apple_get("/v1/bundleIds/" + bundles[0]["id"] + "/profiles",
                    {"fields[profiles]": "profileState,profileType,expirationDate", "limit": 200})
                available = [p.get("attributes", {}) for p in data.get("data", [])]
                item["app_store_profiles"] = [p for p in available if p.get("profileType") == "IOS_APP_STORE"]
                item["profile_list_complete"] = not bool(data.get("links", {}).get("next"))
                item["portal_profile_compatibility"] = portal_profile_checks(
                    data, plistlib.loads((ROOT / entitlement_path).read_bytes()), bundle, cert_sha)
        except Exception as error:
            item["developer_portal_read_error"] = str(error) if isinstance(error, AppleReadFailure) else type(error).__name__
        result.append(item)
    return {"status": "READ_ONLY_AUDIT_COMPLETE", "products": result}

def device_inventory():
    # Inventory only. No device is paired, booted, installed on, or tested.
    result = {"physical_tests": "NOT_RUN"}
    try:
        process = subprocess.run(["xcrun", "simctl", "list", "runtimes", "-j"],
                                 capture_output=True, timeout=20)
        data = json.loads(process.stdout)
        result["simulator_runtimes"] = [{"name": r.get("name"), "version": r.get("version"),
            "available": r.get("isAvailable")} for r in data.get("runtimes", [])]
    except Exception as error:
        result["simulator_inventory_error"] = type(error).__name__
    try:
        with tempfile.TemporaryDirectory(prefix="hanlin-device-inventory-") as folder:
            path = Path(folder) / "devices.json"
            process = subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", str(path)],
                                     capture_output=True, timeout=30)
            if process.returncode:
                raise ValueError("Device inventory unavailable")
            devices = json.loads(path.read_bytes()).get("result", {}).get("devices", [])
        result["visible_device_count"] = len(devices)
        result["devices"] = [{"platform": d.get("hardwareProperties", {}).get("platform"),
            "os_version": d.get("deviceProperties", {}).get("osVersionNumber"),
            "pairing_state": d.get("connectionProperties", {}).get("pairingState"),
            "transport": d.get("connectionProperties", {}).get("transportType")} for d in devices]
    except Exception as error:
        result["physical_inventory_error"] = type(error).__name__
    return result

def main():
    cert, digest = certificate()
    profile_results = profiles(digest)
    report = {
        "schema_version": 1, "source_sha": os.environ.get("GITHUB_SHA"),
        "run_id": os.environ.get("GITHUB_RUN_ID"), "timestamp": datetime.now(timezone.utc).isoformat(),
        "scope": "Read-only resource metadata; no signing, installation, upload, distribution, account change or notification.",
        "certificate": cert, "profiles": profile_results, "apple": apple_resources(digest),
        "device_inventory": device_inventory(),
        "signing_inputs_ready": cert["status"] == "READY_RESOURCE"
            and all(p["status"] == "READY_RESOURCE" for p in profile_results),
        "product_acceptance": "SEPARATE_NATIVE_GATES_REQUIRED", "release_decision": "NO_GO",
        "limitations": "Resource checks do not establish OS trust-chain validation, key revocation, a signed archive, physical-device acceptance or publication readiness.",
    }
    out = ROOT / "build/release-resource-audit"
    out.mkdir(parents=True, exist_ok=True)
    (out / "sanitized-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))

if __name__ == "__main__":
    main()
