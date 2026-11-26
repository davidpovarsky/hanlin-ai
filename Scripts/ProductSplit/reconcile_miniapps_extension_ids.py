#!/usr/bin/env python3
"""Register only source-declared MiniApps extensions; retain explicit signing gaps."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import jwt

EXPECTED = {
    "com.itorah.hanlinminiapps.widgets": {"APP_GROUPS", "HEALTHKIT", "HOMEKIT", "ICLOUD"},
    "com.itorah.hanlinminiapps.share": {"APP_GROUPS"},
    "com.itorah.hanlinminiapps.translation-provider": {"APP_GROUPS"},
    "com.itorah.hanlinminiapps.notification-service": {"APP_GROUPS"},
}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--plan", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--apply", action="store_true")
    args = p.parse_args()
    raw = args.plan.read_bytes()
    plan = json.loads(raw)
    if plan["team_id"] != "NA6HPWARQ2" or plan["parent_bundle_id"] != "com.itorah.hanlinminiapps":
        raise ValueError("Unexpected owner or parent")
    if not re.fullmatch("[0-9a-f]{40}", plan["source_sha"]):
        raise ValueError("Unbound source")
    rows = plan["extensions"]
    if len(rows) != len(EXPECTED) or {x["bundle_id"] for x in rows} != set(EXPECTED):
        raise ValueError("Unexpected extension scope")
    for row in rows:
        if set(row["public_capabilities"]) != EXPECTED[row["bundle_id"]]:
            raise ValueError("Unexpected capability scope")
        if not re.fullmatch("[0-9a-f]{64}", row["entitlements_sha256"]):
            raise ValueError("Missing source entitlement binding")
    receipt = {"source_sha": plan["source_sha"], "team_id": plan["team_id"],
        "started_at": datetime.now(timezone.utc).isoformat(),
        "plan_sha256": hashlib.sha256(raw).hexdigest(), "apply": args.apply,
        "operations": [], "extensions": [],
        "app_group_assignment": "REQUIRES_SEPARATE_VERIFICATION",
        "icloud_container_assignment": "REQUIRES_SEPARATE_VERIFICATION",
        "profile_signing_and_upload": "NOT_PERFORMED"}

    def checkpoint():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temp = args.output.with_suffix(".tmp")
        temp.write_text(json.dumps(receipt, indent=2) + "\n")
        temp.replace(args.output)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    key_id = "BMFQPP6252"
    key_path = Path.home() / ".appstoreconnect/private_keys" / ("AuthKey_" + key_id + ".p8")
    def request(method, path, payload=None, params=None):
        if not path.startswith("/v1/"):
            raise ValueError("Unsupported Apple path")
        now = int(time.time())
        token = jwt.encode({"iss": "b5ac6a24-597d-4c46-924e-712ad41bf667",
            "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            key_path.read_bytes(), algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
        url = "https://api.appstoreconnect.apple.com" + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        body = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(url, data=body,
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"}, method=method)
        event = {"method": method, "path": path, "started_at": datetime.now(timezone.utc).isoformat()}
        if payload is not None:
            event["request"] = payload
        receipt["operations"].append(event)
        checkpoint()
        try:
            with opener.open(req, timeout=30) as response:
                result = json.load(response)
                event["http_status"] = response.status
        except urllib.error.HTTPError as error:
            event["http_status"] = error.code
            data = json.loads(error.read())
            event["errors"] = [{k: item.get(k) for k in ("status", "code", "title", "detail")}
                               for item in data.get("errors", [])]
            checkpoint()
            raise RuntimeError("Apple rejected " + method + " " + path + ": HTTP " + str(error.code)) from None
        except (OSError, TimeoutError):
            event["outcome"] = "UNKNOWN_RECONCILE_WITH_GET_BEFORE_ANY_RETRY"
            checkpoint()
            raise RuntimeError("Apple outcome uncertain; no automatic mutation retry") from None
        checkpoint()
        return result

    def exact_bundle(identifier):
        data = request("GET", "/v1/bundleIds", params={"filter[identifier]": identifier, "limit": 200})
        if data.get("links", {}).get("next"):
            raise RuntimeError("Incomplete bundle listing")
        # Apple's identifier filter returns prefix matches as observed once
        # the first extension was registered. Keep an exact local identity match.
        matches = [x for x in data.get("data", []) if x["attributes"]["identifier"] == identifier]
        if len(matches) > 1:
            raise RuntimeError("Ambiguous exact bundle identity")
        return matches[0] if matches else None

    try:
        parent = exact_bundle(plan["parent_bundle_id"])
        if not parent or parent["attributes"].get("seedId") != plan["team_id"]:
            raise RuntimeError("Existing parent does not prove the requested team")
        receipt["parent"] = {"id": parent["id"], "identifier": parent["attributes"]["identifier"],
                             "seedId": parent["attributes"]["seedId"]}
        for row in rows:
            bundle = exact_bundle(row["bundle_id"])
            state = {"bundle_id": row["bundle_id"], "source_entitlements_sha256": row["entitlements_sha256"],
                     "created": False, "capabilities_enabled": []}
            receipt["extensions"].append(state)
            if not bundle:
                if not args.apply:
                    state["status"] = "REGISTRATION_REQUIRED"
                    continue
                bundle = request("POST", "/v1/bundleIds", {"data": {
                    "type": "bundleIds", "attributes": {"name": row["name"],
                    "identifier": row["bundle_id"], "platform": "IOS"}}})["data"]
                state["created"] = True
                state["id"] = bundle["id"]
                checkpoint()
                bundle = exact_bundle(row["bundle_id"])
            if not bundle or bundle["attributes"].get("seedId") != plan["team_id"]:
                raise RuntimeError("Extension team readback differs")
            bid = bundle["id"]; state["id"] = bid
            current = request("GET", "/v1/bundleIds/" + bid + "/bundleIdCapabilities")
            if current.get("links", {}).get("next"):
                raise RuntimeError("Incomplete capability listing")
            present = {x["attributes"]["capabilityType"] for x in current.get("data", [])}
            for cap in row["public_capabilities"]:
                if cap in present or not args.apply:
                    continue
                attributes = {"capabilityType": cap}
                if cap == "ICLOUD":
                    # The source requires CloudKit/CloudDocuments. Apple rejected
                    # a null CloudkitVersion; this is the existing owner's
                    # ICLOUD_VERSION/XCODE_6 setting, read back from Apple.
                    attributes["settings"] = [{"key": "ICLOUD_VERSION",
                        "options": [{"key": "XCODE_6", "enabled": True}]}]
                request("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities",
                    "attributes": attributes,
                    "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
                state["capabilities_enabled"].append(cap)
                checkpoint()
            final = request("GET", "/v1/bundleIds/" + bid + "/bundleIdCapabilities")
            actual = {x["attributes"]["capabilityType"] for x in final.get("data", [])}
            state["capabilities_readback"] = sorted(actual)
            if "ICLOUD" in actual:
                icloud = next(x["attributes"] for x in final["data"] if x["attributes"]["capabilityType"] == "ICLOUD")
                state["icloud_settings_readback"] = icloud.get("settings")
                if not any(setting.get("key") == "ICLOUD_VERSION" and
                    any(option.get("key") == "XCODE_6" for option in setting.get("options", []))
                    for setting in icloud.get("settings", [])):
                    raise RuntimeError("CloudKit version readback differs from source requirement")
            state["missing_public_capabilities"] = sorted(EXPECTED[row["bundle_id"]] - actual)
            state["status"] = "PUBLIC_CAPABILITIES_VERIFIED" if not state["missing_public_capabilities"] else "INCOMPLETE"
            checkpoint()
        receipt["status"] = "PUBLIC_IDENTITIES_AND_CAPABILITIES_VERIFIED" if args.apply and all(
            x.get("status") == "PUBLIC_CAPABILITIES_VERIFIED" for x in receipt["extensions"]) else "READ_ONLY_PLAN"
    except Exception as error:
        receipt["status"] = "STOPPED"
        receipt["error"] = str(error)
    receipt["finished_at"] = datetime.now(timezone.utc).isoformat()
    checkpoint()
    print(json.dumps({k:v for k,v in receipt.items() if k != "operations"}, indent=2))
    return 0 if receipt["status"] != "STOPPED" else 1

if __name__ == "__main__":
    raise SystemExit(main())
