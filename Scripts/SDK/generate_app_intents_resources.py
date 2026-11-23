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
    print("AppIntents host projection: 18 original keys, en/he/zh-Hans; canonical translations retained")

if __name__ == "__main__":
    main()
