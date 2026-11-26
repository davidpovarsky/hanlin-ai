"""Read existing owner bundle IDs/profiles; do not mutate identities or expose credentials."""
from pathlib import Path
from datetime import datetime, timezone
import json, os, sys, urllib.parse
sys.path.insert(0, str(Path(__file__).resolve().parent))
from register_miniapps_bundle import request, AppleFailure
from extension_inventory import SIGNING_TARGETS

out = Path("build/app-split-evidence")
out.mkdir(parents=True, exist_ok=True)
report = {"schema_version": 1, "status": "READBACK_PENDING",
          "source_sha": os.environ.get("GITHUB_SHA"),
          "timestamp": datetime.now(timezone.utc).isoformat(),
          "expected_group": "group.com.itorah.shared", "bundles": [],
          "scope": "Existing Apple account metadata only; no identifiers/profiles created or changed."}
try:
    page = request("/v1/bundleIds", parameters={"limit": 200})
    while True:
        for item in page.get("data", []):
            attr = item.get("attributes", {})
            identifier = attr.get("identifier", "")
            name = attr.get("name", "")
            if any(term in (identifier + " " + name).lower() for term in
                   ["hanlin", "itorah", "chavrusatext", "maktabah", "otzaria", "pinkha", "anytype"]):
                row = {"identifier": identifier, "name": name, "platform": attr.get("platform")}
                caps = request("/v1/bundleIds/" + item["id"] + "/bundleIdCapabilities")
                row["capabilities"] = [c.get("attributes", {}).get("capabilityType") for c in caps.get("data", [])]
                row["app_groups_capability"] = "APP_GROUPS" in row["capabilities"]
                report["bundles"].append(row)
        link = page.get("links", {}).get("next")
        if not link: break
        parsed = urllib.parse.urlparse(link)
        if parsed.netloc != "api.appstoreconnect.apple.com" or parsed.path != "/v1/bundleIds":
            raise ValueError("Unexpected next-page location")
        page = request(parsed.path, parameters=dict(urllib.parse.parse_qsl(parsed.query)))
    observed = {row["identifier"] for row in report["bundles"]}
    report["declared_shipping_targets"] = [
        {"role": target.role, "owner": target.owner, "target": target.target,
         "bundle_id": target.bundle, "registered": target.bundle in observed,
         "entitlements_source": target.entitlements}
        for target in SIGNING_TARGETS]
    report["missing_declared_shipping_bundles"] = sorted(
        target.bundle for target in SIGNING_TARGETS if target.bundle not in observed)
    report["profile_and_signed_entitlement_readiness"] = "NOT_PROVEN_BY_REGISTRATION_READBACK"
    report["status"] = "EXISTING_BUNDLES_READ_BACK"
    report["remaining"] = [
        "APP_GROUPS capability alone does not prove assignment of group.com.itorah.shared.",
        "Each signed target must match its own source entitlements and the owner Team ID; capture requests no App Groups.",
        "Anytype upstream io.anytype.app is not an owner registered identity unless present here."
    ]
except Exception as error:
    report["status"] = "READBACK_FAILED"
    report["error"] = {"type": type(error).__name__,
                       "status": getattr(error, "status", None),
                       "codes": getattr(error, "codes", [])}
finally:
    (out / "cross-app-apple-identities.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))
raise SystemExit(0 if report["status"] == "EXISTING_BUNDLES_READ_BACK" else 1)
