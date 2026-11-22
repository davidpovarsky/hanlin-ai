#!/usr/bin/env python3
"""Check the actual composer geometry against keyboard/panel/accessory budgets.

Requires Swift 6 with Foundation. No SwiftUI or UIKit code is executed: this is
portable layout-domain evidence, not native layout, animation or device proof.
The generated fixture, executable and result.json are written to --output-dir.
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[2])
    parser.add_argument("--output-dir", type=pathlib.Path,
                        default=pathlib.Path(tempfile.gettempdir()) / "hanlin-composer-layout-check")
    parser.add_argument("--swiftc", default="swiftc")
    args = parser.parse_args()
    root, out = args.repo_root.resolve(), args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    geometry_path = "Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Composer/HanlinMorphComposer.swift"
    catalog_path = "Packages/HanlinPresentationSDK/Sources/HanlinPresentationKit/HanlinDesignCatalog.swift"
    source_paths = [geometry_path, catalog_path,
                    "AI_HLY/Views/Components/ChatViewBottom.swift",
                    "AI_HLY/Downstream/ChatInput/HanlinModelZoomPopover.swift",
                    "AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinCompactChatWorkspace.swift",
                    "AI_HLYTests/HanlinMorphComposerTests.swift",
                    "Scripts/CI/check_composer_layout.py"]
    contents = {path: (root / path).read_text(encoding="utf-8") for path in source_paths}
    hashes = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in source_paths}
    geometry = contents[geometry_path].split("public enum HanlinMorphGeometry {", 1)[1].split("\n/// Reference shell", 1)[0]
    catalog = contents[catalog_path].split("public enum HanlinMorphStyle {", 1)[1].split("\n}", 1)[0]
    # Keep each complete CGFloat initializer, including continuation lines.
    constants = "\n".join(re.findall(r"    public static let \w+: CGFloat =.*?(?=\n    public static let|\Z)", catalog, re.S))
    fixture = r'''
@main
struct ComposerLayoutChecks {
    static func main() {
        var scenarios = 0
        var assertions = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            assertions += 1
        }
        for available in [CGFloat(240), 320, 480, 800] {
            for toolbar in [CGFloat(30), 60] {
                for capabilities in [CGFloat(0), 48] {
                    for accessories in [CGFloat(0), 160] {
                        for draftHeight in [CGFloat(38), 160, 900] {
                            for panel in [false, true] {
                                for expanded in [false, true] {
                                    scenarios += 1
                                    let layout = HanlinMorphGeometry.layout(
                                        availableHeight: available, accessoryNaturalHeight: accessories,
                                        capabilitiesHeight: capabilities, naturalEditorHeight: draftHeight,
                                        toolbarHeight: toolbar, isPanelExpanded: panel, isEditorExpanded: expanded)
                                    expect(layout.inputHeight.isFinite && layout.editorHeight.isFinite,
                                           "non-finite input geometry")
                                    expect(layout.inputHeight - layout.editorHeight == 64,
                                           "controls left their enclosing glass")
                                    expect(layout.editorHeight >= 38 && layout.editorHeight <= layout.editorMaximumHeight,
                                           "editor exceeds its native height budget")
                                    expect(layout.accessoryHeight >= 0 && layout.accessoryHeight <= accessories,
                                           "accessory scroll viewport exceeds content")
                                    if panel {
                                        // Native captures independently check the actual rendered material;
                                        // this guards the source contract across every budget scenario.
                                        let panelContentBottom: CGFloat = 200
                                        let plusTop = panelContentBottom + 13 + layout.inputHeight - 52
                                        let panelMaterialBottom = panelContentBottom
                                            + HanlinMorphGeometry.panelGlassExtension(inputHeight: layout.inputHeight)
                                        expect(abs(plusTop - panelMaterialBottom - 13) < 0.001,
                                               "panel material stopped short of the original bottom launcher")
                                    }
                                    let panelChrome = panel ? 32 + 14 + 13 + toolbar + 80 : 0
                                    let capabilityChrome = capabilities > 1 ? capabilities + 6 : 0
                                    let minimumRequired = capabilityChrome + panelChrome + 26 + 102
                                    if available >= minimumRequired {
                                        expect(layout.inputHeight + layout.hostOverhead + 26 + panelChrome <= available + 0.001,
                                               "combined local layout exceeds the usable host viewport")
                                        if panel {
                                            let page = HanlinMorphGeometry.pageBudget(availableHeight: available,
                                                accessoryHeight: layout.hostOverhead, inputHeight: layout.inputHeight,
                                                toolbarHeight: toolbar)
                                            expect(page >= 80 - 0.001, "attachments/editor consumed the open page")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let small = HanlinMorphGeometry.layout(availableHeight: 400, accessoryNaturalHeight: 1000,
            capabilitiesHeight: 42, naturalEditorHeight: 38, toolbarHeight: 44,
            isPanelExpanded: true, isEditorExpanded: false)
        expect(small.inputHeight == 102 && small.accessoryHeight == 35 && small.hostOverhead == 89,
               "keyboard/attachments regression fixture changed")
        func expanded(_ height: CGFloat) -> HanlinMorphGeometry.Layout {
            HanlinMorphGeometry.layout(availableHeight: height, accessoryNaturalHeight: 62,
                capabilitiesHeight: 0, naturalEditorHeight: 160, toolbarHeight: 44,
                isPanelExpanded: true, isEditorExpanded: true)
        }
        let restored = expanded(800)
        expect(expanded(400).inputHeight < restored.inputHeight, "keyboard did not reduce usable input height")
        expect(expanded(800) == restored, "local height depends on an earlier viewport/origin")
        for invalid in [CGFloat.nan, .infinity, -.infinity, -20] {
            let result = HanlinMorphGeometry.layout(availableHeight: invalid, accessoryNaturalHeight: invalid,
                capabilitiesHeight: invalid, naturalEditorHeight: invalid, toolbarHeight: invalid,
                isPanelExpanded: true, isEditorExpanded: true)
            expect(result.inputHeight == 102 && result.editorHeight == 38 && result.accessoryHeight == 0,
                   "invalid host geometry escaped the minimum stable input")
        }
        // Preserve the approved launcher and connected glass graph at rest.
        expect(HanlinMorphStyle.launcherSize == 52, "original plus size changed")
        expect(HanlinMorphStyle.launcherInputSpacing < HanlinMorphStyle.glassMergeDistance,
               "input and original plus no longer connect")
        expect(HanlinMorphStyle.panelInputSpacing < HanlinMorphStyle.glassMergeDistance,
               "panel and input no longer connect")
        let minimumRowWidth = 4 * HanlinMorphStyle.inputControlHitSize
            + 3 * HanlinMorphStyle.inputControlsSpacing + 2 * HanlinMorphStyle.inputControlsInset
            + HanlinMorphStyle.launcherSize + HanlinMorphStyle.launcherInputSpacing
            + 2 * HanlinMorphStyle.horizontalInset
        expect(minimumRowWidth <= 320, "single row cannot retain 44pt controls in the narrow host")
        print("COMPOSER_LAYOUT_PASS scenarios=\(scenarios) assertions=\(assertions)")
    }
}
'''
    swift = out / "ComposerLayoutChecks.swift"
    swift.write_text("import Foundation\npublic enum HanlinMorphStyle {\n" + constants
                     + "\n}\npublic enum HanlinMorphGeometry {" + geometry + fixture,
                     encoding="utf-8", newline="\n")
    executable = out / ("ComposerLayoutChecks.exe" if os.name == "nt" else "ComposerLayoutChecks")
    command = [args.swiftc, "-parse-as-library", "-swift-version", "6", str(swift), "-o", str(executable)]
    built = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
    version = subprocess.run([args.swiftc, "--version"], capture_output=True, text=True, timeout=15)
    result = {"recorded_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "validation_scope": "Actual composer geometry and CGFloat metrics, compiled with Foundation; no SwiftUI/UIKit/native UI execution.",
              "source_hashes": hashes, "compiler": version.stdout.strip(),
              "compile_returncode": built.returncode, "compile_output": built.stdout + built.stderr}
    if built.returncode == 0:
        run = subprocess.run([str(executable)], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
        result.update(run_returncode=run.returncode, output=run.stdout + run.stderr)
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
    return result.get("run_returncode", built.returncode)


if __name__ == "__main__":
    sys.exit(main())
