"""Bounded Xcode profile-discovery preflight, not product acceptance.

All probe products remain in the existing private signing directory. Xcode builds
and locally exports tiny applications using the six original bundle/profile
identities. Nothing is uploaded, installed, or treated as a release artifact.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
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



_CMS_DIAGNOSTIC_SOURCE = r"""
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <Security/CMSDecoder.h>
#import <CommonCrypto/CommonDigest.h>
#include <stdio.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 7) return 64;
        NSMutableArray *records = [NSMutableArray array];
        for (int index = 1; index < argc; index++) {
            NSData *data = [NSData dataWithContentsOfFile:@(argv[index])];
            NSMutableArray *signers = [NSMutableArray array];
            NSMutableDictionary *record = [@{
                @"index": @(index - 1), @"read_ok": data != nil ? @YES : @NO,
                @"signers": signers
            } mutableCopy];
            [records addObject:record];
            if (!data || data.length > 1024 * 1024) continue;
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
            NSMutableString *hex = [NSMutableString string];
            for (size_t j = 0; j < sizeof(digest); j++) [hex appendFormat:@"%02x", digest[j]];
            record[@"input_sha256"] = hex;
            CMSDecoderRef decoder = NULL;
            OSStatus status = CMSDecoderCreate(&decoder);
            if (status == errSecSuccess) status = CMSDecoderUpdateMessage(decoder, data.bytes, data.length);
            if (status == errSecSuccess) status = CMSDecoderFinalizeMessage(decoder);
            record[@"decoder_status"] = @(status);
            size_t count = 0;
            if (status == errSecSuccess) status = CMSDecoderGetNumSigners(decoder, &count);
            record[@"signer_count_status"] = @(status);
            record[@"signer_count"] = @(count);
            if (status == errSecSuccess && count <= 8) {
                for (size_t signer = 0; signer < count; signer++) {
                    CMSSignerStatus signature = kCMSSignerUnsigned;
                    OSStatus certificate = errSecSuccess;
                    SecTrustRef trust = NULL;
                    SecPolicyRef policy = SecPolicyCreateBasicX509();
                    OSStatus result = CMSDecoderCopySignerStatus(
                        decoder, signer, policy, true, &signature, &trust, &certificate);
                    SecTrustResultType trustResult = kSecTrustResultInvalid;
                    OSStatus trustStatus = trust ? SecTrustGetTrustResult(trust, &trustResult) : errSecParam;
                    [signers addObject:@{
                        @"index": @(signer), @"api_status": @(result),
                        @"signer_status": @(signature), @"certificate_status": @(certificate),
                        @"trust_result_status": @(trustStatus), @"trust_result": @(trustResult),
                        @"signature_and_certificate_valid": (
                            result == errSecSuccess && signature == kCMSSignerValid &&
                            certificate == errSecSuccess) ? @YES : @NO
                    }];
                    if (trust) CFRelease(trust);
                    if (policy) CFRelease(policy);
                }
            }
            if (decoder) CFRelease(decoder);
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{
            @"format_version": @1, @"profiles": records
        } options:0 error:nil];
        if (!json) return 65;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}
