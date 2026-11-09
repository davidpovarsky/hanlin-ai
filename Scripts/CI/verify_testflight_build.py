#!/usr/bin/env python3
"""Wait until App Store Connect acknowledges the uploaded ChavrusaChat build."""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

import jwt


BUNDLE_ID = "com.itorah.chavrusachat"
build_number = sys.argv[1]
audience_source = None
if len(sys.argv) > 2:
    if len(sys.argv) != 4 or sys.argv[2] != "--reuse-internal-audience-from" or not sys.argv[3].isdigit():
        raise SystemExit("Expected --reuse-internal-audience-from <previous build number>")
    audience_source = sys.argv[3]


def get(path: str, *, method: str = "GET", data: dict | None = None) -> dict:
    # Processing may outlive one JWT. Mint a short-lived token per request.
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now,
         "exp": now + 600, "aud": "appstoreconnect-v1"},
        Path(os.environ["ASC_KEY_PATH"]).read_bytes(),
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    request = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com{path}",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method=method, data=json.dumps(data).encode() if data is not None else None,
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        body = response.read()
        return json.loads(body) if body else {}


app_query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": 1})
apps = get(f"/v1/apps?{app_query}").get("data", [])
if len(apps) != 1:
    raise SystemExit(f"Expected one App Store Connect app for {BUNDLE_ID}")

query = urllib.parse.urlencode(
    {
        "filter[app]": apps[0]["id"],
        "filter[version]": build_number,
        "fields[builds]": "version,processingState,uploadedDate,expired",
        "limit": 5,
    }
)
audience_groups = None
for _ in range(40):
    builds = get(f"/v1/builds?{query}").get("data", [])
    if builds:
        state = builds[0]["attributes"]["processingState"]
        print(f"TestFlight build {build_number} processing state: {state}")
        if state in {"FAILED", "INVALID"} or builds[0]["attributes"].get("expired"):
            raise SystemExit("Apple rejected or expired the uploaded build")
        if state == "VALID":
            if audience_source and audience_groups is None:
                source_query = urllib.parse.urlencode({"filter[app]": apps[0]["id"],
                                                      "filter[version]": audience_source, "limit": 5})
                sources = get(f"/v1/builds?{source_query}").get("data", [])
                if len(sources) != 1:
                    raise SystemExit("Expected one previous audience build for this app")
                previous_groups = get(f"/v1/builds/{sources[0]['id']}/betaGroups?limit=200")["data"]
                audience_groups = sorted(group["id"] for group in previous_groups
                                         if group["attributes"].get("isInternalGroup") is True)
                if not audience_groups:
                    raise SystemExit("Previous build has no assigned internal group; no audience changed")
                current_groups = get(f"/v1/builds/{builds[0]['id']}/betaGroups?limit=200")["data"]
                missing = sorted(set(audience_groups) - {group["id"] for group in current_groups})
                if missing:
                    get(f"/v1/builds/{builds[0]['id']}/relationships/betaGroups", method="POST",
                        data={"data": [{"type": "betaGroups", "id": group} for group in missing]})
                confirmed = get(f"/v1/builds/{builds[0]['id']}/betaGroups?limit=200")["data"]
                if not set(audience_groups).issubset({group["id"] for group in confirmed}):
                    raise SystemExit("Internal group assignment was not confirmed")
                print(f"Reused {len(audience_groups)} existing internal groups from build {audience_source}")
            detail = get(f"/v1/builds/{builds[0]['id']}/buildBetaDetail")["data"]["attributes"]
            internal = detail["internalBuildState"]
            print(f"TestFlight build {build_number} internal testing state: {internal}")
            if internal in {"PROCESSING_EXCEPTION", "EXPIRED", "MISSING_EXPORT_COMPLIANCE"}:
                raise SystemExit(f"TestFlight testing unavailable: {internal}")
            ready = {"IN_BETA_TESTING"} if audience_source else {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}
            if internal in ready:
                evidence = {"appID": apps[0]["id"], "buildID": builds[0]["id"],
                            "buildNumber": build_number, "processingState": state,
                            "internalBuildState": internal,
                            "externalBuildState": detail.get("externalBuildState"),
                            "sourceSHA": os.environ.get("GITHUB_SHA")}
                if audience_source:
                    evidence["verificationSHA"] = evidence.pop("sourceSHA")
                    evidence["audienceSourceBuild"] = audience_source
                    evidence["internalBetaGroupIDs"] = audience_groups
                if os.environ.get("BUILD_DIR"):
                    output = Path(os.environ["BUILD_DIR"]) / "logs" / "testflight-readiness.json"
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(evidence))
                raise SystemExit(0)
    time.sleep(30)
raise SystemExit(
    f"Build {build_number} was not ready for internal TestFlight testing within 20 minutes"
)
