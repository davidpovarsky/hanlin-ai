#!/usr/bin/env python3
"""Grant native calendar acceptance access to this run's owned simulator only."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib

from current_unit_xctestrun import HOST_ID, original_unit_target, product_path
from owned_simulator_receipts import verify_owned_simulator
from stage_simulator_fixtures import INSTALL_TIMEOUT_SECONDS, run_bounded

SUITE = "AI_HLYTests/HanlinAppAgentSessionOwnerTests"
METHOD = SUITE + "/actualEventKitToolRecoversTheOriginalChatAndReadsTheFullDateWindow"


def selected(selectors: str) -> bool:
    return any(value.strip().removesuffix("()") in ("AI_HLYTests", SUITE, METHOD)
               for value in selectors.split(","))


def prepare(selectors, manifest, products, log, run_id, run_attempt,
            runner=run_bounded, verify_owner=verify_owned_simulator):
    if not selected(selectors):
        return None
    log = Path(log)
    owned = verify_owner(log, run_id, run_attempt)
    simulator = owned["simulator"]
    manifest = Path(manifest).resolve(strict=True)
    products = Path(products).resolve(strict=True)
    document = plistlib.loads(manifest.read_bytes())
    _, target = original_unit_target(document)
    host = product_path(target.get("TestHostPath"), products)
    info = plistlib.loads((host / "Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != HOST_ID:
        raise RuntimeError("Calendar acceptance requires the admitted original test host")
    commands = []
    for command, timeout in [
        (["xcrun", "simctl", "install", simulator, str(host)], INSTALL_TIMEOUT_SECONDS),
        (["xcrun", "simctl", "privacy", simulator, "grant", "calendar", HOST_ID], 20),
        (["xcrun", "simctl", "privacy", simulator, "grant", "reminders", HOST_ID], 20),
    ]:
        result = runner(command, timeout_seconds=timeout)
        commands.append({"command": command, "exit_code": result.returncode,
                         "stdout": result.stdout, "stderr": result.stderr})
        if result.returncode:
            (log / "08-calendar-native-staging.json").write_text(json.dumps(
                {"status": "FAIL", "owned_simulator": owned, "commands": commands}, indent=2) + "\n")
            raise RuntimeError("Native calendar acceptance staging failed")
    receipt = {"status": "PASS", "owned_simulator": owned, "bundle_id": HOST_ID,
               "xctestrun_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
               "original_host": str(host), "selected_method": METHOD, "commands": commands}
    (log / "08-calendar-native-staging.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selectors", required=True)
    parser.add_argument("--xctestrun", required=True)
    parser.add_argument("--derived-data", required=True)
    parser.add_argument("--log-dir", required=True)
    args = parser.parse_args()
    result = prepare(args.selectors, args.xctestrun,
                     Path(args.derived_data) / "Build/Products", args.log_dir,
                     os.environ.get("GITHUB_RUN_ID"), os.environ.get("GITHUB_RUN_ATTEMPT"))
    print("Native calendar fixture grants staged" if result else "Native calendar acceptance not selected")


if __name__ == "__main__":
    main()
