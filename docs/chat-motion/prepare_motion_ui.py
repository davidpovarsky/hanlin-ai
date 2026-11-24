"""Prepare the original Motion fixture as a real consumer of the pinned shared SDK.

Only the fixture app/test sources are staged. Production implementations and
resources come from the existing selected-product installer, without snippets.
Preparation is portable; compiling/running the UIKit fixture requires Apple.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

from record_sdk_inputs import record_profile

ROOT = Path(__file__).resolve().parents[2]
APP = "docs/chat-motion/MotionUI/App.swift"
TEST = "docs/chat-motion/MotionUI/MotionUITests.swift"
PRODUCTS = ["HanlinChatUI"]


def spec():
    common = {"GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "6.0",
              "CODE_SIGNING_ALLOWED": "NO", "TARGETED_DEVICE_FAMILY": "1,2",
              "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES"}
    return {
        "name": "ChatMotionProof", "options": {"deploymentTarget": {"iOS": "27.0"}},
        "settings": {"base": common},
        "packages": {"HanlinSDK": {"path": "Vendor/HanlinSDK"}},
        "targets": {
            "ChatMotionProof": {
                "type": "application", "platform": "iOS", "sources": ["App"],
                "dependencies": [{"package": "HanlinSDK", "product": "HanlinChatUI"}],
                "settings": {"base": {
                    "PRODUCT_BUNDLE_IDENTIFIER": "ai.hanlin.motion-proof",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "",
                    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":
                        "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"}}},
            "ChatMotionProofUITests": {
                "type": "bundle.ui-testing", "platform": "iOS", "sources": ["UITests"],
                "dependencies": [{"target": "ChatMotionProof"}],
                "settings": {"base": {"PRODUCT_BUNDLE_IDENTIFIER": "ai.hanlin.motion-proof.uitests",
                                        "TEST_TARGET_NAME": "ChatMotionProof"}}}},
        "schemes": {"ChatMotionProof": {"build": {"targets": {"ChatMotionProof": "all"}},
                                           "test": {"targets": ["ChatMotionProofUITests"]}}}}


def prepare(destination):
    destination = destination.resolve()
    if destination.exists() or destination.is_relative_to(ROOT):
        raise ValueError("A fresh scratch path outside the checkout is required")
    revision = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    for directory in ["App", "UITests"]:
        (destination / directory).mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / APP, destination / "App/App.swift")
    shutil.copyfile(ROOT / TEST, destination / "UITests/MotionUITests.swift")
    (destination / "project.json").write_text(json.dumps(spec(), indent=2) + "\n")
    lock = destination / "HanlinSDK.lock.json"
    lock.write_text(json.dumps({"revision": revision, "products": PRODUCTS}, indent=2) + "\n")
    module_spec = importlib.util.spec_from_file_location("hanlin_motion_sdk_installer", ROOT / "Scripts/SDK/install.py")
    installer = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(installer)
    installation = installer.install(destination, lock, "Vendor/HanlinSDK",
                                     destination / "native-cache", source_cache=ROOT)
    if installation["binaryTargets"]:
        raise ValueError("The Motion component profile must not select native runtime binaries")
    receipt = record_profile(destination, ROOT)
    (destination / "proof-inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.output), indent=2))


if __name__ == "__main__":
    main()
