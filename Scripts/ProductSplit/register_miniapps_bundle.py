"""Register the already-declared MiniApps product using the existing Apple account key.

This manual operation sends only the original identifier/name and the two
documented capability types. It does not create/export credentials, profiles,
App Store listings, builds, notifications or a release.
"""
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "com.itorah.hanlinminiapps"
NAME = "Hanlin MiniApps"
ALLOWED_CAPABILITIES = ("APP_GROUPS", "HEALTHKIT")

class AppleFailure(Exception):
    def __init__(self, status, codes=()):
        self.status = status
        self.codes = list(codes)
        super().__init__(status)

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def request(path, method="GET", parameters=None, body=None):
    import jwt
    if method == "POST" and path not in {"/v1/bundleIds", "/v1/bundleIdCapabilities"}:
        raise ValueError("Mutation outside the reviewed registration scope")
    if not path.startswith("/v1/") or "?" in path or "://" in path:
        raise ValueError("Invalid fixed-origin path")
    now = int(time.time())
    key = base64.b64decode("".join(os.environ["ASC_KEY_P8"].split()), validate=True)
    token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now,
        "exp": now + 600, "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    url = "https://api.appstoreconnect.apple.com" + path
    if parameters:
        url += "?" + urllib.parse.urlencode(parameters)
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    call = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(),
        headers=headers, method=method)
    try:
        with urllib.request.build_opener(NoRedirect).open(call, timeout=30) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise AppleFailure("RESPONSE_TOO_LARGE")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        try:
            detail = json.loads(error.read(16384))
            codes = [str(item.get("code", ""))[:120] for item in detail.get("errors", [])]
        except Exception:
            codes = []
        raise AppleFailure("HTTP_" + str(error.code), codes) from None

def find_bundle():
    result = request("/v1/bundleIds", parameters={"filter[identifier]": BUNDLE,
        "fields[bundleIds]": "identifier,name,platform", "limit": 200})
    if result.get("links", {}).get("next"):
        raise AppleFailure("INCOMPLETE_EXACT_LOOKUP")
    found = [item for item in result.get("data", [])
        if item.get("attributes", {}).get("identifier") == BUNDLE
        and item.get("attributes", {}).get("platform") in {"IOS", "UNIVERSAL"}]
    if len(found) > 1:
        raise AppleFailure("AMBIGUOUS_EXACT_IDENTITY")
    return found

def main():
    out = ROOT / "build/miniapps-registration"
    out.mkdir(parents=True, exist_ok=True)
    report = {"source_sha": os.environ.get("GITHUB_SHA"), "run_id": os.environ.get("GITHUB_RUN_ID"),
        "timestamp": datetime.now(timezone.utc).isoformat(), "bundle_id": BUNDLE,
        "product_name": NAME, "status": "BLOCKED", "operations": [],
        "signing_ready": False, "release_decision": "NO_GO",
        "scope": "Original MiniApps identifier and documented APP_GROUPS/HEALTHKIT capability toggles only; no signing, publication or credentials transfer"}
    try:
        if os.environ.get("EXPECTED_MINIAPPS_BUNDLE") != BUNDLE:
            raise ValueError("The manual input must identify the original MiniApps product")
        project = (ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text()
        if BUNDLE not in project:
            raise ValueError("Original shipping target is missing")
        entitlements_path = ROOT / "HanlinMiniAppsApp/HanlinMiniApps.entitlements"
        entitlements = plistlib.loads(entitlements_path.read_bytes())
        if entitlements.get("com.apple.developer.healthkit") is not True or set(
            entitlements.get("com.apple.security.application-groups", [])) != {
                "group.com.itorah.chavrusachat", "group.com.itorah.shared"}:
            raise ValueError("Declared capabilities differ from the reviewed source")
        report["entitlements_sha256"] = hashlib.sha256(entitlements_path.read_bytes()).hexdigest()
        found = find_bundle()
        if not found:
            try:
                request("/v1/bundleIds", "POST", body={"data": {"type": "bundleIds",
                    "attributes": {"identifier": BUNDLE, "name": NAME, "platform": "IOS"}}})
                report["operations"].append({"operation": "REGISTER_ORIGINAL_BUNDLE_ID", "status": "API_ACCEPTED"})
            except Exception as error:
                report["operations"].append({"operation": "REGISTER_ORIGINAL_BUNDLE_ID",
                    "status": error.status if isinstance(error, AppleFailure) else "OUTCOME_UNKNOWN",
                    "codes": error.codes if isinstance(error, AppleFailure) else []})
                # Never retry a write after an uncertain response. Reconcile by GET.
            found = find_bundle()
        if len(found) != 1:
            raise AppleFailure("ORIGINAL_BUNDLE_NOT_OBSERVED")
        bundle = found[0]
        report["observed_bundle"] = {k: bundle["attributes"].get(k) for k in ["identifier", "name", "platform"]}
        report["status"] = "ORIGINAL_BUNDLE_OBSERVED"
        path = "/v1/bundleIds/" + bundle["id"] + "/bundleIdCapabilities"
        observed = request(path)
        if observed.get("links", {}).get("next"):
            raise AppleFailure("INCOMPLETE_CAPABILITY_LOOKUP")
        capabilities = {item["attributes"]["capabilityType"] for item in observed.get("data", [])}
        for capability in ALLOWED_CAPABILITIES:
            if capability in capabilities:
                continue
            try:
                request("/v1/bundleIdCapabilities", "POST", body={"data": {"type": "bundleIdCapabilities",
                    "attributes": {"capabilityType": capability},
                    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}}}}})
                report["operations"].append({"operation": capability, "status": "API_ACCEPTED"})
            except Exception as error:
                report["operations"].append({"operation": capability,
                    "status": error.status if isinstance(error, AppleFailure) else "OUTCOME_UNKNOWN",
                    "codes": error.codes if isinstance(error, AppleFailure) else []})
        final = request(path)
        if final.get("links", {}).get("next"):
            raise AppleFailure("INCOMPLETE_CAPABILITY_READBACK")
        report["observed_capabilities"] = sorted(item["attributes"]["capabilityType"] for item in final.get("data", []))
        report["registration_scope_passed"] = set(ALLOWED_CAPABILITIES).issubset(report["observed_capabilities"])
        report["status"] = "REGISTRATION_SCOPE_VERIFIED" if report["registration_scope_passed"] else "PARTIAL_REGISTRATION"
    except Exception as error:
        report["error"] = {"status": error.status if isinstance(error, AppleFailure) else type(error).__name__,
            "codes": error.codes if isinstance(error, AppleFailure) else []}
    finally:
        report["remaining"] = [
            "Assign both original App Groups in the authorized Apple portal/Xcode configuration",
            "Enable the target's required Extended Virtual Addressing, WeatherKit and Time Sensitive Notifications",
            "Create a compatible profile for the existing Distribution certificate, verify every requested entitlement",
            "Create the separate App Store Connect record and complete original native/device/release gates"]
        (out / "sanitized-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
    return 0 if report.get("registration_scope_passed") else 1

if __name__ == "__main__":
    raise SystemExit(main())