"""


def _native_cms_signatures_valid(rows):
    # NSJSONSerialization can encode a boxed C comparison as NSNumber 0/1.
    # Accept that exact native wire form, never general Python truthiness.
    def true_flag(value):
        return value is True or (type(value) is int and value == 1)

    return all(true_flag(row.get("read_ok")) and row.get("decoder_status") == 0
               and row.get("signer_count_status") == 0 and row.get("signer_count", 0) > 0
               and len(row.get("signers", [])) == row["signer_count"]
               and all(true_flag(signer.get("signature_and_certificate_valid"))
                       for signer in row["signers"]) for row in rows)


def profile_cms_diagnostics(folder, profiles, run, deadline):
    """Observe CMS signature/trust separately; only native Xcode establishes admission."""
    receipt = {"status": "NOT_RUN",
               "scope": "CMS_SIGNATURE_AND_BASIC_X509_ONLY_NOT_XCODE_ACCEPTANCE"}
    source = Path(folder) / "profile-cms-status.m"
    executable = Path(folder) / "profile-cms-status"
    source.write_text(_CMS_DIAGNOSTIC_SOURCE, encoding="utf-8")
    paths = []
    for profile in profiles:
        identifier = str(uuid.UUID(profile["uuid"])).upper()
        path = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles" / (
            identifier + ".mobileprovision")
        if path.is_symlink() or path.read_bytes() != profile["content"]:
            raise RuntimeError("Installed profile changed before CMS signature diagnostics")
        paths.append(path)
    try:
        remaining = int(deadline - time.monotonic())
        if remaining <= 0:
            raise RuntimeError("Profile-discovery deadline reached before CMS diagnostics")
        code, _ = run(["xcrun", "--sdk", "macosx", "clang", "-Wno-deprecated-declarations",
                       source, "-framework", "Foundation", "-framework", "Security",
                       "-o", executable], "profile-cms-diagnostic-build",
                      timeout=min(30, remaining), required=False)
        if code:
            receipt.update(status="DIAGNOSTIC_BUILD_FAILED", exit=code)
            return receipt
        remaining = int(deadline - time.monotonic())
        if remaining <= 0:
            raise RuntimeError("Profile-discovery deadline reached before CMS signature evaluation")
        code, output = run([executable, *paths], "profile-cms-signature-status",
                           timeout=min(30, remaining), required=False)
        if code:
            receipt.update(status="DIAGNOSTIC_EXECUTION_FAILED", exit=code)
            return receipt
        value = json.loads(output)
        rows = value.get("profiles", [])
        if value.get("format_version") != 1 or len(rows) != len(profiles):
            raise RuntimeError("CMS diagnostic does not cover the exact selected profiles")
        for index, (row, profile) in enumerate(zip(rows, profiles)):
            if (row.get("index") != index or row.get("input_sha256") !=
                    hashlib.sha256(profile["content"]).hexdigest()):
                raise RuntimeError("CMS diagnostic input does not match the selected profile")
            row["bundle_id"] = profile["bundle"]
        valid = _native_cms_signatures_valid(rows)
        receipt.update(status="CMS_SIGNATURES_VALID" if valid else "CMS_SIGNATURE_OR_TRUST_REJECTED",
                       profiles=rows)
    except (OSError, ValueError, RuntimeError) as error:
        receipt.update(status="DIAGNOSTIC_UNAVAILABLE", error=type(error).__name__)
    return receipt


def run_owned_process(argv, cwd, stream, timeout):
    """Return the PID of this exact child; timeout cleanup never targets other jobs."""
    with subprocess.Popen([str(value) for value in argv], cwd=cwd, stdout=stream,
                          stderr=subprocess.STDOUT) as process:
        try:
            result = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            result = -1
        return result, process.pid


def retain_owned_xcode_signing_logs(pid, started_at, ended_at, destination, sanitize):
    """Read only this invocation's PID/time interval and retain sanitized signing events."""
    if type(pid) is not int or pid <= 1:
        raise ValueError("A concrete owned xcodebuild PID is required")
    predicate = (f"processID == {pid} AND (eventMessage CONTAINS[c] \"provision\" OR "
                 "eventMessage CONTAINS[c] \"profile\" OR eventMessage CONTAINS[c] \"codesign\" OR "
                 "eventMessage CONTAINS[c] \"signing\" OR eventMessage CONTAINS[c] \"trust\")")
    result = subprocess.run(
        ["/usr/bin/log", "show", "--style", "json", "--info", "--debug",
         "--start", started_at, "--end", ended_at, "--predicate", predicate],
        capture_output=True, timeout=15)
    if result.returncode:
        return {"status": "UNAVAILABLE", "exit": result.returncode,
                "error": sanitize(result.stderr.decode("utf-8", errors="replace")[:1024])}
    if len(result.stdout) > 1024 * 1024:
        raise RuntimeError("Owned Xcode signing diagnostics exceed bounded retention")
    events = json.loads(result.stdout or b"[]")
    if not isinstance(events, list):
        raise RuntimeError("Owned Xcode diagnostics have an unexpected format")
    retained = []
    for event in events:
        if event.get("processID") != pid:
            raise RuntimeError("Xcode diagnostics include an unowned process")
        message = event.get("eventMessage", "")
        if not re.search(r"provision|profile|codesign|signing|trust", message, re.I):
            continue
        retained.append({key: event[key] for key in
                         ["timestamp", "processID", "eventMessage", "subsystem", "category"]
                         if key in event})
    target = Path(destination)
    target.write_text(sanitize(json.dumps(retained, indent=2)) + "\n", encoding="utf-8")
    return {"status": "CAPTURED" if retained else "NO_MATCHING_RECORDED_EVENTS",
            "pid": pid, "start": started_at, "end": ended_at, "events": len(retained),
            "sanitized_sha256": hashlib.sha256(target.read_bytes()).hexdigest()}


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


