#!/usr/bin/env python3
"""Verify and reuse the original signed Hanlin IPA without rebuilding it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

REPOSITORY = "davidpovarsky/hanlin-ai"
SOURCE_RUN_ID = 44663389672
SOURCE_SHA = "3ebb970c418632dcb5f765e7dcef3d4aa2103bdb"
ARTIFACT_ID = 14599261662
ARTIFACT_NAME = "ChavrusaChat-signed-ipa-143801"
BUILD_NUMBER = "143801"
APP_BUNDLE_ID = "com.itorah.chavrusachat"
APP_DISPLAY_NAME = "Hanlin AI"
EXTENDED_VA = "com.apple.developer.kernel.extended-virtual-addressing"
REQUIRED_PRIVACY = (
    "NSAlarmKitUsageDescription",
    "NSCalendarsFullAccessUsageDescription",
    "NSCameraUsageDescription",
    "NSContactsUsageDescription",
    "NSFaceIDUsageDescription",
    "NSHealthClinicalHealthRecordsShareUsageDescription",
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSRemindersFullAccessUsageDescription",
    "NSSpeechRecognitionUsageDescription",
)
EXTENSIONS = (
    ("PlugIns", "ChavrusaChatShare.appex", APP_BUNDLE_ID + ".share"),
    ("PlugIns", "HanlinScriptingWidgets.appex", APP_BUNDLE_ID + ".widgets"),
    ("Extensions", "ChavrusaChatTranslationProvider.appex", APP_BUNDLE_ID + ".translation-provider"),
    ("PlugIns", "ChavrusaChatNotificationService.appex", APP_BUNDLE_ID + ".notification-service"),
)

def demand(ok, explanation):
    if not ok:
        raise ValueError(explanation)

def cmd(*arguments):
    response = subprocess.run(arguments, capture_output=True, check=False)
    if response.returncode:
        raise ValueError("Required command failed: " + arguments[0] + " " + arguments[1])
    return response.stdout

def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as fp:
        for chunk in iter(lambda: fp.read(4 * 1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()

def inspect_source():
    run = json.loads(cmd("gh", "api", f"repos/{REPOSITORY}/actions/runs/{SOURCE_RUN_ID}"))
    demand(run["id"] == SOURCE_RUN_ID and run["head_sha"] == SOURCE_SHA,
           "Source run SHA or ID differs from the original signed candidate")
    demand(run["status"] == "completed" and run["conclusion"] == "failure",
           "Source run state changed unexpectedly")
    demand(run["repository"]["full_name"] == REPOSITORY,
           "Signed artifact source must be the original repository")
    response = json.loads(cmd("gh", "api", f"repos/{REPOSITORY}/actions/runs/{SOURCE_RUN_ID}/artifacts"))
    matches = [x for x in response["artifacts"] if x["id"] == ARTIFACT_ID
               and x["name"] == ARTIFACT_NAME and not x["expired"]]
    demand(len(matches) == 1, "Original signed IPA artifact is absent/expired or has changed identity")
    jobs = json.loads(cmd("gh", "api", f"repos/{REPOSITORY}/actions/runs/{SOURCE_RUN_ID}/jobs?per_page=100"))
    valid = any(
        {entry["name"]: entry["conclusion"] for entry in job.get("steps", [])}.get(
            "Archive signed Release app") == "success"
        and {entry["name"]: entry["conclusion"] for entry in job.get("steps", [])}.get(
            "Export App Store Connect IPA") == "success"
        for job in jobs.get("jobs", [])
    )
    demand(valid, "Original signed device archive and export did not complete successfully")
    return matches[0]

def unpack_archive(artifact_dir):
    targets = list(artifact_dir.rglob(f"ChavrusaChat-{BUILD_NUMBER}.ipa"))
    demand(len(targets) == 1, "Expected exactly one signed IPA for original build")
    ipa = targets[0].resolve()
    evidence = ipa.with_suffix(".ipa.sha256")
    demand(evidence.is_file(), "SHA-256 receipt from original export missing")
    receipt = evidence.read_text().split()[0].lower()
    demand(bool(re.fullmatch(r"[0-9a-f]{64}", receipt)), "Original SHA-256 receipt malformed")
    actual = digest(ipa)
    demand(actual == receipt, "Signed IPA bytes differ from the original export receipt")
    with zipfile.ZipFile(ipa) as archive:
        target = [n for n in archive.namelist()
                  if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        demand(len(target) == 1, "Signed IPA does not contain exactly one main app")
        info = plistlib.loads(archive.read(target[0]))
        demand(info.get("CFBundleIdentifier") == APP_BUNDLE_ID, "Unexpected IPA bundle identifier")
        demand(str(info.get("CFBundleVersion")) == BUILD_NUMBER, "Unexpected IPA build number")
        demand(info.get("CFBundleDisplayName") == APP_DISPLAY_NAME,
               f"Unexpected display name: expected {APP_DISPLAY_NAME!r}, "
               f"got {info.get('CFBundleDisplayName')!r}")
        missing = [k for k in REQUIRED_PRIVACY if not str(info.get(k, "")).strip()]
        demand(not missing, "Final signed IPA is missing required privacy descriptions: " + ", ".join(missing))
    return ipa, actual

def verify_binaries(ipa, team):
    with tempfile.TemporaryDirectory(prefix="hanlin-signed-ipa-verify-") as directory:
        root = Path(directory)
        cmd("ditto", "-x", "-k", str(ipa), str(root))
        apps = list((root / "Payload").glob("*.app"))
        demand(len(apps) == 1, "Extracted IPA does not contain one app")
        app = apps[0]
        cmd("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))
        info = plistlib.loads((app / "Info.plist").read_bytes())
        demand(info["CFBundleIdentifier"] == APP_BUNDLE_ID, "Extracted IPA identity mismatch")

        def verify_identity(bundle, bundle_id, main=False):
            cmd("codesign", "--verify", "--strict", "--verbose=2", str(bundle))
            signed = plistlib.loads(cmd("codesign", "--display", "--entitlements", "-", "--xml", str(bundle)))
            profile_path = bundle / "embedded.mobileprovision"
            demand(profile_path.is_file(), "Embedded App Store provisioning profile is missing")
            profile = plistlib.loads(cmd("security", "cms", "-D", "-i", str(profile_path)))
            demand(signed.get("com.apple.developer.team-identifier") == team,
                   "Actual signing team differs from configured Apple team")
            demand(signed.get("application-identifier") == f"{team}.{bundle_id}",
                   "Actual signing entitlements use the wrong bundle ID")
            ent = profile.get("Entitlements", {})
            demand(ent.get("application-identifier") == f"{team}.{bundle_id}",
                   "Embedded provisioning profile is for a different app")
            demand(ent.get("get-task-allow") is False, "Debug provisioning profile found in signed app")
            groups = signed.get("com.apple.security.application-groups", [])
            demand("group.com.itorah.chavrusachat" in groups
                   and "group.com.itorah.shared" in groups,
                   "Signed app or extension is missing original App Groups")
            if main:
                demand(signed.get(EXTENDED_VA) is True and ent.get(EXTENDED_VA) is True,
                       "Actual IPA or profile is missing required Extended Virtual Addressing")
                demand(signed.get("aps-environment") == "production",
                       "Actual main IPA does not have production push entitlement")
                containers = signed.get("com.apple.developer.icloud-container-identifiers", [])
                demand("iCloud.com.itorah.chavrusachat" in containers,
                       "Signed main IPA lost its original iCloud container")

        verify_identity(app, APP_BUNDLE_ID, main=True)
        for folder, name, identifier in EXTENSIONS:
            item = app / folder / name
            demand(item.is_dir(), f"App extension missing: {name}")
            ext_info = plistlib.loads((item / "Info.plist").read_bytes())
            demand(ext_info.get("CFBundleIdentifier") == identifier, f"App extension ID mismatch: {name}")
            demand(str(ext_info.get("CFBundleVersion")) == BUILD_NUMBER, f"Extension build number mismatch: {name}")
            verify_identity(item, identifier)
        demand((app / "Frameworks/NodeMobile.framework").is_dir(),
               "Required NodeMobile runtime is missing from signed IPA")
        demand((app / "RuntimeHostResources.zip").is_file(),
               "Required pinned Runtime Host resources are missing")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact-dir", required=True, type=Path)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args()
    args.evidence_dir.mkdir(parents=True, exist_ok=True)
    print("Validating original signed IPA source, not rebuilding app or running simulator", flush=True)
    source = inspect_source()
    ipa, sha = unpack_archive(args.artifact_dir)
    team = os.environ.get("APPLE_TEAM_ID", "")
    demand(bool(re.fullmatch(r"[A-Z0-9]{10}", team)), "Apple signing team must be supplied securely")
    verify_binaries(ipa, team)
    report = {
        "status": "ORIGINAL_SIGNED_IPA_VERIFIED",
        "sourceRun": SOURCE_RUN_ID,
        "sourceSha": SOURCE_SHA,
        "artifactId": ARTIFACT_ID,
        "artifactDigest": source.get("digest"),
        "bundleId": APP_BUNDLE_ID,
        "buildNumber": BUILD_NUMBER,
        "displayName": APP_DISPLAY_NAME,
        "signedIpaSha256": sha,
        "simulatorTestsExecuted": False,
        "sourceArchiveAndExportSucceeded": True,
        "signaturesAndProfilesVerified": True,
    }
    (args.evidence_dir / "signed-ipa-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a") as handle:
            handle.write(f"IPA_PATH={ipa}\n")
    print(json.dumps(report), flush=True)

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, plistlib.InvalidFileException) as exc:
        print("Signed IPA reuse blocked: " + str(exc), file=sys.stderr, flush=True)
        raise SystemExit(1)
