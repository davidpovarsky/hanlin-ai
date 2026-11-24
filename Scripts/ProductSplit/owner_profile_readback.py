"""Refresh exact owner grants after Xcode provisioning without another build.

Only new App Store profiles for already verified bundle/certificate resources are
issued. No certificate, device, App ID, or group is created, changed, or removed.
"""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re

from audit_cross_app_signing import all_records, profile_fact, SHARED_GROUP
from audit_release_resources import apple_get, decode, entitlement_allows
from cross_app_owner_provisioning import (
    _capabilities, _development_certificates, _private_output,
    _registered_identity, _resolve_native_groups,
)


def _fresh_profile(product, folder, team, certificate_sha, certificate_id, run_id,
                   *, get=apple_get, create=None, decode_profile=None):
    """Do not mistake a profile issued before provisioning for current grants."""
    from resolve_signing_profiles import create_profile, decode_cms
    create = create or create_profile
    decode_profile = decode_profile or decode_cms
    name = "MiniApps owner readback " + product["role"] + " " + str(run_id)
    records = all_records(get, "/v1/bundleIds/" + product["apple_bundle_resource_id"] + "/profiles",
        {"fields[profiles]": "name,profileType,profileState", "limit": 200})
    matching = [record for record in records if record.get("attributes", {}).get("name") == name]
    if len(matching) > 1:
        raise ValueError("The same readback run has ambiguous profile records")
    if matching:
        identifier = matching[0]["id"]
        source = "RECONCILED_THIS_READBACK_RUN_PROFILE"
    else:
        # A failed/uncertain POST is never retried. A later attempt reconciles by
        # its exact run-specific name before considering another profile.
        identifier = create(product["apple_bundle_resource_id"], certificate_id, name)["data"]["id"]
        source = "CREATED_FRESH_PROFILE_WITHOUT_APP_ID_OR_GROUP_MUTATION"
    attributes = get("/v1/profiles/" + identifier,
        {"fields[profiles]": "profileType,profileState,profileContent"})["data"]["attributes"]
    if attributes.get("profileType") != "IOS_APP_STORE" or attributes.get("profileState") != "ACTIVE":
        raise ValueError("Fresh readback requires an active App Store profile")
    raw, profile = decode_profile(attributes["profileContent"], folder)
    fact = profile_fact(profile, bundle=product["bundle_id"], team=team,
                        certificate_sha=certificate_sha, now=datetime.now(timezone.utc))
    if not all(fact["checks"][key] for key in
               ("owner_team_matches", "bundle_matches", "not_expired", "existing_distribution_certificate_matches")):
        raise ValueError("The fresh profile does not match the existing owner identity")
    creation = profile.get("CreationDate")
    fact.update(resource_id=identifier, source=source,
                profile_sha256=hashlib.sha256(raw).hexdigest(),
                creation=creation.isoformat() if isinstance(creation, datetime) else None)
    return profile, fact


def _registered_devices():
    rows = all_records(apple_get, "/v1/devices",
                       {"fields[devices]": "platform,status", "limit": 200})
    return {"source": "APP_STORE_CONNECT_REGISTERED_DEVICES_API", "inventory_complete": True,
            "registered_device_count": len(rows),
            "status_counts": dict(Counter(row.get("attributes", {}).get("status", "UNKNOWN") for row in rows)),
            "platform_counts": dict(Counter(row.get("attributes", {}).get("platform", "UNKNOWN") for row in rows)),
            "enabled_platform_counts": dict(Counter(row.get("attributes", {}).get("platform", "UNKNOWN")
                for row in rows if row.get("attributes", {}).get("status") == "ENABLED")),
            "device_names_and_identifiers_retained": False, "registration": "NOT_REQUESTED"}


def _identity_fingerprints(listing):
    return {value.upper() for value in re.findall(r"(?m)^\s*\d+\)\s+([A-Fa-f0-9]{40})\s", listing)}


def _existing_development_identity_availability(team, *, inspect_local_keychain=True):
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    local = None
    if inspect_local_keychain:
        listing = _private_output(["security", "find-identity", "-v", "-p", "codesigning"]).decode()
        local = _identity_fingerprints(listing)
    now = datetime.now(timezone.utc)
    facts = []
    for row in _development_certificates():
        raw = decode(row["attributes"]["certificateContent"])
        certificate = x509.load_der_x509_certificate(raw)
        teams = [attribute.value for attribute in
                 certificate.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)]
        not_before = getattr(certificate, "not_valid_before_utc", None) or certificate.not_valid_before.replace(tzinfo=timezone.utc)
        not_after = getattr(certificate, "not_valid_after_utc", None) or certificate.not_valid_after.replace(tzinfo=timezone.utc)
        facts.append({"resource_id": row["id"], "certificate_type": row["attributes"]["certificateType"],
                      "public_certificate_sha256": hashlib.sha256(raw).hexdigest(),
                      "owner_team_matches": team in teams,
                      "valid_dates": not_before <= now < not_after,
                      "expiration": not_after.isoformat(),
                      "private_identity_available_in_existing_search_list":
                          None if local is None else hashlib.sha1(raw).hexdigest().upper() in local})
    return {"source": "APPLE_PUBLIC_CERTIFICATES",
            "local_keychain_inspection": "PERFORMED" if inspect_local_keychain else "NOT_INSPECTED_ON_LINUX",
            "inventory_complete": True, "registered_development_certificate_count": len(facts),
            "reusable_valid_owner_development_identity_count": None if local is None else sum(
                fact["owner_team_matches"] and fact["valid_dates"]
                and fact["private_identity_available_in_existing_search_list"] for fact in facts),
            "certificates": facts, "creation": "NOT_REQUESTED", "revocation": "NOT_REQUESTED"}