def observe_owned_signing_build_settings(archive_argv, probe_root, nonce, deadline):
    """Inspect the failed tiny target once; never run another archive or admit a profile."""
    receipt = {"status": "NOT_RUN", "scope": "SIGNING_SETTINGS_ONLY_NOT_PROFILE_ACCEPTANCE",
               "nonce": nonce}
    try:
        argv = [str(value) for value in archive_argv]
        root = Path(probe_root).resolve()
        if (argv.count("-project") != 1 or argv.count("-scheme") != 1
                or argv.count("archive") != 1 or Path(argv[0]).name != "xcodebuild"
                or not re.fullmatch(r"[a-f0-9]{32}", nonce)):
            raise ValueError("Unbound profile-discovery command")
        project = Path(argv[argv.index("-project") + 1]).resolve()
        target = argv[argv.index("-scheme") + 1]
        if (project.parent != root or project.name != "ProfileDiscovery.xcodeproj"
                or target != "ProfileDiscovery"
                or argv.count("HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce) != 1):
            raise ValueError("Command is outside this exact owned profile-discovery project")
        receipt["project_path_sha256"] = hashlib.sha256(str(project).encode()).hexdigest()
        receipt["archive_arguments_sha256"] = hashlib.sha256(json.dumps(argv).encode()).hexdigest()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            receipt["status"] = "DEADLINE_EXHAUSTED"
            return receipt
        settings_argv = [value for value in argv if value != "archive"]
        settings_argv += ["-showBuildSettings", "-json"]
        environment = dict(os.environ)
        # Only presence/hashes and equality facts are retained for inherited paths.
        # No user directory, xcconfig filename, or other environment value is logged.
        receipt["inherited_environment"] = {
            key: {"present": key in environment,
                  "value_sha256": hashlib.sha256(environment[key].encode()).hexdigest()
                  if key in environment else None}
            for key in ["HOME", "CFFIXED_USER_HOME", "DEVELOPER_DIR", "XCODE_XCCONFIG_FILE", "SDKROOT"]
        }
        for key in ["HOME", "CFFIXED_USER_HOME"]:
            if environment.get(key):
                receipt["inherited_environment"][key]["matches_python_home"] = (
                    Path(environment[key]).resolve() == Path.home().resolve())
        result = subprocess.run(settings_argv, cwd=ROOT, env=environment,
                                capture_output=True, timeout=min(15, remaining))
        receipt["exit"] = result.returncode
        receipt["stdout_sha256"] = hashlib.sha256(result.stdout).hexdigest()
        receipt["stderr_sha256"] = hashlib.sha256(result.stderr).hexdigest()
        if result.returncode:
            receipt["status"] = "SETTINGS_COMMAND_FAILED"
            return receipt
        if len(result.stdout) + len(result.stderr) > 512 * 1024:
            raise ValueError("Owned build settings exceed bounded diagnostic retention")
        values = json.loads(result.stdout)
        if not isinstance(values, list) or len(values) != 1 or values[0].get("target") != target:
            raise ValueError("Unexpected target inventory")
        settings = values[0].get("buildSettings")
        if (not isinstance(settings, dict)
                or Path(settings.get("PROJECT_FILE_PATH", "")).resolve() != project
                or settings.get("HANLIN_PROFILE_DISCOVERY_NONCE") != nonce):
            raise ValueError("Build settings do not belong to this exact owned invocation")
        receipt["project_and_nonce_match"] = True
        selected = dict(value.split("=", 1) for value in argv
                        if "=" in value and not value.startswith("-"))
        keys = ["CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "EXPANDED_CODE_SIGN_IDENTITY",
                "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE",
                "EXPANDED_PROVISIONING_PROFILE", "CONFIGURATION", "SDKROOT", "PLATFORM_NAME",
                "SUPPORTED_PLATFORMS", "PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGNING_ALLOWED",
                "CODE_SIGNING_REQUIRED", "PROVISIONING_PROFILE_REQUIRED"]
        projected = {}
        for key in keys:
            if key not in settings:
                projected[key] = {"observed": False}
                continue
            value = settings[key]
            if not isinstance(value, str):
                raise ValueError("Unexpected build-setting value type")
            item = {"observed": True, "value_sha256": hashlib.sha256(value.encode()).hexdigest()}
            if key in selected:
                item["matches_selected_argument"] = value == selected[key]
            if key == "DEVELOPMENT_TEAM":
                item["value"] = "[SELECTED_TEAM]" if value == selected.get(key) else "[OTHER_TEAM]"
            elif key in {"CODE_SIGN_IDENTITY", "EXPANDED_CODE_SIGN_IDENTITY"}:
                item["value"] = value if (re.fullmatch(r"[A-Fa-f0-9]{40}", value)
                    or value in {"", "-", "Apple Distribution", "Apple Development",
                                 "iPhone Distribution", "iPhone Developer"}) else "[IDENTITY_NAME_REDACTED]"
            elif key in {"PROVISIONING_PROFILE_SPECIFIER", "PROVISIONING_PROFILE",
                         "EXPANDED_PROVISIONING_PROFILE"}:
                item["value"] = value if (not value or re.fullmatch(
                    r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", value)) else "[PROFILE_NAME_REDACTED]"
            elif key == "SDKROOT":
                leaf = Path(value).name
                item["value"] = leaf if re.fullmatch(
                    r"(?:iPhoneOS|iPhoneSimulator|MacOSX)[0-9.]*\.sdk|iphoneos|iphonesimulator|macosx", leaf) else "[SDK_PATH_REDACTED]"
            else:
                item["value"] = value if len(value) <= 160 and re.fullmatch(
                    r"[A-Za-z0-9_. -]*", value) else "[SETTING_REDACTED]"
            projected[key] = item
        receipt.update(status="OBSERVED_SETTINGS", target=target, settings=projected)
    except subprocess.TimeoutExpired:
        receipt["status"] = "SETTINGS_COMMAND_TIMED_OUT"
    except (OSError, ValueError, TypeError, IndexError) as error:
        receipt.update(status="DIAGNOSTIC_UNAVAILABLE", error=type(error).__name__)
    return receipt


def run_profile_discovery_preflight(folder, profiles, team, identity, certificate_sha, run, receipt):
    """At most four minutes, stopping on the first native failure."""
    receipt.update(status="RUNNING", scope="PROFILE_DISCOVERY_ONLY_NOT_PRODUCT_ACCEPTANCE",
                   native_products=[], deadline_seconds=240)
    deadline = time.monotonic() + 240
    work = Path(folder) / "profile-discovery"
    work.mkdir()
    project = _write_probe_project(work)
    nonce = uuid.uuid4().hex
    receipt["probe_nonce"] = nonce
    receipt["cms_signatures"] = profile_cms_diagnostics(work, profiles, run, deadline)

    def bounded(argv, label, entry=None, key=None):
        remaining = int(deadline - time.monotonic())
        # Keep up to 15 seconds within the existing deadline for the owned
        # Xcode failure diagnostics; a fresh native attempt must fit both.
        if remaining <= 15:
            raise RuntimeError("Bounded Xcode profile-discovery deadline reached")
        if entry is not None:
            entry[key] = "RUNNING"
        try:
            code, _ = run(argv, label, timeout=min(60, remaining - 15), required=False)
            if code:
                raise RuntimeError(label + " failed before original product archives")
        except Exception:
            if entry is not None:
                entry[key] = "EXECUTED_FAIL"
                if key == "archive":
                    try:
                        entry["build_settings_diagnostic"] = observe_owned_signing_build_settings(
                            argv, work, nonce, deadline)
                    except Exception as diagnostic_error:
                        # The diagnostic never replaces the original archive failure.
                        entry["build_settings_diagnostic"] = {
                            "status": "DIAGNOSTIC_UNAVAILABLE", "error": type(diagnostic_error).__name__}
            raise
        if entry is not None:
            entry[key] = "EXECUTED_PASS"

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
                     "CODE_SIGN_ENTITLEMENTS=" + str(entitlements), "APS_ENVIRONMENT=production",
                     "HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce],
                    "profile-discovery-" + role + "-archive", entry, "archive")
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
                    "profile-discovery-" + role + "-export", entry, "export")
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
