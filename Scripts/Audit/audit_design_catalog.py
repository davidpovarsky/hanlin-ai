#!/usr/bin/env python3
"""Inventory Hanlin's native UI and catalogue consumers without changing source.

Counts are lexical source evidence, not a runtime or visual acceptance test.
Run again after integrating UI changes to refresh the dated JSON snapshot.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = (
    "AI_HLY",
    "Packages/HanlinPresentationSDK/Sources",
    "ChavrusaChatShare",
    "ChavrusaChatTranslationProvider",
    "ChavrusaChatNotificationService",
    "HanlinScriptingWidgets",
)
ROLES = "largeTitle|title2|title3|title|headline|subheadline|body|callout|footnote|caption2|caption"
DIRECT_FONT = re.compile(r"\.font\(\.(?:" + ROLES + r"|system|custom)\b")
COMPONENTS = (
    "List", "Form", "Section", "NavigationStack", "NavigationSplitView", "NavigationView",
    "Button", "Toggle", "Picker", "Menu", "Slider", "Stepper", "DatePicker",
    "TextField", "TextEditor", "DisclosureGroup", "ContentUnavailableView",
    "HanlinSearchField", "UISearchTextField", "UITextView",
)
VIEW_DECLARATION = re.compile(
    r"\b(?:struct|class)\s+(\w+)(?:<[^{}]+>)?\s*:\s*[^{\n]*(?:\bView\b|Representable\b)"
)


def count_components(source: str) -> dict[str, int]:
    counts = {
        name: len(re.findall(r"\b" + name + r"\s*(?:<[^>\n]+>)?\s*[\({]", source))
        for name in COMPONENTS
    }
    counts["searchable"] = len(re.findall(r"\.searchable\s*\(", source))
    return {key: value for key, value in counts.items() if value}


def git_value(*arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(ROOT), *arguments],
        capture_output=True, text=True, encoding="utf-8", errors="replace", check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else "unavailable"


def inventory() -> dict:
    records = []
    totals: Counter[str] = Counter()
    areas: dict[str, Counter[str]] = {}
    for folder in SOURCE_ROOTS:
        for path in sorted((ROOT / folder).rglob("*.swift")):
            data = path.read_bytes()
            source = data.decode("utf-8")
            relative = path.relative_to(ROOT).as_posix()
            components = count_components(source)
            views = VIEW_DECLARATION.findall(source)
            is_ui = "import SwiftUI" in source or bool(views) or "UIViewRepresentable" in source
            catalogue_fonts = len(re.findall(r"\bHanlinTypography\.", source))
            catalogue_metrics = len(re.findall(r"\bHanlinControlMetrics\.", source))
            residual = [
                {"line": line_number, "source": line.strip()[:220]}
                for line_number, line in enumerate(source.splitlines(), 1)
                if DIRECT_FONT.search(line) and not line.lstrip().startswith("//")
            ]
            search_candidates = [
                {"line": line_number, "source": line.strip()[:220]}
                for line_number, line in enumerate(source.splitlines(), 1)
                if re.search(r"\bTextField\s*\(", line)
                and re.search(r"search|搜索|חיפוש", line, re.IGNORECASE)
            ]
            record = {
                "path": relative,
                "sha256": hashlib.sha256(data).hexdigest(),
                "isUI": is_ui,
                "declaredViews": views,
                "nativeComponents": components,
                "catalogueFontUses": catalogue_fonts,
                "catalogueMetricUses": catalogue_metrics,
                "directFontSites": residual,
                "customSearchCandidates": search_candidates,
                "originalPaletteTokens": sorted(set(re.findall(r"\bhl[A-Z]\w+", source))),
            }
            records.append(record)
            group = folder
            if relative.startswith("AI_HLY/Downstream/"):
                group = "/".join(relative.split("/")[:3])
            elif relative.startswith("AI_HLY/Native"):
                group = "/".join(relative.split("/")[:2])
            counts = areas.setdefault(group, Counter())
            for current in (totals, counts):
                current["swiftFiles"] += 1
                current["uiFiles"] += int(is_ui)
                current["declaredViews"] += len(views)
                current["catalogueFontUses"] += catalogue_fonts
                current["catalogueMetricUses"] += catalogue_metrics
                current["directFontSites"] += len(residual)
                current["customSearchCandidates"] += len(search_candidates)
            for name, count in components.items():
                totals["component:" + name] += count
                counts["component:" + name] += count
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "gitHead": git_value("rev-parse", "HEAD"),
        "workingTree": True,
        "scope": "Native Hanlin AI app, Presentation SDK, and app extensions; source inventory only.",
        "method": "Lexical scan; constructor counts and candidates require source interpretation. No simulator, device, visual or performance validation.",
        "sourceRoots": list(SOURCE_ROOTS),
        "intentionalBoundaries": [
            "System controls own their internal typography, spacing, animation and accessibility.",
            "Named adaptive assets remain the application's central palette.",
            "Rich document sizes, glyph dimensions and code monospace are intentionally preserved.",
            "Share, notification, translation and widget targets keep system defaults and their independent target dependencies.",
            "HanlinMiniAppsApp, vendored runtimes, generated native bridges and tests are separate products or implementation infrastructure.",
        ],
        "summary": dict(sorted(totals.items())),
        "areas": {key: dict(sorted(value.items())) for key, value in sorted(areas.items())},
        "files": records,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Optional JSON path; source files are never changed.")
    args = parser.parse_args()
    result = inventory()
    if args.output:
        output = args.output if args.output.is_absolute() else ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print(json.dumps({"output": str(args.output) if args.output else None, **result["summary"]}, indent=2))


if __name__ == "__main__":
    main()
