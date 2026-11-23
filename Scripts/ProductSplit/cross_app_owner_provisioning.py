"""Provision the explicitly recorded cross-app owner plan using supported Xcode tooling.

The caller owns the temporary keychain and existing distribution identity. This
helper never publishes or installs a product and retains only signing receipts.
The plan is opt-in; original release signing has no dependency on its presence.
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
import stat
import time
import urllib.error
import urllib.request
import zipfile

from audit_release_resources import apple_get, decode, entitlement_allows
from audit_cross_app_signing import all_records, profile_fact, SHARED_GROUP
from signing_profile_preflight import _write_probe_project


def _private_output(argv):
    completed = subprocess.run([str(value) for value in argv], capture_output=True, timeout=45)
    if completed.returncode:
        raise RuntimeError("Native signing readback failed: " + Path(str(argv[0])).name)
    return completed.stdout


def _development_certificates():
    return all_records(apple_get, "/v1/certificates", {
        "filter[certificateType]": "DEVELOPMENT,IOS_DEVELOPMENT",
        "fields[certificates]": "certificateType,certificateContent", "limit": 200})


def _owned_temporary_development_certificates(before_ids, records, keychain_fingerprints):
    """Select only new development identities whose private key is in our keychain."""
    from resolve_signing_profiles import resource_id
    result = []
    for value in records:
        attributes = value.get("attributes", {})
        if (value["id"] in before_ids
                or attributes.get("certificateType") not in {"DEVELOPMENT", "IOS_DEVELOPMENT"}):
            continue
        certificate = decode(attributes["certificateContent"])
        fingerprint = hashlib.sha1(certificate).hexdigest().upper()
        if fingerprint in keychain_fingerprints:
            result.append({"resource_id": resource_id(value["id"]),
                           "certificate_type": attributes["certificateType"],
                           "public_certificate_sha256": hashlib.sha256(certificate).hexdigest(),
                           "created_after_probe_started": True,
                           "private_key_in_owned_temporary_keychain": True})
    return result


def _revoke_temporary_development_certificate(fact, before_ids):
    """Documented DELETE of this probe's new, byte-matched development identity only."""
    import jwt
    from audit_release_resources import AppleReadFailure
    from resolve_signing_profiles import resource_id
    identifier = resource_id(fact["resource_id"])
    if identifier in before_ids:
        raise ValueError("An existing certificate must never be revoked by this probe")
    current = apple_get("/v1/certificates/" + identifier,
        {"fields[certificates]": "certificateType,certificateContent"})["data"]["attributes"]
    if (current.get("certificateType") not in {"DEVELOPMENT", "IOS_DEVELOPMENT"}
            or hashlib.sha256(decode(current["certificateContent"])).hexdigest()
                != fact["public_certificate_sha256"]):
        raise ValueError("Temporary development identity changed before cleanup")
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600,
         "aud": "appstoreconnect-v1"}, decode(os.environ["ASC_KEY_P8"]),
        algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    request = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/certificates/" + identifier,
        headers={"Authorization": "Bearer " + token}, method="DELETE")
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            if response.status != 204:
                raise AppleReadFailure("TEMPORARY_CERTIFICATE_DELETE_UNEXPECTED_STATUS")
    except urllib.error.HTTPError as error:
        raise AppleReadFailure("TEMPORARY_CERTIFICATE_DELETE_HTTP_" + str(error.code)) from None
    except (OSError, TimeoutError):
        raise AppleReadFailure("TEMPORARY_CERTIFICATE_DELETE_OUTCOME_UNKNOWN_RECONCILE_BEFORE_RETRY") from None


def _cleanup_temporary_development_certificates(keychain, before_ids, receipt):
    identities = _private_output(["security", "find-identity", "-p", "codesigning", keychain]).decode()
    fingerprints = {value.upper() for value in re.findall(
        r"(?m)^\s*\d+\)\s+([A-Fa-f0-9]{40})\s", identities)}
    facts = _owned_temporary_development_certificates(
        before_ids, _development_certificates(), fingerprints)
    receipt["temporary_development_identities"] = facts
    for fact in facts:
        fact["cleanup"] = "PENDING"
        _revoke_temporary_development_certificate(fact, before_ids)
        fact["cleanup"] = "REVOKED_EXACT_OWNED_TEMPORARY_IDENTITY"
    receipt["temporary_development_identity_cleanup"] = "PASS"


