"""Register an exact declared app/extension with the existing Apple account.

The default is the original MiniApps registration. An explicit extension role
admits only the three new MiniApps target identifiers and their checked-in capabilities.
No certificate, profile, App Store listing, build or release is created here.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "com.itorah.hanlinminiapps"
NAME = "Hanlin MiniApps"
ALLOWED_CAPABILITIES = ("APP_GROUPS", "HEALTHKIT")
from extension_inventory import EXTENSIONS, SIGNING_TARGETS, NEW_EXTENSION_KEYS

REGISTRATION_ROLES = ("miniapps", *(
    target.role for target in SIGNING_TARGETS
    if target.owner == "miniapps" and target.target in {
        spec.mini_target for spec in EXTENSIONS if spec.key in NEW_EXTENSION_KEYS}
))


def registration_target(role, root=ROOT):
    """Resolve a bounded role to the actual target and source entitlements."""
    if role not in REGISTRATION_ROLES:
        raise ValueError("Registration is outside the declared MiniApps/new-extension scope")
    target = next(target for target in SIGNING_TARGETS if target.role == role)
    sys.path.insert(0, str(root / "Scripts/CI/IntegrationValidation"))
    from project_graph import parse_project
    project = parse_project((root / "AI_HLY.xcodeproj/project.pbxproj").read_text())
    objects = project["objects"]
    matches = [value for value in objects.values()
               if value.get("isa") == "PBXNativeTarget" and value.get("name") == target.target]
    if len(matches) != 1:
        raise ValueError("The exact declared shipping target is missing or ambiguous")
    for config_id in objects[matches[0]["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[config_id]["buildSettings"]
        if settings["PRODUCT_BUNDLE_IDENTIFIER"] != target.bundle or settings["CODE_SIGN_ENTITLEMENTS"] != target.entitlements:
            raise ValueError("The target identity or entitlement source differs from its reviewed inventory")
    path = root / target.entitlements
    entitlements = plistlib.loads(path.read_bytes())
    if role == "miniapps":
        if entitlements.get("com.apple.developer.healthkit") is not True or set(
                entitlements.get("com.apple.security.application-groups", [])) != {
                "group.com.itorah.chavrusachat", "group.com.itorah.shared"}:
            raise ValueError("Declared MiniApps capabilities differ from the reviewed source")
        name, capabilities = NAME, ALLOWED_CAPABILITIES
    else:
        if target.bundle.endswith(".camera-capture"):
            if entitlements:
                raise ValueError("The declared locked camera capture target has no additional entitlements")
            capabilities = ()
        else:
            if entitlements != {"com.apple.security.application-groups": ["group.com.itorah.chavrusachat"]}:
                raise ValueError("The declared extension App Group differs from its reviewed source")
            capabilities = ("APP_GROUPS",)
        info = plistlib.loads(path.with_name("Info.plist").read_bytes())
        name = info.get("CFBundleDisplayName", target.target)
        if not isinstance(name, str) or not name.strip():
            raise ValueError("The extension display name is missing")
    return target, name, capabilities, path

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

def find_bundle(identifier=BUNDLE):
    result = request("/v1/bundleIds", parameters={"filter[identifier]": identifier,
        "fields[bundleIds]": "identifier,name,platform", "limit": 200})
    if result.get("links", {}).get("next"):
        raise AppleFailure("INCOMPLETE_EXACT_LOOKUP")
    found = [item for item in result.get("data", [])
        if item.get("attributes", {}).get("identifier") == identifier
        and item.get("attributes", {}).get("platform") in {"IOS", "UNIVERSAL"}]
    if len(found) > 1:
        raise AppleFailure("AMBIGUOUS_EXACT_IDENTITY")
    return found

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-role", choices=REGISTRATION_ROLES, default="miniapps")
    args = parser.parse_args(argv)
    out = ROOT / "build/miniapps-registration"
    if args.target_role != "miniapps":
        out = out / args.target_role
    out.mkdir(parents=True, exist_ok=True)
    report = {"source_sha": os.environ.get("GITHUB_SHA"), "run_id": os.environ.get("GITHUB_RUN_ID"),
        "timestamp": datetime.now(timezone.utc).isoformat(), "target_role": args.target_role, "status": "BLOCKED", "operations": [],
        "signing_ready": False, "release_decision": "NO_GO",
        "scope": "One exact declared MiniApps/new-extension identifier and its source-checked capabilities only; no signing, publication or credentials transfer"}
    try:
        target, name, allowed_capabilities, entitlements_path = registration_target(args.target_role)
        expected_key = "EXPECTED_MINIAPPS_BUNDLE" if args.target_role == "miniapps" else "EXPECTED_EXTENSION_BUNDLE"
        if os.environ.get(expected_key) != target.bundle:
            raise ValueError("The explicit operation input must match the exact declared bundle")
        report.update(bundle_id=target.bundle, product_name=name, capabilities=list(allowed_capabilities))
        report["entitlements_sha256"] = hashlib.sha256(entitlements_path.read_bytes()).hexdigest()
        found = find_bundle(target.bundle)
        if not found:
            try:
                request("/v1/bundleIds", "POST", body={"data": {"type": "bundleIds",
                    "attributes": {"identifier": target.bundle, "name": name, "platform": "IOS"}}})
                report["operations"].append({"operation": ("REGISTER_ORIGINAL_BUNDLE_ID" if args.target_role == "miniapps" else "REGISTER_DECLARED_EXTENSION_BUNDLE_ID"), "status": "API_ACCEPTED"})
            except Exception as error:
                report["operations"].append({"operation": ("REGISTER_ORIGINAL_BUNDLE_ID" if args.target_role == "miniapps" else "REGISTER_DECLARED_EXTENSION_BUNDLE_ID"),
                    "status": error.status if isinstance(error, AppleFailure) else "OUTCOME_UNKNOWN",
                    "codes": error.codes if isinstance(error, AppleFailure) else []})
                # Never retry a write after an uncertain response. Reconcile by GET.
            found = find_bundle(target.bundle)
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
        for capability in allowed_capabilities:
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
        report["registration_scope_passed"] = set(allowed_capabilities).issubset(report["observed_capabilities"])
        report["status"] = "REGISTRATION_SCOPE_VERIFIED" if report["registration_scope_passed"] else "PARTIAL_REGISTRATION"
    except Exception as error:
        report["error"] = {"status": error.status if isinstance(error, AppleFailure) else type(error).__name__,
            "codes": error.codes if isinstance(error, AppleFailure) else []}
    finally:
        report["remaining"] = ([
            "Assign both original App Groups in the authorized Apple portal/Xcode configuration",
            "Enable the target's required Extended Virtual Addressing, WeatherKit and Time Sensitive Notifications",
            "Create a compatible profile for the existing Distribution certificate, verify every requested entitlement",
            "Create the separate App Store Connect record and complete original native/device/release gates"]
            if args.target_role == "miniapps" else [
                *(["Assign the declared existing App Group in the authorized Apple configuration"]
                  if "APP_GROUPS" in report.get("capabilities", []) else []),
                "Resolve a compatible profile for the existing Distribution certificate and verify its exact entitlements",
                "Complete the owning app's native, signed archive, export and device acceptance gates"])
        (out / "sanitized-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
    return 0 if report.get("registration_scope_passed") else 1

if __name__ == "__main__":
    raise SystemExit(main())
