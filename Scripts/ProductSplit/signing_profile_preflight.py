"""Bounded Xcode profile-discovery preflight, not product acceptance.

All probe products remain in the existing private signing directory. Xcode builds
and locally exports tiny applications using the six original bundle/profile
identities. Nothing is uploaded, installed, or treated as a release artifact.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import tempfile
import time
import uuid
import zipfile

from audit_release_resources import ROLES, ROOT, evaluate_profile


def installed_profile_receipt(profiles, directories, receipt):
    """Read the installed CMS bytes, not merely the in-memory API response."""
    receipt.update(status="NOT_RUN", profiles=[])
    home = Path.home()
    receipt["python_home"] = str(home)
    receipt["effective_uid"] = os.geteuid()
    import pwd
    receipt["account_home_matches_python_home"] = (
        Path(pwd.getpwuid(os.geteuid()).pw_dir).resolve() == home.resolve())
    # Ask Foundation separately; HOME and account home can disagree on CI.
    foundation = subprocess.run(
        ["/usr/bin/osascript", "-l", "JavaScript", "-e",
         'ObjC.import("Foundation"); $.NSHomeDirectory().js'],
        capture_output=True, text=True, timeout=15)
    receipt["foundation_home_observed"] = foundation.returncode == 0
    receipt["foundation_home_matches_python_home"] = (
        foundation.returncode == 0 and
        Path(foundation.stdout.strip()).resolve() == home.resolve())
    for profile in profiles:
        identifier = str(uuid.UUID(profile["uuid"])).upper()
        digest = hashlib.sha256(profile["content"]).hexdigest()
        item = {"bundle_id": profile["bundle"], "uuid": identifier,
                "expected_sha256": digest, "locations": []}
        receipt["profiles"].append(item)
        for directory in directories:
            path = Path(directory) / (identifier + ".mobileprovision")
            facts = {"cache": str(Path(directory).relative_to(home)),
                     "exists": path.exists(), "symlink": path.is_symlink()}
            item["locations"].append(facts)
            if not facts["exists"] or facts["symlink"]:
                raise RuntimeError("Installed profile is missing or a symlink: " + profile["bundle"])
            info = path.stat()
            facts.update(regular=stat.S_ISREG(info.st_mode),
                         owner_matches=info.st_uid == os.geteuid(),
                         mode=oct(stat.S_IMODE(info.st_mode)), links=info.st_nlink)
            raw = path.read_bytes()
            facts["actual_sha256"] = hashlib.sha256(raw).hexdigest()
            facts["bytes_match"] = raw == profile["content"]
            if not facts["regular"] or not facts["bytes_match"]:
                raise RuntimeError("Installed profile bytes changed: " + profile["bundle"])
            decoded = subprocess.run(["security", "cms", "-D", "-i", str(path)],
                                     capture_output=True, timeout=15)
            if decoded.returncode:
                raise RuntimeError("Installed profile CMS decode failed: " + profile["bundle"])
            payload = plistlib.loads(decoded.stdout)
            facts["cms_uuid_matches"] = str(uuid.UUID(payload["UUID"])).upper() == identifier
            facts["platforms"] = payload.get("Platform", [])
            facts["der_profile_present"] = isinstance(payload.get("DER-Encoded-Profile"), bytes)
            if not facts["cms_uuid_matches"]:
                raise RuntimeError("Installed profile UUID mismatch: " + profile["bundle"])
    receipt["status"] = "VERIFIED_FILESYSTEM_AND_CMS_ONLY"
    return receipt


def retain_distribution_logs(raw_output, destination, sanitize):
    """Preserve only sanitized text logs emitted by this xcodebuild invocation."""
    receipts = []
    temp_root = Path(tempfile.gettempdir()).resolve()
    for value in dict.fromkeys(re.findall(
            r'Created bundle at path "([^"\n]+\.xcdistributionlogs)"', raw_output)):
        bundle = Path(value)
        resolved = bundle.resolve()
        if (bundle.is_symlink() or not resolved.is_relative_to(temp_root)
                or not resolved.is_dir() or resolved.stat().st_uid != os.geteuid()):
            raise RuntimeError("Unexpected Xcode distribution-log location")
        target = Path(destination)
        target.mkdir(parents=True, exist_ok=True)
        for source in sorted(resolved.rglob("*.log")):
            if source.is_symlink() or not source.is_file():
                continue
            size = source.stat().st_size
            if size > 8 * 1024 * 1024:
                raise RuntimeError("Xcode distribution log exceeds bounded retention")
            raw = source.read_bytes()
            relative = source.relative_to(resolved)
            output = target / relative
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(sanitize(raw.decode("utf-8", errors="replace")), encoding="utf-8")
            receipts.append({"file": str(relative),
                             "sanitized_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                             "source_bytes": size})
    return receipts


def _write_probe_project(directory):
    """A dependency-free application whose sole purpose is Xcode profile lookup."""
    project = directory / "ProfileDiscovery.xcodeproj"
    project.mkdir()
    (directory / "main.c").write_text("int main(void) { return 0; }\n", encoding="utf-8")
    (directory / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleDevelopmentRegion": "en", "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
        "LSRequiresIPhoneOS": True, "UILaunchScreen": {},
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait",
                                            "UIInterfaceOrientationPortraitUpsideDown",
                                            "UIInterfaceOrientationLandscapeLeft",
                                            "UIInterfaceOrientationLandscapeRight"]
    }))
    (project / "project.pbxproj").write_text("""// !$*UTF8*$!
{
 archiveVersion = 1;
 classes = {};
 objectVersion = 56;
 objects = {
  A10000000000000000000001 = {isa = PBXBuildFile; fileRef = A10000000000000000000002; };
  A10000000000000000000002 = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.c; path = main.c; sourceTree = "<group>"; };
  A10000000000000000000003 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = ProfileDiscovery.app; sourceTree = BUILT_PRODUCTS_DIR; };
  A10000000000000000000004 = {isa = PBXGroup; children = (A10000000000000000000002, A10000000000000000000005); sourceTree = "<group>"; };
  A10000000000000000000005 = {isa = PBXGroup; children = (A10000000000000000000003); name = Products; sourceTree = "<group>"; };
  A10000000000000000000006 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A10000000000000000000001); runOnlyForDeploymentPostprocessing = 0; };
  A10000000000000000000007 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
  A10000000000000000000008 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
  A10000000000000000000009 = {
   isa = PBXNativeTarget; buildConfigurationList = A1000000000000000000000A;
   buildPhases = (A10000000000000000000006, A10000000000000000000007, A10000000000000000000008);
   buildRules = (); dependencies = (); name = ProfileDiscovery; productName = ProfileDiscovery;
   productReference = A10000000000000000000003; productType = "com.apple.product-type.application";
  };
  A1000000000000000000000A = {isa = XCConfigurationList; buildConfigurations = (A1000000000000000000000B); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
  A1000000000000000000000B = {
   isa = XCBuildConfiguration; name = Release;
   buildSettings = {
    CODE_SIGN_STYLE = Manual; INFOPLIST_FILE = Info.plist; GENERATE_INFOPLIST_FILE = NO;
    IPHONEOS_DEPLOYMENT_TARGET = 15.0; PRODUCT_NAME = "$(TARGET_NAME)";
    SDKROOT = iphoneos; SUPPORTED_PLATFORMS = iphoneos; TARGETED_DEVICE_FAMILY = "1,2";
    SKIP_INSTALL = NO; ENABLE_BITCODE = NO;
   };
  };
  A1000000000000000000000C = {isa = XCConfigurationList; buildConfigurations = (A1000000000000000000000D); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
  A1000000000000000000000D = {isa = XCBuildConfiguration; name = Release; buildSettings = {CLANG_ENABLE_MODULES = YES; }; };
  A1000000000000000000000E = {
   isa = PBXProject; attributes = {LastUpgradeCheck = 2700; };
   buildConfigurationList = A1000000000000000000000C; compatibilityVersion = "Xcode 14.0";
   developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base);
   mainGroup = A10000000000000000000004; productRefGroup = A10000000000000000000005;
   projectDirPath = ""; projectRoot = ""; targets = (A10000000000000000000009);
  };
 };
 rootObject = A1000000000000000000000E;
}
""", encoding="utf-8")
    scheme = project / "xcshareddata/xcschemes"
    scheme.mkdir(parents=True)
    (scheme / "ProfileDiscovery.xcscheme").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES">
  <BuildActionEntries><BuildActionEntry buildForTesting="NO" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="YES" buildForAnalyzing="NO">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000009" BuildableName="ProfileDiscovery.app" BlueprintName="ProfileDiscovery" ReferencedContainer="container:ProfileDiscovery.xcodeproj"/>
  </BuildActionEntry></BuildActionEntries>
 </BuildAction>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="NO"/>
</Scheme>
""", encoding="utf-8")
    return project


