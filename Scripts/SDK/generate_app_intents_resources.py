#!/usr/bin/env python3
"""Project canonical SDK translations into the host table AppIntents can index."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Packages/HanlinPresentationSDK/Sources/HanlinLocalization/Resources/Localizable.xcstrings"
OUTPUT = ROOT / "Packages/HanlinWidgetSDK/HostResources/HanlinAppIntents.xcstrings"
KEYS = (
    "Script Action",
    "Run Script Action",
    "Runs an action from an installed Hanlin Script package.",
    "Action",
    "Input",
    "Widget instance",
    "Choose an installed instance. Placements using the same instance share state.",
    "Open Hanlin Camera",
    "Opens Hanlin’s camera and visual analysis.",
    "Enable Hanlin Notifications",
    "Enables notifications for Hanlin after you grant system permission.",
    "Schedule an Alarm with Hanlin",
    "Schedules a system alarm at the time you choose.",
    "Hour",
    "Minute",
    "Title",
    "Schedule Alarm",
    "Enable Notifications",
)

# New standalone Shortcuts and shared receipt UI use the same canonical table.
KEYS += (
    "Run MiniApp Action",
    "Runs a saved MiniApp action and returns its actual text, JSON or file result.",
    "Input Type",
    "JSON File",
    "Allow Long Running",
    "MiniApp Input",
    "Text",
    "Dictionary or List (JSON)",
    "MiniApp Action Result",
    "Invocation",
    "Refresh MiniApp Result",
    "Wait for MiniApp Result",
    "Waits for an existing MiniApp action and returns its text or JSON result without running it again.",
    "Running MiniApp action",
    "Preparing app storage",
    "Running saved action",
    "Action completed",
    "Choose a JSON file as input.",
    "The JSON file must contain UTF-8 text.",
    "This MiniApp action is no longer available. Select it again.",
    "This operation requires an interactive MiniApp window.",
    "This action receipt is no longer available in this app.",
    "Refresh result",
    "Action unavailable",
    "Waiting to run",
    "Running in MiniApps",
    "Action failed",
    "Action cancelled",
    "Package changed",
    "Action expired",
    "Continue in the app",
    "Action acknowledged",
    "The action returned a result that is available in the app.",
    "The installed package changed. Select its current action again.",
    "The package does not declare this action or input.",
    "Open the app to continue this action.",
    "The package reported an error. Open the app for details.",
    "The app was interrupted before a result was recorded.",
    "This action could not be completed.",
    "This action expired before it completed.",
    "This MiniApp invocation could not be found in this app.",
    "The MiniApp action did not complete successfully (%@).",
)

def render():
    catalog = json.loads(SOURCE.read_text())
    selected = {}
    for key in KEYS:
        entry = catalog["strings"][key]
        for language in ("en", "he", "zh-Hans"):
            unit = entry["localizations"][language]["stringUnit"]
            if unit["state"] != "translated" or not unit["value"]:
                raise ValueError(f"Missing original translation: {key} / {language}")
        selected[key] = entry
    return json.dumps({
        "sourceLanguage": catalog["sourceLanguage"],
        "strings": selected,
        "version": catalog["version"],
    }, ensure_ascii=False, indent=2) + "\n"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != expected:
            raise SystemExit("AppIntents host projection is stale; run Scripts/SDK/generate_app_intents_resources.py")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(expected)
    print(f"AppIntents host projection: {len(KEYS)} keys (18 original retained), en/he/zh-Hans; canonical translations retained")

if __name__ == "__main__":
    main()