def _unpack_export(exported, destination):
    ipas = list(exported.glob("*.ipa"))
    if len(ipas) != 1:
        raise RuntimeError("The owner probe export must contain exactly one IPA")
    with zipfile.ZipFile(ipas[0]) as package:
        for member in package.infolist():
            path = Path(member.filename)
            if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(member.external_attr >> 16):
                raise RuntimeError("The owner probe export contains an invalid path")
        package.extractall(destination)
    applications = list((destination / "Payload").glob("*.app"))
    if len(applications) != 1:
        raise RuntimeError("The owner probe export must contain one application")
    return applications[0], hashlib.sha256(ipas[0].read_bytes()).hexdigest()


def _capabilities(resource_id):
    records = all_records(apple_get, "/v1/bundleIds/" + resource_id + "/bundleIdCapabilities")
    return sorted({row.get("attributes", {}).get("capabilityType") for row in records
                   if row.get("attributes", {}).get("capabilityType")})


def _registered_identity(product):
    resource_id = product["apple_bundle_resource_id"]
    if not re.fullmatch(r"[A-Z0-9]+", resource_id):
        raise ValueError("The plan must contain a concrete registered Apple bundle resource")
    value = apple_get("/v1/bundleIds/" + resource_id,
                      {"fields[bundleIds]": "identifier,name,platform"})["data"]
    attributes = value["attributes"]
    if attributes.get("identifier") != product["bundle_id"] or attributes.get("platform") not in {"IOS", "UNIVERSAL"}:
        raise ValueError("The live Apple identity differs from the recorded owner plan")
    return {"resource_id": resource_id, "bundle_id": attributes["identifier"],
            "name": attributes.get("name"), "platform": attributes["platform"]}


def _profile_snapshot(product, folder, team, certificate_sha, certificate_id, required_entitlements=None):
    """Issue a profile only if necessary; this does not change an App ID or group."""
    from resolve_signing_profiles import create_profile, decode_cms
    candidates = all_records(apple_get, "/v1/bundleIds/" + product["apple_bundle_resource_id"] + "/profiles",
        {"fields[profiles]": "name,profileType,profileState", "limit": 200})

    def read(profile_id):
        value = apple_get("/v1/profiles/" + profile_id,
                         {"fields[profiles]": "profileType,profileState,profileContent"})["data"]
        attributes = value["attributes"]
        if attributes.get("profileType") != "IOS_APP_STORE" or attributes.get("profileState") != "ACTIVE":
            return None
        _, profile = decode_cms(attributes["profileContent"], folder)
        fact = profile_fact(profile, bundle=product["bundle_id"], team=team,
                            certificate_sha=certificate_sha, now=datetime.now(timezone.utc))
        valid = all(fact["checks"][key] for key in
                    ("owner_team_matches", "bundle_matches", "not_expired", "existing_distribution_certificate_matches"))
        if required_entitlements:
            valid = valid and all(entitlement_allows(profile.get("Entitlements", {}).get(key), value)
                                  for key, value in required_entitlements.items())
        return (profile, fact) if valid else None

    for candidate in candidates:
        if candidate.get("attributes", {}).get("profileState") != "ACTIVE":
            continue
        observed = read(candidate["id"])
        if observed:
            profile, fact = observed
            fact.update(resource_id=candidate["id"], source="REUSED_EXISTING_PROFILE")
            return profile, fact
    created = create_profile(product["apple_bundle_resource_id"], certificate_id,
        "MiniApps owner " + product["role"] + " " + os.environ["GITHUB_RUN_ID"])
    profile_id = created["data"]["id"]
    observed = read(profile_id)
    if observed is None:
        raise RuntimeError("Created owner profile failed identity readback")
    profile, fact = observed
    fact.update(resource_id=profile_id, source="CREATED_PROFILE_WITHOUT_APP_ID_OR_GROUP_MUTATION")
    return profile, fact


