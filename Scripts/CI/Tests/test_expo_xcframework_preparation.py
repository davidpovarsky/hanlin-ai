import json
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
PREPARE_SCRIPT = REPO_ROOT / "Scripts" / "Expo" / "prepare-ios-dependencies.mjs"
LOCK_FILE = REPO_ROOT / "Scripts" / "Expo" / "dependency-lock.json"
TESTFLIGHT_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "testflight.yml"
DISPATCH_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "build-ios26-unsigned-ipa.yml"
ARTIFACTS_DIR = REPO_ROOT / "Packages" / "HanlinExpoRuntime" / "Artifacts"


class TestExpoXCFrameworkPreparation(unittest.TestCase):
    def test_testflight_workflow_removes_improvised_signing_step(self):
        content = TESTFLIGHT_WORKFLOW.read_text(encoding="utf-8")
        self.assertNotIn(
            "Validate and normalize local Expo XCFramework signatures",
            content,
            "Assistant-introduced XCFramework signing step must be completely removed from testflight.yml",
        )
        parsed_tf = yaml.safe_load(content)
        self.assertIsInstance(parsed_tf, dict)
        parsed_dispatch = yaml.safe_load(DISPATCH_WORKFLOW.read_text(encoding="utf-8"))
        self.assertIsInstance(parsed_dispatch, dict)

        steps = parsed_tf["jobs"]["build-sign-and-upload"]["steps"]
        step_names = [s.get("name", "") for s in steps]
        self.assertIn("Select Xcode 27 and verify iOS 27 SDK", step_names)
        self.assertIn("Prepare application build inputs", step_names)
        self.assertNotIn("Validate and normalize local Expo XCFramework signatures", step_names)

    def test_node_helpers_detect_broken_symlinks_and_prune_non_ios_slices(self):
        node_test_script = r"""
import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import {
  cleanBundleMetadataAndSignatures,
  findBrokenSymlinks,
  parseXCFrameworkInfoPlist,
  pruneNonIOSSlicesFromXCFramework,
  signAndVerifyXCFramework,
  validateXCFrameworkStructure,
} from './Scripts/Expo/prepare-ios-dependencies.mjs';

const rootTmp = await mkdtemp(join(tmpdir(), 'hanlin-xcf-test-'));
try {
  const fwPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>hermesvm</string>
  <key>CFBundleIdentifier</key>
  <string>dev.expo.hermesvm</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>MinimumOSVersion</key>
  <string>15.1</string>
</dict>
</plist>`;

  const xcfPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>AvailableLibraries</key>
\t<array>
\t\t<dict>
\t\t\t<key>BinaryPath</key>
\t\t\t<string>hermesvm.framework/hermesvm</string>
\t\t\t<key>LibraryIdentifier</key>
\t\t\t<string>ios-arm64</string>
\t\t\t<key>LibraryPath</key>
\t\t\t<string>hermesvm.framework</string>
\t\t\t<key>SupportedArchitectures</key>
\t\t\t<array>
\t\t\t\t<string>arm64</string>
\t\t\t</array>
\t\t\t<key>SupportedPlatform</key>
\t\t\t<string>ios</string>
\t\t</dict>
\t\t<dict>
\t\t\t<key>BinaryPath</key>
\t\t\t<string>hermesvm.framework/hermesvm</string>
\t\t\t<key>LibraryIdentifier</key>
\t\t\t<string>ios-arm64_x86_64-simulator</string>
\t\t\t<key>LibraryPath</key>
\t\t\t<string>hermesvm.framework</string>
\t\t\t<key>SupportedArchitectures</key>
\t\t\t<array>
\t\t\t\t<string>arm64</string>
\t\t\t\t<string>x86_64</string>
\t\t\t</array>
\t\t\t<key>SupportedPlatform</key>
\t\t\t<string>ios</string>
\t\t\t<key>SupportedPlatformVariant</key>
\t\t\t<string>simulator</string>
\t\t</dict>
\t\t<dict>
\t\t\t<key>BinaryPath</key>
\t\t\t<string>hermesvm.framework/Versions/1/hermesvm</string>
\t\t\t<key>LibraryIdentifier</key>
\t\t\t<string>ios-arm64_x86_64-maccatalyst</string>
\t\t\t<key>LibraryPath</key>
\t\t\t<string>hermesvm.framework</string>
\t\t\t<key>SupportedArchitectures</key>
\t\t\t<array>
\t\t\t\t<string>arm64</string>
\t\t\t\t<string>x86_64</string>
\t\t\t</array>
\t\t\t<key>SupportedPlatform</key>
\t\t\t<string>ios</string>
\t\t\t<key>SupportedPlatformVariant</key>
\t\t\t<string>maccatalyst</string>
\t\t</dict>
\t</array>
\t<key>CFBundlePackageType</key>
\t<string>XFWK</string>
\t<key>XCFrameworkFormatVersion</key>
\t<string>1.0</string>
</dict>
</plist>`;

  // 1. Test broken symlink detection (fail-closed)
  const brokenXcf = join(rootTmp, 'broken.xcframework');
  await mkdir(join(brokenXcf, 'ios-arm64', 'hermesvm.framework'), { recursive: true });
  await writeFile(join(brokenXcf, 'Info.plist'), xcfPlist, 'utf8');
  await symlink(
    join(rootTmp, 'deleted-unpack-dir', 'missing-target'),
    join(brokenXcf, 'ios-arm64', 'hermesvm.framework', 'hermesvm')
  );
  const brokenLinks = await findBrokenSymlinks(brokenXcf);
  assert.equal(brokenLinks.length, 1);
  await assert.rejects(
    () => validateXCFrameworkStructure(brokenXcf, { checkDarwinTools: false }),
    /Broken symlinks detected/
  );

  // 2. Test ExpoModulesJSI stub + stale _CodeSignature + .build-hash + pruning
  const jsiXcf = join(rootTmp, 'ExpoModulesJSI.xcframework');
  for (const slice of ['ios-arm64', 'ios-arm64_x86_64-simulator', 'ios-arm64_x86_64-maccatalyst']) {
    const fwDir = join(jsiXcf, slice, 'ExpoModulesJSI.framework');
    await mkdir(fwDir, { recursive: true });
    await writeFile(join(fwDir, 'ExpoModulesJSI'), 'stub-binary', 'utf8');
    await writeFile(join(jsiXcf, slice, '.build-hash'), 'deadbeef', 'utf8');
    await writeFile(join(jsiXcf, slice, '._ExpoModulesJSI'), 'appledouble', 'utf8');
  }
  await mkdir(join(jsiXcf, '_CodeSignature'), { recursive: true });
  await writeFile(join(jsiXcf, '_CodeSignature', 'CodeResources'), 'stale-seal', 'utf8');
  await mkdir(join(jsiXcf, 'ios-arm64', 'dSYMs'), { recursive: true });
  await writeFile(
    join(jsiXcf, 'Info.plist'),
    xcfPlist.replaceAll('hermesvm', 'ExpoModulesJSI'),
    'utf8'
  );

  // Without inner framework Info.plist, requireFrameworkInfoPlist=true must reject the stub
  await cleanBundleMetadataAndSignatures(jsiXcf);
  await pruneNonIOSSlicesFromXCFramework(jsiXcf);
  await assert.rejects(
    () =>
      validateXCFrameworkStructure(jsiXcf, {
        checkDarwinTools: false,
        requireFrameworkInfoPlist: true,
      }),
    /Missing framework Info\.plist/
  );

  // Add inner Info.plist for the 2 iOS slices and verify signAndVerifyXCFramework succeeds
  const jsiFwPlist = fwPlist.replaceAll('hermesvm', 'ExpoModulesJSI');
  await writeFile(join(jsiXcf, 'ios-arm64', 'ExpoModulesJSI.framework', 'Info.plist'), jsiFwPlist, 'utf8');
  await writeFile(
    join(jsiXcf, 'ios-arm64_x86_64-simulator', 'ExpoModulesJSI.framework', 'Info.plist'),
    jsiFwPlist,
    'utf8'
  );

  await signAndVerifyXCFramework(jsiXcf, {
    checkDarwinTools: false,
    requireFrameworkInfoPlist: true,
  });

  assert.equal(existsSync(join(jsiXcf, '_CodeSignature')), false);
  assert.equal(existsSync(join(jsiXcf, 'ios-arm64_x86_64-maccatalyst')), false);
  assert.equal(existsSync(join(jsiXcf, 'ios-arm64', '.build-hash')), false);
  assert.equal(existsSync(join(jsiXcf, 'ios-arm64', '._ExpoModulesJSI')), false);
  assert.equal(existsSync(join(jsiXcf, 'ios-arm64', 'dSYMs')), false);

  const parsedAfter = parseXCFrameworkInfoPlist(await readFile(join(jsiXcf, 'Info.plist'), 'utf8'));
  assert.deepEqual(
    parsedAfter.AvailableLibraries.map((x) => x.LibraryIdentifier).sort(),
    ['ios-arm64', 'ios-arm64_x86_64-simulator']
  );
} finally {
  await rm(rootTmp, { recursive: true, force: true });
}
"""
        proc = subprocess.run(
            ["node", "--input-type=module", "-e", node_test_script],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
        )
        self.assertEqual(
            proc.returncode,
            0,
            f"Node XCFramework preparation helper test failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}",
        )

    def test_staged_artifacts_have_valid_plists_only_ios_slices_and_no_broken_links(self):
        if not ARTIFACTS_DIR.exists():
            self.skipTest("Artifacts directory is not staged")

        lock_data = json.loads(LOCK_FILE.read_text(encoding="utf-8"))
        for item in lock_data["artifacts"]:
            xcf_dir = REPO_ROOT / item["target"]
            self.assertTrue(xcf_dir.exists(), f"Missing staged XCFramework: {xcf_dir}")
            info_plist = xcf_dir / "Info.plist"
            self.assertTrue(info_plist.exists(), f"Missing Info.plist in {xcf_dir}")

            with info_plist.open("rb") as f:
                plist_data = plistlib.load(f)

            self.assertEqual(plist_data.get("CFBundlePackageType"), "XFWK")
            libs = plist_data.get("AvailableLibraries", [])
            slice_ids = {lib["LibraryIdentifier"] for lib in libs}
            self.assertEqual(
                slice_ids,
                {"ios-arm64", "ios-arm64_x86_64-simulator"},
                f"{xcf_dir.name} should only retain ios-arm64 and ios-arm64_x86_64-simulator slices, got {slice_ids}",
            )

            for root, dirs, files in os.walk(xcf_dir, followlinks=False):
                root_path = Path(root)
                self.assertNotIn("_CodeSignature", dirs, f"Stale _CodeSignature in {root_path}")
                for name in list(dirs) + list(files):
                    full = root_path / name
                    self.assertNotEqual(name, ".build-hash", f"Stale .build-hash at {full}")
                    self.assertFalse(name.startswith("._"), f"AppleDouble file at {full}")
                    if full.is_symlink():
                        target = os.readlink(full)
                        resolved = (full.parent / target).resolve()
                        self.assertTrue(
                            resolved.exists(),
                            f"Broken symlink in {xcf_dir.name}: {full} -> {target}",
                        )


if __name__ == "__main__":
    unittest.main()