def run_profile_discovery_preflight(folder, profiles, team, identity, certificate_sha, run, receipt):
    """At most four minutes, stopping on the first native failure."""
    receipt.update(status="RUNNING", scope="PROFILE_DISCOVERY_ONLY_NOT_PRODUCT_ACCEPTANCE",
                   native_products=[], deadline_seconds=240)
    deadline = time.monotonic() + 240
    work = Path(folder) / "profile-discovery"
    work.mkdir()
    project = _write_probe_project(work)

    def bounded(argv, label):
        remaining = int(deadline - time.monotonic())
        if remaining <= 0:
            raise RuntimeError("Bounded Xcode profile-discovery deadline reached")
        code, _ = run(argv, label, timeout=min(60, remaining), required=False)
        if code:
            raise RuntimeError(label + " failed before original product archives")

    def private_native(argv):
        remaining = int(deadline - time.monotonic())
        if remaining <= 0:
            raise RuntimeError("Bounded Xcode profile-discovery deadline reached")
        return subprocess.run([str(value) for value in argv], capture_output=True,
                              timeout=min(15, remaining), check=True)

    ordered = sorted(profiles, key=lambda p: p["bundle"] != "com.itorah.hanlinminiapps")
    roles = {bundle: (role, source) for role, bundle, _, source in ROLES}
    try:
        for profile in ordered:
            role, source = roles[profile["bundle"]]
            entitlements = ROOT / source
            required = plistlib.loads(entitlements.read_bytes())
            entry = {"role": role, "bundle_id": profile["bundle"],
                     "uuid": profile["uuid"], "archive": "NOT_RUN", "export": "NOT_RUN",
                     "required_entitlements_source": source,
                     "required_entitlements_sha256": hashlib.sha256(entitlements.read_bytes()).hexdigest()}
            receipt["native_products"].append(entry)
            archive = work / (role + ".xcarchive")
            bounded(["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery",
                     "-configuration", "Release", "-destination", "generic/platform=iOS",
                     "-derivedDataPath", work / "DerivedData", "-archivePath", archive, "archive",
                     "PRODUCT_BUNDLE_IDENTIFIER=" + profile["bundle"],
                     "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=" + team,
                     "CODE_SIGN_IDENTITY=" + identity,
                     "PROVISIONING_PROFILE_SPECIFIER=" + profile["uuid"], "PROVISIONING_PROFILE=",
                     "CODE_SIGN_ENTITLEMENTS=" + str(entitlements), "APS_ENVIRONMENT=production"],
                    "profile-discovery-" + role + "-archive")
            entry["archive"] = "EXECUTED_PASS"
            options = work / (role + "-ExportOptions.plist")
            options.write_bytes(plistlib.dumps({
                "method": "app-store-connect", "destination": "export", "signingStyle": "manual",
                "teamID": team, "signingCertificate": identity, "uploadSymbols": False,
                "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True,
                "provisioningProfiles": {profile["bundle"]: profile["uuid"]}
            }))
            options.chmod(0o600)
            exported = work / (role + "-export")
            bounded(["xcodebuild", "-exportArchive", "-archivePath", archive,
                     "-exportPath", exported, "-exportOptionsPlist", options],
                    "profile-discovery-" + role + "-export")
            entry["export"] = "EXECUTED_PASS"
            ipas = list(exported.glob("*.ipa"))
            if len(ipas) != 1:
                raise RuntimeError("Profile-discovery export has no unique IPA")
            with zipfile.ZipFile(ipas[0]) as package:
                names = [name for name in package.namelist()
                         if re.fullmatch(r"Payload/[^/]+\.app/embedded\.mobileprovision", name)]
                if len(names) != 1:
                    raise RuntimeError("Profile-discovery export has no unique embedded profile")
                digest = hashlib.sha256(package.read(names[0])).hexdigest()
                for member in package.infolist():
                    path = Path(member.filename)
                    if path.is_absolute() or ".." in path.parts or stat.S_ISLNK(member.external_attr >> 16):
                        raise RuntimeError("Unexpected profile-discovery IPA member")
                unpacked = work / (role + "-unpacked")
                package.extractall(unpacked)
            entry["embedded_profile_sha256"] = digest
            if digest != hashlib.sha256(profile["content"]).hexdigest():
                raise RuntimeError("Xcode exported a different profile than requested")
            entry["exact_profile_embedded"] = True
            apps = list((unpacked / "Payload").glob("*.app"))
            if len(apps) != 1:
                raise RuntimeError("Profile-discovery payload is ambiguous")
            bounded(["codesign", "--verify", "--deep", "--strict", apps[0]],
                    "profile-discovery-" + role + "-signature")
            embedded = private_native(["security", "cms", "-D", "-i",
                apps[0] / "embedded.mobileprovision"])
            signed = private_native(["codesign", "--display", "--entitlements", "-", "--xml", apps[0]])
            raw = signed.stdout + signed.stderr
            start = raw.find(b"<?xml")
            end = raw.find(b"</plist>", start)
            if start < 0 or end < start:
                raise RuntimeError("Profile-discovery signature has no XML entitlements")
            actual = plistlib.loads(embedded.stdout)
            actual["Entitlements"] = plistlib.loads(raw[start:end + len(b"</plist>")])
            check = evaluate_profile(actual, required, profile["bundle"], team, certificate_sha,
                                     datetime.now(timezone.utc))
            entry["actual_signature_checks"] = check
            if check["status"] != "READY_RESOURCE":
                raise RuntimeError("Profile-discovery signature lacks original entitlements")
            public_prefix = work / (role + "-certificate-")
            private_native(["codesign", "--display", "--extract-certificates=" + str(public_prefix), apps[0]])
            entry["original_certificate_matches"] = (
                hashlib.sha256(Path(str(public_prefix) + "0").read_bytes()).hexdigest() == certificate_sha)
            if not entry["original_certificate_matches"]:
                raise RuntimeError("Profile-discovery signature uses a different certificate")
        receipt["status"] = "EXECUTED_PASS"
    except Exception:
        receipt["status"] = "EXECUTED_FAIL"
        raise