def _expanded(value, team, bundle):
    if isinstance(value, str):
        return (value.replace("$(TeamIdentifierPrefix)", team + ".")
                     .replace("$(CFBundleIdentifier)", bundle)
                     .replace("$(APS_ENVIRONMENT)", "production"))
    if isinstance(value, list):
        return [_expanded(item, team, bundle) for item in value]
    return value


def run_cross_app_owner_readback(folder, plan_path, *, team, certificate_sha, receipt,
                                inspect_local_keychain=True, decode_profile=None):
    from resolve_signing_profiles import original_certificate_id
    plan_bytes = Path(plan_path).read_bytes()
    plan = json.loads(plan_bytes)
    if (plan.get("schema_version") != 1 or plan.get("scope") != "miniapps-cross-app-owner-groups"
            or plan.get("operation") != "refresh-profile-readback"
            or plan.get("owner_team") != team or plan.get("shared_group") != SHARED_GROUP):
        raise ValueError("Expected the explicit registered owner profile-readback plan")
    products = plan.get("products", [])
    if not products or len({product.get("bundle_id") for product in products}) != len(products):
        raise ValueError("The plan needs distinct already registered owner identities")
    receipt.update(status="RUNNING", scope="FRESH_PROFILE_READBACK_WITH_EXISTING_DISTRIBUTION_CERTIFICATE",
                   plan_sha256=hashlib.sha256(plan_bytes).hexdigest(), owner_team=team,
                   shared_group=SHARED_GROUP, previous_provisioning_run=plan.get("previous_provisioning_run"),
                   products=[], native_builds="NOT_REQUESTED", app_id_or_group_changes="NOT_REQUESTED",
                   certificate_creation="NOT_REQUESTED", certificate_revocation="NOT_REQUESTED",
                   uploads="NOT_REQUESTED", installs="NOT_REQUESTED")
    work = Path(folder) / "cross-app-owner-readback"
    work.mkdir()
    certificate_id = original_certificate_id(apple_get("/v1/certificates", {
        "filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION",
        "fields[certificates]": "certificateType,certificateContent", "limit": 200}), certificate_sha)
    # Read identity metadata before any profile issuance; no private key material
    # is exported from the current runner keychain or retained in the report.
    receipt["registered_devices"] = _registered_devices()
    receipt["development_identity_availability"] = _existing_development_identity_availability(
        team, inspect_local_keychain=inspect_local_keychain)
    snapshots = []
    decoded_profiles = []
    for product in products:
        if not re.fullmatch(r"[a-z0-9_-]+", product["role"]):
            raise ValueError("A product role must be a filename-safe plan key")
        entry = {"role": product["role"], "bundle_id": product["bundle_id"],
                 "registered_identity": _registered_identity(product)}
        receipt["products"].append(entry)
        entry["current_capabilities"] = _capabilities(product["apple_bundle_resource_id"])
        profile, fact = _fresh_profile(product, work, team, certificate_sha, certificate_id,
                                       os.environ["GITHUB_RUN_ID"], decode_profile=decode_profile)
        entry["fresh_profile"] = fact
        snapshots.append((product, fact))
        decoded_profiles.append(profile)
    families = _resolve_native_groups(plan, snapshots)
    receipt["resolved_native_storage_families"] = families
    for (product, fact), profile, entry in zip(snapshots, decoded_profiles, receipt["products"]):
        required = {key: _expanded(value, team, product["bundle_id"])
                    for key, value in product["entitlements"].items()}
        if "aps-environment" in required:
            required["aps-environment"] = "production"
        groups = set(required.get("com.apple.security.application-groups", []))
        family = product.get("native_storage_family")
        if family:
            groups.add(families[family]["group"])
            entry["native_storage_group"] = families[family]
        required["com.apple.security.application-groups"] = sorted(groups)
        actual = profile.get("Entitlements", {})
        entry["required_entitlements"] = required
        entry["actual_required_key_grants"] = {key: actual.get(key) for key in required}
        entry["missing_or_mismatched_entitlement_keys"] = sorted(
            key for key, value in required.items() if not entitlement_allows(actual.get(key), value))
        entry["status"] = ("PROFILE_COVERS_REQUIRED_GRANTS" if not entry["missing_or_mismatched_entitlement_keys"]
                           else "PROFILE_GRANTS_INCOMPLETE")
    receipt["all_requested_profile_grants_present"] = all(
        entry["status"] == "PROFILE_COVERS_REQUIRED_GRANTS" for entry in receipt["products"])
    receipt["status"] = "CURRENT_PROFILE_GRANTS_READ_BACK"
    receipt["limitation"] = "Profile grants and identity metadata only; no native archive, installed app, or device journey was executed."