def _resolve_native_groups(plan, snapshots):
    result = {}
    for family, specification in plan.get("native_storage_families", {}).items():
        group_sets = [set(snapshot["app_groups"]) - {SHARED_GROUP}
                      for product, snapshot in snapshots
                      if product.get("native_storage_family") == family]
        existing = set().union(*group_sets) if group_sets else set()
        common = set.intersection(*group_sets) if group_sets and all(group_sets) else existing
        preferred = next((group for group in specification["preferred_existing_groups"] if group in common), None)
        if preferred is None and len(common) == 1:
            preferred = next(iter(common))
        if preferred is not None:
            result[family] = {"group": preferred, "source": "EXISTING_APPLE_PROFILE_GRANT", "observed_groups": sorted(existing)}
        elif not existing:
            result[family] = {"group": specification["new_group_if_no_existing_grants"],
                              "source": "NEW_OWNER_PRIVATE_GROUP_REQUESTED", "observed_groups": []}
        else:
            raise ValueError("Existing native group identity needs an exact mapping from the signed profile receipts")
    return result


def _read_signed_probe(app, expected, team, certificate_sha, certificate_prefix):
    bundle = plistlib.loads((app / "Info.plist").read_bytes())
    payload = plistlib.loads(_private_output(["security", "cms", "-D", "-i", app / "embedded.mobileprovision"]))
    entitlements = plistlib.loads(_private_output(["codesign", "-d", "--entitlements", ":-", app]))
    _private_output(["codesign", "--verify", "--strict", app])
    _private_output(["codesign", "-d", "--extract-certificates=" + str(certificate_prefix), app])
    leaf = Path(str(certificate_prefix) + "0")
    actual_certificate_sha = hashlib.sha256(leaf.read_bytes()).hexdigest()
    profile = profile_fact(payload, bundle=expected["bundle_id"], team=team,
                           certificate_sha=certificate_sha, now=datetime.now(timezone.utc))
    required = expected["entitlements"]
    missing_signed = sorted(key for key, value in required.items()
                            if not entitlement_allows(entitlements.get(key), value))
    missing_profile = sorted(key for key, value in required.items()
                             if not entitlement_allows(payload.get("Entitlements", {}).get(key), value))
    groups = entitlements.get("com.apple.security.application-groups", [])
    checks = {
        "binary_bundle_matches": bundle.get("CFBundleIdentifier") == expected["bundle_id"],
        "binary_uses_existing_distribution_certificate": actual_certificate_sha == certificate_sha,
        "profile_owner_bundle_certificate_and_shared_group_match": profile["compatible_with_existing_certificate"],
        "signed_entitlements_cover_plan": not missing_signed,
        "profile_entitlements_cover_plan": not missing_profile,
        "shared_group_in_signed_binary": isinstance(groups, list) and SHARED_GROUP in groups,
        "native_codesign_verify_passed": True,
    }
    return {"checks": checks, "profile": profile, "signed_app_groups": groups,
            "missing_signed_entitlement_keys": missing_signed,
            "missing_profile_entitlement_keys": missing_profile,
            "status": "SIGNED_GROUP_PROBE_PASS" if all(checks.values()) else "SIGNED_GROUP_PROBE_FAILED"}


