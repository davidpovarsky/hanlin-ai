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


def get(path: str) -> dict:
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
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.load(response)


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
for _ in range(40):
    builds = get(f"/v1/builds?{query}").get("data", [])
    if builds:
        state = builds[0]["attributes"]["processingState"]
        print(f"TestFlight build {build_number} processing state: {state}")
        if state in {"FAILED", "INVALID"} or builds[0]["attributes"].get("expired"):
            raise SystemExit("Apple rejected or expired the uploaded build")
        if state == "VALID":
            detail = get(f"/v1/builds/{builds[0]['id']}/buildBetaDetail")["data"]["attributes"]
            internal = detail["internalBuildState"]
            print(f"TestFlight build {build_number} internal testing state: {internal}")
            if internal in {"PROCESSING_EXCEPTION", "EXPIRED", "MISSING_EXPORT_COMPLIANCE"}:
                raise SystemExit(f"TestFlight testing unavailable: {internal}")
            if internal in {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}:
                evidence = {"appID": apps[0]["id"], "buildID": builds[0]["id"],
                            "buildNumber": build_number, "processingState": state,
                            "internalBuildState": internal,
                            "externalBuildState": detail.get("externalBuildState"),
                            "sourceSHA": os.environ.get("GITHUB_SHA")}
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
