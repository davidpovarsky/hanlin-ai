#!/usr/bin/env python3
"""Generate an App Store main profile from the configured team credentials.

Fail closed unless Apple's new profile authorizes Extended Virtual Addressing.
Never print JWTs, keys, certificate bytes, or profile content.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

BASE = "https://api.appstoreconnect.apple.com"
EXTENDED = "com.apple.developer.kernel.extended-virtual-addressing"


def require(name):
    value = os.environ.get(name, "")
    if not value:
        raise RuntimeError("Missing required secret/configuration " + name)
    return value


def api(token, method, path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=35) as reply:
            raw = reply.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        body = exc.read(8192)
        try:
            descriptions = [
                str(e.get("code", "")) + ":" + str(e.get("title", ""))
                for e in json.loads(body).get("errors", [])
            ]
        except (ValueError, KeyError):
            descriptions = []
        raise RuntimeError(
            f"Apple provisioning API {method} {path.split('?')[0]} returned HTTP {exc.code}; "
            + ", ".join(descriptions[:4])
        ) from None


def page_all(token, path):
    result = []
    while path:
        response = api(token, "GET", path)
        result.extend(response.get("data", []))
        next_url = response.get("links", {}).get("next")
        if next_url:
            if not next_url.startswith(BASE + "/"):
                raise RuntimeError("Unexpected Apple API pagination URL")
            path = next_url[len(BASE):]
        else:
            path = None
    return result


def signing_serial(p12_b64, password):
    with tempfile.TemporaryDirectory(prefix="hanlin-signing-cert-") as temp:
        source, pem = Path(temp) / "distribution.p12", Path(temp) / "distribution.pem"
        source.write_bytes(base64.b64decode(p12_b64, validate=True))
        env = dict(os.environ, APPLE_CERTIFICATE_PASSWORD=password)
        proc = subprocess.run(
            ["openssl", "pkcs12", "-in", str(source), "-clcerts", "-nokeys",
             "-passin", "env:APPLE_CERTIFICATE_PASSWORD", "-out", str(pem)],
            env=env, capture_output=True, text=True,
        )
        if proc.returncode:
            raise RuntimeError("Could not read distribution certificate public serial from configured P12")
        proc = subprocess.run(
            ["openssl", "x509", "-in", str(pem), "-noout", "-serial"],
            capture_output=True, text=True,
        )
        if proc.returncode or "=" not in proc.stdout:
            raise RuntimeError("Could not identify public distribution certificate serial")
        return proc.stdout.strip().split("=", 1)[1].upper().lstrip("0")


def decode_entitlements(profile):
    if platform.system() == "Darwin":
        proc = subprocess.run(["security", "cms", "-D", "-i", str(profile)], capture_output=True)
        if proc.returncode:
            raise RuntimeError("Apple provisioning profile CMS decode failed")
        return plistlib.loads(proc.stdout)
    with tempfile.NamedTemporaryFile(suffix=".plist") as output:
        proc = subprocess.run(
            ["openssl", "cms", "-verify", "-inform", "DER", "-noverify",
             "-in", str(profile), "-out", output.name],
            capture_output=True,
        )
        if proc.returncode:
            raise RuntimeError("Apple provisioning profile CMS verification failed")
        return plistlib.loads(Path(output.name).read_bytes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    app_id = require("APP_BUNDLE_ID")
    team_id = require("APPLE_TEAM_ID")
    private_key = base64.b64decode(require("ASC_KEY_P8_B64"), validate=True)
    now = int(time.time())
    token = jwt.encode(
        {"iss": require("ASC_ISSUER_ID"), "iat": now - 5, "exp": now + 600,
         "aud": "appstoreconnect-v1"},
        private_key, algorithm="ES256",
        headers={"kid": require("ASC_KEY_ID"), "typ": "JWT"},
    )
    bundles = page_all(
        token, "/v1/bundleIds?" + urllib.parse.urlencode({
            "filter[identifier]": app_id, "limit": "100",
        })
    )
    matches = [item for item in bundles if item.get("attributes", {}).get("identifier") == app_id]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one registered Apple bundle identifier for main app")
    bundle_id = matches[0]["id"]
    capabilities = page_all(
        token, "/v1/bundleIds/" + bundle_id + "/bundleIdCapabilities",
    )
    print("Apple Developer bundle ID available; provisioned capabilities: "
          + str(len(capabilities)), flush=True)

    cert_serial = signing_serial(
        require("APPLE_CERTIFICATE_P12_B64"),
        require("APPLE_CERTIFICATE_PASSWORD"),
    )
    certificates = page_all(token, "/v1/certificates?limit=200")
    matching = [
        item for item in certificates
        if str(item.get("attributes", {}).get("serialNumber", "")).replace(":", "").upper().lstrip("0") == cert_serial
    ]
    if len(matching) != 1:
        raise RuntimeError(
            "Configured Apple Distribution P12 does not match exactly one active "
            "App Store Connect certificate"
        )
    certificate_id = matching[0]["id"]
    run_id = os.environ.get("GITHUB_RUN_ID", str(now))
    response = api(token, "POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": "Hanlin TestFlight VA " + run_id,
                "profileType": "IOS_APP_STORE",
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        },
    })
    item = response["data"]
    profile_id = item["id"]
    data_b64 = item.get("attributes", {}).get("profileContent")
    if not data_b64:
        raise RuntimeError("Apple created a profile without downloadable profileContent")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(base64.b64decode(data_b64, validate=True))
    decoded = decode_entitlements(args.output)
    allowed = decoded.get("Entitlements", {})
    if allowed.get(EXTENDED) is not True:
        print("New Apple profile does not authorize Extended Virtual Addressing; "
              "App ID capability must be enabled in Apple Developer.", flush=True)
        try:
            api(token, "DELETE", "/v1/profiles/" + profile_id)
        except RuntimeError:
            pass
        args.output.unlink(missing_ok=True)
        raise RuntimeError("APPLE_APP_ID_EXTENDED_VIRTUAL_ADDRESSING_NOT_ENABLED")
    if allowed.get("application-identifier") != team_id + "." + app_id:
        args.output.unlink(missing_ok=True)
        raise RuntimeError("Generated profile has incorrect app/team identifier")
    if allowed.get("get-task-allow") is not False:
        args.output.unlink(missing_ok=True)
        raise RuntimeError("Generated profile is not App Store distribution")
    print(json.dumps({
        "status": "PROFILE_EXTENDED_VA_CONFIRMED",
        "appBundleId": app_id,
        "authorization": True,
        "state": item.get("attributes", {}).get("profileState"),
        "bytes": args.output.stat().st_size,
    }), flush=True)
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf8") as stream:
            stream.write("HANLIN_GENERATED_MAIN_PROFILE_PATH=" + str(args.output) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, KeyError, OSError, subprocess.CalledProcessError) as exc:
        print("Apple main-profile preparation blocked: " + str(exc), file=sys.stderr)
        raise SystemExit(1) from None