def run_cross_app_owner_provisioning(folder, plan_path, *, team, identity, certificate_sha, keychain,
                                   installed_profiles, run, receipt):
    from resolve_signing_profiles import original_certificate_id, install_profile
    plan_bytes = Path(plan_path).read_bytes()
    plan = json.loads(plan_bytes)
    if plan.get("schema_version") != 1 or plan.get("scope") != "miniapps-cross-app-owner-groups":
        raise ValueError("Unexpected cross-app owner signing plan")
    if not team or plan.get("owner_team") != team or plan.get("shared_group") != SHARED_GROUP:
        raise ValueError("The plan and existing signing account must name the same owner and group")
    products = plan.get("products", [])
    if not products or len({item.get("bundle_id") for item in products}) != len(products):
        raise ValueError("The explicit plan needs distinct registered product identities")
    for product in products:
        if not re.fullmatch(r"[a-z0-9_-]+", product["role"]):
            raise ValueError("A product role must be a filename-safe plan key")
        groups = product.get("entitlements", {}).get("com.apple.security.application-groups", [])
        if SHARED_GROUP not in groups:
            raise ValueError("Every requested bridge participant must declare the shared group")
    receipt.update(status="RUNNING", scope="ACCOUNT_GROUP_PROVISIONING_AND_SIGNED_PROBES_ONLY",
                   plan_sha256=hashlib.sha256(plan_bytes).hexdigest(), owner_team=team,
                   shared_group=SHARED_GROUP, identity_audit=plan.get("identity_audit"),
                   products=[], uploads="NOT_REQUESTED", installs="NOT_REQUESTED")
    work = Path(folder) / "cross-app-owner"
    work.mkdir()
    certificate_id = original_certificate_id(apple_get("/v1/certificates", {
        "filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION",
        "fields[certificates]": "certificateType,certificateContent", "limit": 200}), certificate_sha)
    snapshots = []
    for product in products:
        entry = {"role": product["role"], "bundle_id": product["bundle_id"], "status": "DISCOVERING_CURRENT_GROUPS"}
        receipt["products"].append(entry)
        entry["registered_identity"] = _registered_identity(product)
        entry["capabilities_before"] = _capabilities(product["apple_bundle_resource_id"])
        _, snapshot = _profile_snapshot(product, work, team, certificate_sha, certificate_id)
        entry["profile_before_app_id_changes"] = snapshot
        entry["status"] = "CURRENT_GROUPS_READ_BACK"
        snapshots.append((product, snapshot))
    families = _resolve_native_groups(plan, snapshots)
    receipt["resolved_native_storage_families"] = families

    project = _write_probe_project(work)
    pbx = project / "project.pbxproj"
    content = pbx.read_text().replace("CODE_SIGN_STYLE = Manual;", "CODE_SIGN_STYLE = Automatic;")
    content = content.replace(
        "attributes = {LastUpgradeCheck = 2700; };",
        "attributes = {LastUpgradeCheck = 2700; TargetAttributes = {A10000000000000000000009 = {"
        "ProvisioningStyle = Automatic; SystemCapabilities = {com.apple.ApplicationGroups.iOS = {enabled = 1; }; }; }; }; };")
    pbx.write_text(content)
    key = work / "AuthKey.p8"
    key.write_bytes(decode(os.environ["ASC_KEY_P8"]))
    key.chmod(0o600)
    auth = ["-allowProvisioningUpdates", "-authenticationKeyPath", key,
            "-authenticationKeyID", os.environ["ASC_KEY_ID"],
            "-authenticationKeyIssuerID", os.environ["ASC_ISSUER_ID"]]
    development_before_ids = {value["id"] for value in _development_certificates()}
    receipt["development_identities_before_count"] = len(development_before_ids)
    receipt["signing_flow"] = "AUTOMATIC_DEVELOPMENT_ARCHIVE_THEN_EXISTING_DISTRIBUTION_EXPORT"
    try:
        for (product, snapshot), entry in zip(snapshots, receipt["products"]):
            try:
                required = dict(product["entitlements"])
                groups = set(required["com.apple.security.application-groups"]) | set(snapshot["app_groups"])
                family = product.get("native_storage_family")
                if family:
                    groups.add(families[family]["group"])
                    entry["native_storage_group"] = families[family]
                required["com.apple.security.application-groups"] = sorted(groups)
                # Resolve the existing source build variables for this distribution probe.
                def expand(value):
                    if isinstance(value, str):
                        return (value.replace("$(TeamIdentifierPrefix)", team + ".")
                                .replace("$(CFBundleIdentifier)", product["bundle_id"])
                                .replace("$(APS_ENVIRONMENT)", "production"))
                    if isinstance(value, list):
                        return [expand(item) for item in value]
                    return value
                required = {name: expand(value) for name, value in required.items()}
                if "aps-environment" in required:
                    required["aps-environment"] = "production"
                effective_product = dict(product, entitlements=required)
                entitlements_path = work / (product["role"] + ".entitlements")
                archive_required = dict(required)
                if "aps-environment" in archive_required:
                    archive_required["aps-environment"] = "development"
                entitlements_path.write_bytes(plistlib.dumps(archive_required))
                entry["requested_app_groups"] = sorted(groups)
                entry["required_distribution_entitlement_keys"] = sorted(required)
                entry["requested_entitlements_sha256"] = hashlib.sha256(plistlib.dumps(required)).hexdigest()
                archive = work / (product["role"] + ".xcarchive")
                code, _ = run(
                    ["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery",
                     "-configuration", "Release", "-destination", "generic/platform=iOS",
                     "-derivedDataPath", work / "DerivedData", "-archivePath", archive, *auth, "archive",
                     "PRODUCT_BUNDLE_IDENTIFIER=" + product["bundle_id"],
                     "CODE_SIGN_STYLE=Automatic", "DEVELOPMENT_TEAM=" + team,
                     "CODE_SIGN_IDENTITY=Apple Development", "PROVISIONING_PROFILE_SPECIFIER=", "PROVISIONING_PROFILE=",
                     "CODE_SIGN_ENTITLEMENTS=" + str(entitlements_path), "REGISTER_APP_GROUPS=YES"],
                    "owner-groups-" + product["role"] + "-archive", timeout=300, required=False)
                entry["xcode_archive_exit"] = code
                if code:
                    entry["status"] = "XCODE_AUTOMATIC_PROVISIONING_FAILED"
                    continue
                applications = list((archive / "Products/Applications").glob("*.app"))
                if len(applications) != 1:
                    raise RuntimeError("The archive must contain the one requested probe application")
                development_profile = plistlib.loads(_private_output(
                    ["security", "cms", "-D", "-i", applications[0] / "embedded.mobileprovision"]))
                entry["development_archive_app_groups"] = development_profile.get(
                    "Entitlements", {}).get("com.apple.security.application-groups", [])

                # Registration used automatic signing; distribution remains bound to
                # the original certificate and a read-back profile covering every key.
                _, distribution_fact = _profile_snapshot(
                    effective_product, work, team, certificate_sha, certificate_id,
                    required_entitlements=required)
                entry["distribution_profile_after_registration"] = distribution_fact
                value = apple_get("/v1/profiles/" + distribution_fact["resource_id"],
                    {"fields[profiles]": "profileContent"})["data"]["attributes"]
                install_profile({"uuid": distribution_fact["uuid"],
                                 "content": decode(value["profileContent"])},
                    [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                     Path.home() / "Library/MobileDevice/Provisioning Profiles"], installed_profiles)
                options = work / (product["role"] + "-ExportOptions.plist")
                options.write_bytes(plistlib.dumps({
                    "method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                    "teamID": team, "signingCertificate": identity, "uploadSymbols": False,
                    "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True,
                    "provisioningProfiles": {product["bundle_id"]: distribution_fact["uuid"]}}))
                options.chmod(0o600)
                exported = work / (product["role"] + "-export")
                code, _ = run(
                    ["xcodebuild", "-exportArchive", "-archivePath", archive,
                     "-exportPath", exported, "-exportOptionsPlist", options],
                    "owner-groups-" + product["role"] + "-export", timeout=300, required=False)
                entry["xcode_export_exit"] = code
                if code:
                    entry["status"] = "EXISTING_DISTRIBUTION_EXPORT_FAILED"
                    continue
                app, ipa_sha = _unpack_export(exported, work / (product["role"] + "-unpacked"))
                entry["probe_ipa_sha256"] = ipa_sha
                entry.update(_read_signed_probe(app, effective_product, team, certificate_sha,
                                               work / (product["role"] + "-leaf-certificate-")))
                after = _capabilities(product["apple_bundle_resource_id"])
                entry["capabilities_after"] = after
                entry["existing_capabilities_preserved"] = set(entry["capabilities_before"]).issubset(after)
                if not entry["existing_capabilities_preserved"]:
                    entry["status"] = "CAPABILITY_READBACK_MISMATCH"
            except Exception as error:
                entry.update(status="PROVISIONING_OR_READBACK_FAILED", error_kind=type(error).__name__)
    finally:
        try:
            _cleanup_temporary_development_certificates(keychain, development_before_ids, receipt)
        except Exception as error:
            receipt["temporary_development_identity_cleanup"] = "FAILED"
            receipt["temporary_development_identity_cleanup_error"] = str(error)
        key.unlink(missing_ok=True)
    passed = (all(entry["status"] == "SIGNED_GROUP_PROBE_PASS" for entry in receipt["products"])
              and receipt["temporary_development_identity_cleanup"] == "PASS")
    receipt["status"] = "CROSS_APP_OWNER_GROUPS_READY" if passed else "CROSS_APP_OWNER_GROUPS_INCOMPLETE"
    if not passed:
        raise RuntimeError("Cross-app owner provisioning did not pass for every requested participant; see per-product receipts")
