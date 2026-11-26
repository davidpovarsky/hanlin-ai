#!/usr/bin/env python3
"""Issue at most one missing real Share profile after actual Xcode reconciliation."""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
import plistlib
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import jwt
from audit_release_resources import evaluate_profile, exact_bundles
from resolve_signing_profiles import complete_items, original_certificate_id, decode_cms, resource_id

TEAM = "NA6HPWARQ2"
BUNDLE = "com.itorah.hanlinminiapps.share"
BUNDLE_RESOURCE = "WM658PXWFD"
CERTIFICATE_SHA = "5aefaf80b344410af7da85678fcb19de9a4be6885a846644df974b1ee38eba4b"
ENTITLEMENT_SHA = "cbce7e438c63d23cdcbc737379709ab6220997a2e39447dd962492a46d3930cc"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--entitlements", required=True)
    args = parser.parse_args()
    if os.geteuid() != 501 or Path.home() != Path("/Users/m1"):
        raise SystemExit("The installed normal m1 signing context is required")
    raw = Path(args.entitlements).read_bytes()
    if hashlib.sha256(raw).hexdigest() != ENTITLEMENT_SHA:
        raise SystemExit("Exact original Share entitlements changed")
    required = plistlib.loads(raw)
    work = Path(args.directory)
    work.mkdir(parents=True, exist_ok=False)
    work.chmod(0o700)
    receipt = {"scope": "ACTUAL_APPLE_PROFILE_GRANTS_ONLY_NOT_PRODUCT_SIGNING_OR_ACCEPTANCE",
               "source_sha": "9ef80a6ddfc997724360a9a34bb1d05cbf7cad40",
               "entitlements_sha256": ENTITLEMENT_SHA, "bundle": BUNDLE,
               "started_at": datetime.now(timezone.utc).isoformat(), "operations": [],
               "status": "PREFLIGHT", "existing_certificate_sha256": CERTIFICATE_SHA}
    destination = work / "receipt.json"
    def checkpoint():
        with destination.open("w") as out:
            json.dump(receipt, out, indent=2)
            out.write("\n"); out.flush(); os.fsync(out.fileno())
    checkpoint()
    key = Path.home() / ".appstoreconnect/private_keys/AuthKey_BMFQPP6252.p8"
    now = int(time.time())
    token = jwt.encode({"iss": "b5ac6a24-597d-4c46-924e-712ad41bf667", "iat": now,
                        "exp": now + 600, "aud": "appstoreconnect-v1"},
                       key.read_bytes(), algorithm="ES256",
                       headers={"kid": "BMFQPP6252", "typ": "JWT"})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    opener = urllib.request.build_opener(NoRedirect)
    def api(path, params=None, body=None):
        url = "https://api.appstoreconnect.apple.com" + path
        if params: url += "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(url,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
            method="POST" if body is not None else "GET")
        try:
            with opener.open(request, timeout=30) as response:
                content = response.read(2 * 1024 * 1024 + 1)
            if len(content) > 2 * 1024 * 1024: raise ValueError("Oversized Apple response")
            return json.loads(content)
        except urllib.error.HTTPError as error:
            raise RuntimeError("APPLE_HTTP_" + str(error.code)) from None

    try:
        bundle = api("/v1/bundleIds/" + BUNDLE_RESOURCE)["data"]
        attributes = bundle["attributes"]
        # Xcode can reconcile an existing iOS identifier as UNIVERSAL. Keep
        # the exact resource, identifier and team checks; use the same iOS or
        # universal acceptance as the audited release inventory.
        receipt["registered_bundle"] = {"resource_id": bundle.get("id"),
            "identifier": attributes.get("identifier"),
            "platform": attributes.get("platform"), "team": attributes.get("seedId")}
        checkpoint()
        if (bundle.get("id") != BUNDLE_RESOURCE
                or not exact_bundles({"data": [bundle]}, BUNDLE)
                or attributes.get("seedId") != TEAM):
            raise ValueError("Registered original bundle resource, platform or team changed")
        local = subprocess.run(["/usr/bin/security", "find-certificate", "-a", "-p",
            "/Users/m1/Library/Keychains/apple-signing.keychain-db"],
            capture_output=True, timeout=20, check=True)
        certificates = [base64.b64decode(re.sub(rb"\s+", b"", pem), validate=True)
            for pem in re.findall(rb"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----",
                                  local.stdout, re.DOTALL)]
        local_matches = [der for der in certificates if hashlib.sha1(der).hexdigest()
                         == "644940fcf25d1730dbd1bf7596aeba7229e2b8fd"]
        if len(local_matches) != 1 or hashlib.sha256(local_matches[0]).hexdigest() != CERTIFICATE_SHA:
            raise ValueError("Original local distribution certificate bytes changed")
        receipt["local_certificate_sha256"] = hashlib.sha256(local_matches[0]).hexdigest()
        checkpoint()
        certificate_id = original_certificate_id(api("/v1/certificates", {
            "filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION",
            "fields[certificates]": "certificateType,certificateContent", "limit": 200}),
            CERTIFICATE_SHA)
        existing = complete_items(api("/v1/bundleIds/" + BUNDLE_RESOURCE + "/profiles",
            {"fields[profiles]": "name,profileType,profileState", "limit": 200}))
        receipt["existing_profile_count"] = len(existing)
        receipt["examined_profiles"] = []
        def assess(identity):
            identity = resource_id(identity)
            data = api("/v1/profiles/" + identity, {
                "fields[profiles]": "profileType,profileState,profileContent"})["data"]["attributes"]
            if (data["profileType"], data["profileState"]) != ("IOS_APP_STORE", "ACTIVE"):
                raise ValueError("Apple profile is not an active App Store profile")
            content, decoded = decode_cms(data["profileContent"], work)
            result = evaluate_profile(decoded, required, BUNDLE, TEAM, CERTIFICATE_SHA,
                                      datetime.now(timezone.utc))
            result.update(profile_id=identity, cms_sha256=hashlib.sha256(content).hexdigest(),
                          granted_app_groups=decoded.get("Entitlements", {}).get(
                              "com.apple.security.application-groups", []))
            receipt["examined_profiles"].append(result)
            checkpoint()
            return result
        selected = None
        for candidate in existing:
            attr = candidate.get("attributes", {})
            if (attr.get("profileType"), attr.get("profileState")) == ("IOS_APP_STORE", "ACTIVE"):
                check = assess(candidate["id"])
                if check["status"] == "READY_RESOURCE":
                    selected = check
                    break
        if selected is None:
            if existing:
                raise ValueError("Existing Share profiles are incompatible; do not repeat issuance without a grant change")
            name = "Hanlin MiniApps Share App Store Resource " + datetime.now(timezone.utc).strftime("%Y%m%d %H%M")
            receipt.update(status="REQUESTING_ONE_MISSING_PROFILE", requested_name=name)
            checkpoint()
            response = api("/v1/profiles", body={"data": {"type": "profiles",
                "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": BUNDLE_RESOURCE}},
                    "certificates": {"data": [{"type": "certificates", "id": certificate_id}]}}}})
            identity = resource_id(response["data"]["id"])
            receipt["operations"].append({"kind": "CREATED_ONE_PROFILE_WITH_EXISTING_CERTIFICATE",
                                          "profile_id": identity})
            receipt["status"] = "READING_ACTUAL_CREATED_CMS"
            checkpoint()
            selected = assess(identity)
        receipt.update(status="VERIFIED_APPLE_RESOURCE" if selected["status"] == "READY_RESOURCE"
                       else "BLOCKED_ACTUAL_PROFILE_GRANTS", selected_profile=selected)
    except Exception as error:
        receipt.update(status="FAILED_RECONCILE_ACCOUNT_BEFORE_ANY_RETRY",
                       error_type=type(error).__name__, error=str(error)[:500])
    receipt["finished_at"] = datetime.now(timezone.utc).isoformat()
    checkpoint()
    print(json.dumps(receipt, indent=2))
    return 0 if receipt["status"] == "VERIFIED_APPLE_RESOURCE" else 1

if __name__ == "__main__":
    raise SystemExit(main())
