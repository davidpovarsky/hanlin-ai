"""Explicit Linux profile/device readback through the existing authorized job.

This optional entry point issues App Store profile snapshots for the recorded
registered consumers. Original MiniApps registration remains a separate operation.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

from audit_release_resources import decode


def portable_profile_cms(encoded, private_directory):
    """Verify the CMS content signature; API authentication supplies its origin."""
    content = decode(encoded)
    with tempfile.TemporaryDirectory(prefix="owner-profile-", dir=private_directory) as folder:
        path = Path(folder) / "profile.mobileprovision"
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
        process = subprocess.run(
            ["openssl", "cms", "-verify", "-noverify", "-inform", "DER", "-in", str(path)],
            capture_output=True, timeout=20)
        if process.returncode:
            raise ValueError("The API profile's CMS content signature did not verify")
        return content, plistlib.loads(process.stdout)


def _verified_distribution_pin(plan):
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from audit_release_resources import apple_get
    from resolve_signing_profiles import original_certificate_id
    pin = plan["existing_distribution_identity_pin"]
    fingerprint = pin.get("public_certificate_sha256", "")
    if (not re.fullmatch(r"[a-f0-9]{64}", fingerprint)
            or pin.get("owner_team") != plan["owner_team"]
            or pin.get("private_identity_validated_run") != 45286408333):
        raise ValueError("Expected the already validated owner Distribution identity pin")
    records = apple_get("/v1/certificates", {
        "filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION",
        "fields[certificates]": "certificateType,certificateContent", "limit": 200})
    identifier = original_certificate_id(records, fingerprint)
    record = next(value for value in records["data"] if value["id"] == identifier)
    raw = decode(record["attributes"]["certificateContent"])
    certificate = x509.load_der_x509_certificate(raw)
    teams = [value.value for value in certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)]
    now = datetime.now(timezone.utc)
    not_before = getattr(certificate, "not_valid_before_utc", None) or certificate.not_valid_before.replace(tzinfo=timezone.utc)
    not_after = getattr(certificate, "not_valid_after_utc", None) or certificate.not_valid_after.replace(tzinfo=timezone.utc)
    if plan["owner_team"] not in teams or not not_before <= now < not_after:
        raise ValueError("The pinned Distribution certificate no longer qualifies for the owner")
    return fingerprint, {"resource_id": identifier, "certificate_type": record["attributes"]["certificateType"],
        "public_certificate_sha256": hashlib.sha256(raw).hexdigest(), "owner_team_matches": True,
        "currently_valid": True, "expiration": not_after.isoformat(),
        "private_identity_validated_run": pin["private_identity_validated_run"],
        "private_identity_validation_artifact_sha256": pin["artifact_sha256"],
        "this_run_read_or_imported_private_distribution_key": False}


def run_if_explicit_owner_readback(root):
    plan_path = Path(root) / "Config/MiniAppsOwnerSigningPlan.json"
    if not plan_path.is_file():
        return None
    plan = json.loads(plan_path.read_bytes())
    if plan.get("readback_executor") != "documented-api-linux":
        return None
    out = Path(root) / "build/miniapps-registration"
    out.mkdir(parents=True, exist_ok=True)
    report = {"source_sha": os.environ.get("GITHUB_SHA"), "run_id": os.environ.get("GITHUB_RUN_ID"),
              "timestamp": datetime.now(timezone.utc).isoformat(), "status": "BLOCKED",
              "scope": "EXPLICIT_CURRENT_OWNER_PROFILE_AND_DEVICE_API_READBACK",
              "signing_ready": False, "release_decision": "NO_GO",
              "native_builds": "NOT_REQUESTED", "original_bundle_registration": "NOT_REQUESTED",
              "certificate_creation_or_revocation": "NOT_REQUESTED", "private_key_inspection": "NOT_REQUESTED"}
    try:
        if (os.environ.get("GITHUB_REPOSITORY") != "davidpovarsky/hanlin-ai"
                or os.environ.get("EXPECTED_MINIAPPS_BUNDLE") != "com.itorah.hanlinminiapps"
                or plan.get("operation") != "refresh-profile-readback"):
            raise ValueError("The explicit source plan must select the authorized owner readback job")
        fingerprint, identity = _verified_distribution_pin(plan)
        report["existing_distribution_certificate"] = identity
        report["cross_app_owner_readback"] = {}
        from owner_profile_readback import run_cross_app_owner_readback
        with tempfile.TemporaryDirectory(prefix="owner-profile-readback-") as folder:
            run_cross_app_owner_readback(
                Path(folder), plan_path, team=plan["owner_team"], certificate_sha=fingerprint,
                receipt=report["cross_app_owner_readback"], inspect_local_keychain=False,
                decode_profile=portable_profile_cms)
        report["status"] = "CROSS_APP_PROFILE_READBACK_COMPLETE"
    except Exception as error:
        report["error"] = {"kind": type(error).__name__}
        if re.fullmatch(r"[A-Z_]+(?:HTTP_[0-9]{3})?", str(error)):
            report["error"]["code"] = str(error)
    finally:
        (out / "sanitized-report.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
    return 0 if report["status"] == "CROSS_APP_PROFILE_READBACK_COMPLETE" else 1
