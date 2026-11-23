"""Read only registered owner identities and exact groups granted by Apple profiles.

The API response and decoded CMS payload stay in memory or mode-0600 temporary
files. The report contains identifiers, public profile metadata and booleans only.
An APP_GROUPS capability is not evidence of a particular group assignment.
"""
from datetime import datetime, timezone
import hashlib
import urllib.parse

SHARED_GROUP = "group.com.itorah.shared"
EXPECTED_OWNER_TEAM = "NA6HPWARQ2"
IDENTITY_TERMS = (
    "hanlin", "itorah", "chavrusatext", "maktabah", "otzaria", "pinkha",
    "anytype", "povarsky", "אוצריא", "פנכה", "פינכה",
)


def all_records(get, path, parameters=None):
    """Follow complete Apple pagination while retaining the same resource path."""
    result = []
    visited = set()
    parameters = dict(parameters or {})
    while True:
        identity = (path, tuple(sorted(parameters.items())))
        if identity in visited:
            raise ValueError("Repeated Apple pagination cursor")
        visited.add(identity)
        page = get(path, parameters)
        rows = page.get("data")
        if not isinstance(rows, list):
            raise ValueError("Expected an Apple resource list")
        result.extend(rows)
        following = page.get("links", {}).get("next")
        if not following:
            return result
        parsed = urllib.parse.urlparse(following)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com" or parsed.path != path:
            raise ValueError("Unexpected Apple pagination origin or resource")
        parameters = dict(urllib.parse.parse_qsl(parsed.query))


def profile_fact(profile, *, bundle, team, certificate_sha, now):
    """Extract only public signing identity facts, never devices or certificate data."""
    entitlements = profile.get("Entitlements", {})
    groups = entitlements.get("com.apple.security.application-groups", [])
    if not isinstance(groups, list):
        groups = []
    groups = sorted(value for value in groups if isinstance(value, str))
    teams = [value for value in profile.get("TeamIdentifier", []) if isinstance(value, str)]
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ValueError("Profile expiration is missing")
    expiration = expiration.replace(tzinfo=timezone.utc) if expiration.tzinfo is None else expiration.astimezone(timezone.utc)
    certificates = {hashlib.sha256(value).hexdigest()
                    for value in profile.get("DeveloperCertificates", []) if isinstance(value, bytes)}
    prefixes = profile.get("ApplicationIdentifierPrefix", [team])
    checks = {
        "owner_team_matches": bool(team) and team in teams,
        "bundle_matches": any(entitlements.get("application-identifier") == prefix + "." + bundle
                              for prefix in prefixes if isinstance(prefix, str)),
        "not_expired": expiration > now,
        "shared_group_granted": SHARED_GROUP in groups,
        "existing_distribution_certificate_matches": bool(certificate_sha) and certificate_sha in certificates,
    }
    return {
        "name": profile.get("Name"), "uuid": profile.get("UUID"),
        "team_ids": teams, "app_identifier_prefixes": prefixes, "application_identifier": entitlements.get("application-identifier"),
        "app_groups": groups, "expiration": expiration.isoformat(), "checks": checks,
        "signed_profile_supports_shared_group": all(checks[key] for key in (
            "owner_team_matches", "bundle_matches", "not_expired", "shared_group_granted")),
        "compatible_with_existing_certificate": all(checks.values()),
        "distribution": entitlements.get("get-task-allow") is False,
    }


def error_fact(error):
    # Never forward arbitrary exception text that might contain raw responses.
    return {"kind": type(error).__name__}


def audit_cross_app_resources(get, decode_profile, *, certificate_sha, team, now, missing_credentials=()):
    report = {
        "expected_team": EXPECTED_OWNER_TEAM, "team_secret_matches_expected_owner": team == EXPECTED_OWNER_TEAM,
        "expected_app_group": SHARED_GROUP, "scope": "GET-only existing bundle and profile metadata",
        "bundle_inventory_complete": False, "bundle_inventory": [], "candidate_products": [],
        "limitations": [
            "APP_GROUPS capability alone does not establish assignment of the exact shared group.",
            "Profile entitlements are evidence of their issued grants; this audit does not install or sign an app.",
            "A registered identity is not automatically selected as the shipping Anytype/Pinkha product.",
            "Original upstream Anytype signing settings are not changed.",
        ],
    }
    if missing_credentials:
        report.update(status="MISSING_CREDENTIALS", missing_secret_names=list(missing_credentials))
        return report
    try:
        bundles = all_records(get, "/v1/bundleIds",
                             {"fields[bundleIds]": "identifier,name,platform", "limit": 200})
        report["bundle_inventory_complete"] = True
        for bundle in bundles:
            attributes = bundle.get("attributes", {})
            row = {"resource_id": bundle.get("id"), "bundle_id": attributes.get("identifier"),
                   "name": attributes.get("name"), "platform": attributes.get("platform")}
            report["bundle_inventory"].append(row)
        candidates = [row for row in report["bundle_inventory"]
                      if row["platform"] in {"IOS", "UNIVERSAL"}
                      and any(term in ((row["bundle_id"] or "") + " " + (row["name"] or "")).lower()
                              for term in IDENTITY_TERMS)]
        for identity in candidates:
            product = dict(identity)
            product["profiles"] = []
            try:
                prefix = "/v1/bundleIds/" + identity["resource_id"]
                capabilities = all_records(get, prefix + "/bundleIdCapabilities", {"limit": 200})
                product["capability_types"] = sorted(set(
                    row.get("attributes", {}).get("capabilityType") for row in capabilities
                    if row.get("attributes", {}).get("capabilityType")))
                product["capability_inventory_complete"] = True
                profiles = all_records(get, prefix + "/profiles",
                    {"fields[profiles]": "name,profileState,profileType,expirationDate", "limit": 200})
                product["profile_inventory_complete"] = True
                for resource in profiles:
                    attributes = resource.get("attributes", {})
                    profile_row = {"resource_id": resource.get("id"),
                        "portal_name": attributes.get("name"), "profile_type": attributes.get("profileType"),
                        "profile_state": attributes.get("profileState"), "portal_expiration": attributes.get("expirationDate")}
                    try:
                        content = get("/v1/profiles/" + resource["id"], {"fields[profiles]": "profileContent"})
                        encoded = content["data"]["attributes"]["profileContent"]
                        profile_row.update(profile_fact(decode_profile(encoded), bundle=identity["bundle_id"],
                            team=team, certificate_sha=certificate_sha, now=now))
                        profile_row["active"] = attributes.get("profileState") == "ACTIVE"
                        profile_row["usable_existing_shared_group_profile"] = (
                            profile_row["active"] and profile_row["compatible_with_existing_certificate"])
                    except Exception as error:
                        profile_row.update(status="PROFILE_READ_FAILED", error=error_fact(error))
                    product["profiles"].append(profile_row)
                product["usable_shared_group_profile_count"] = sum(
                    bool(row.get("usable_existing_shared_group_profile")) for row in product["profiles"])
            except Exception as error:
                product.update(status="PRODUCT_READ_FAILED", error=error_fact(error))
            report["candidate_products"].append(product)
        report["status"] = "OWNER_RESOURCES_READ_BACK"
        if any(product.get("status") == "PRODUCT_READ_FAILED"
               or any(profile.get("status") == "PROFILE_READ_FAILED" for profile in product["profiles"])
               for product in report["candidate_products"]):
            report["status"] = "PARTIAL_READBACK"
    except Exception as error:
        report.update(status="READBACK_FAILED", error=error_fact(error))
    return report
