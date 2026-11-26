"""Resolve profiles for the declared shipping targets and the existing distribution key.

The only permitted Apple mutation is creating a missing compatible App Store
profile. Never create/revoke a certificate, change capabilities, register a device,
upload a build, or copy a private key out of the existing signing job.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

from audit_release_resources import (
    ROLES, ROOT, AppleReadFailure, apple_get, decode, evaluate_profile, exact_bundles,
)


def resource_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", value):
        raise ValueError("Invalid Apple resource identifier")
    return value


def complete_items(response):
    if response.get("links", {}).get("next"):
        raise ValueError("Apple resource list is incomplete; no profile will be created")
    items = response.get("data")
    if not isinstance(items, list) or len(items) > 200:
        raise ValueError("Invalid Apple resource collection")
    return items


def original_certificate_id(response, certificate_sha):
    matches = []
    for item in complete_items(response):
        attributes = item.get("attributes", {})
        if attributes.get("certificateType") not in {"DISTRIBUTION", "IOS_DISTRIBUTION"}:
            continue
        content = attributes.get("certificateContent")
        if content and hashlib.sha256(decode(content)).hexdigest() == certificate_sha:
            matches.append(resource_id(item["id"]))
    if len(matches) != 1:
        raise ValueError("The original distribution certificate must match exactly one Apple record")
    return matches[0]


def create_profile(bundle_id, certificate_id, name):
    """Single bounded POST. No automatic retry after an uncertain mutation."""
    import jwt
    resource_id(bundle_id)
    resource_id(certificate_id)
    payload = {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
            "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
        },
    }}
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600,
         "aud": "appstoreconnect-v1"},
        decode(os.environ["ASC_KEY_P8"]), algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/profiles",
        data=json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise AppleReadFailure("PROFILE_CREATE_RESPONSE_TOO_LARGE")
        return json.loads(raw)
    except urllib.error.HTTPError as error:
        # Never persist Apple's raw response or auth header.
        raise AppleReadFailure("PROFILE_CREATE_HTTP_" + str(error.code)) from None
    except (OSError, TimeoutError):
        raise AppleReadFailure("PROFILE_CREATE_OUTCOME_UNKNOWN_RECONCILE_BEFORE_RETRY") from None


def decode_cms(encoded, private_directory):
    content = decode(encoded)
    if len(content) > 2 * 1024 * 1024:
        raise ValueError("Oversized provisioning profile")
    with tempfile.TemporaryDirectory(prefix="profile-", dir=private_directory) as directory:
        path = Path(directory) / "input.mobileprovision"
        path.write_bytes(content)
        path.chmod(0o600)
        result = subprocess.run(
            ["security", "cms", "-D", "-i", str(path)],
            capture_output=True, timeout=20,
        )
        if result.returncode:
            raise ValueError("Apple profile CMS could not be decoded")
        return content, plistlib.loads(result.stdout)


def resolve_profile(role, bundle, required, certificate_sha, certificate_id, team,
                    private_directory, *, get=apple_get, create=create_profile,
                    decode_content=decode_cms):
    if (role, bundle) not in {(r, b) for r, b, _, _ in ROLES}:
        raise ValueError("Profile preparation is scoped to the declared shipping targets")
    response = get("/v1/bundleIds", {
        "filter[identifier]": bundle, "fields[bundleIds]": "identifier,platform", "limit": 200,
    })
    complete_items(response)
    matches = exact_bundles(response, bundle)
    if len(matches) != 1:
        raise ValueError("Original bundle registration is missing or ambiguous: " + role)
    bundle_id = resource_id(matches[0]["id"])
    response = get("/v1/bundleIds/" + bundle_id + "/profiles", {
        "fields[profiles]": "profileType,profileState", "limit": 200,
    })
    candidates = [item for item in complete_items(response)
                  if item.get("attributes", {}).get("profileType") == "IOS_APP_STORE"
                  and item.get("attributes", {}).get("profileState") == "ACTIVE"]
    facts = {"role": role, "bundle_id": bundle, "examined_existing_profiles": []}

    def assess(profile_id):
        response = get("/v1/profiles/" + resource_id(profile_id), {
            "fields[profiles]": "profileType,profileState,profileContent",
        })
        attributes = response["data"]["attributes"]
        if (attributes.get("profileType"), attributes.get("profileState")) != ("IOS_APP_STORE", "ACTIVE"):
            raise ValueError("Profile is not an active iOS App Store profile")
        raw, profile = decode_content(attributes["profileContent"], private_directory)
        check = evaluate_profile(profile, required, bundle, team, certificate_sha, datetime.now(timezone.utc))
        check["profile_sha256"] = hashlib.sha256(raw).hexdigest()
        return raw, profile, check

    selected = None
    for candidate in candidates:
        raw, profile, check = assess(candidate["id"])
        facts["examined_existing_profiles"].append(check)
        if check["status"] == "READY_RESOURCE":
            selected = raw, profile, check
            facts["source"] = "REUSED_COMPATIBLE_APPLE_PROFILE"
            break
    if selected is None:
        operation_id = os.environ.get("HANLIN_SIGNING_OPERATION_ID", "")
        if operation_id:
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}", operation_id):
                raise ValueError("The explicit signing operation identifier is invalid")
            facts["operation"] = {"kind": "native", "id": operation_id}
        else:
            operation_id = os.environ.get("GITHUB_RUN_ID", "")
            if not re.fullmatch(r"[1-9][0-9]*", operation_id):
                raise ValueError("A concrete GitHub run or explicit signing operation is required to create a profile")
            facts["operation"] = {"kind": "github", "id": operation_id}
        name = "Hanlin " + role + " App Store " + operation_id
        response = create(bundle_id, resource_id(certificate_id), name)
        # Read the newly created object back and evaluate the actual CMS data.
        selected = assess(response["data"]["id"])
        facts["source"] = "CREATED_AND_READ_BACK_APPLE_PROFILE"
    raw, profile, check = selected
    if check["status"] != "READY_RESOURCE":
        raise ValueError("Apple profile does not cover original entitlements: " + role + " " +
                         ",".join(check["missing_or_mismatched_entitlement_keys"]))
    profile_uuid = str(uuid.UUID(profile["UUID"])).upper()
    facts.update(check)
    return {"bundle": bundle, "uuid": profile_uuid, "content": raw}, facts


def resolve_original_profiles(certificate_sha, private_directory, facts):
    certificate_id = original_certificate_id(apple_get("/v1/certificates", {
        "filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION",
        "fields[certificates]": "certificateType,certificateContent", "limit": 200,
    }), certificate_sha)
    resolved = []
    for role, bundle, _, source in ROLES:
        profile, result = resolve_profile(
            role, bundle, plistlib.loads((ROOT / source).read_bytes()),
            certificate_sha, certificate_id, os.environ["APPLE_TEAM_ID"], private_directory,
        )
        resolved.append(profile)
        facts.append(result)
    return resolved


def install_profile(profile, directories, created):
    """Install only verified content; preserve preexisting cache entries."""
    filename = str(uuid.UUID(profile["uuid"])).upper() + ".mobileprovision"
    for directory in directories:
        directory = Path(directory)
        directory.mkdir(parents=True, exist_ok=True)
        path = directory / filename
        if path.exists():
            if path.is_symlink() or path.read_bytes() != profile["content"]:
                raise ValueError("A different provisioning profile already occupies this UUID")
            continue
        digest = hashlib.sha256(profile["content"]).hexdigest()
        # Publish complete private bytes without replacing an existing UUID.
        # The staging directory is removed even if write/chmod/link fails.
        with tempfile.TemporaryDirectory(prefix=".hanlin-profile-", dir=directory) as staging:
            staged = Path(staging) / filename
            staged.write_bytes(profile["content"])
            staged.chmod(0o600)
            try:
                os.link(staged, path)
            except FileExistsError:
                if path.is_symlink() or path.read_bytes() != profile["content"]:
                    raise ValueError("A different provisioning profile already occupies this UUID")
            else:
                created.append((path, digest))


def remove_installed_profiles(created):
    errors = []
    for path, digest in reversed(created):
        try:
            if path.is_symlink():
                raise ValueError("Installed profile changed during signing; preserved it")
            if path.exists():
                if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                    raise ValueError("Installed profile changed during signing; preserved it")
                path.unlink()
        except (OSError, ValueError) as error:
            errors.append(type(error).__name__)
    if errors:
        raise ValueError("Installed profile changed during signing or cleanup failed; "
                         "preserved affected entries and cleaned remaining owned profiles")
