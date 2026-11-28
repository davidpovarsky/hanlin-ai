#!/usr/bin/env python3
"""Reproduce the 148 portable composer domain assertions.

Usage:
    python Scripts/CI/check_composer_domain.py --output-dir <artifact-directory>

The assertions execute the repository's actual coordinator, organizer dock,
Morph geometry and metrics. Only SwiftUI Binding, Transaction and animation
plumbing use small portable stand-ins. This is not Apple-framework compilation,
native animation, microphone, visual, simulator or physical-device evidence.

Requires Swift 6 with Foundation and Observation. It writes the generated Swift
fixture, executable and result.json (including hashes of all consumed sources).
The recorded 2026-11-22 result predates this path/CLI packaging; the Swift test
fixture and its assertions are unchanged, and it was not rerun for packaging.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repo-root", type=pathlib.Path,
                    default=pathlib.Path(__file__).resolve().parents[2])
parser.add_argument("--output-dir", type=pathlib.Path,
                    default=pathlib.Path(tempfile.gettempdir()) / "hanlin-composer-domain-check")
parser.add_argument("--swiftc", default="swiftc", help="Swift 6 compiler executable")
args = parser.parse_args()
root = args.repo_root.resolve()
out = args.output_dir.resolve()
out.mkdir(parents=True, exist_ok=True)
files = {
 'coordinator': 'AI_HLY/Downstream/ChatInput/HanlinComposerPopupCoordinator.swift',
 'dock': 'AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinOrganizerDockState.swift',
 'geometry': 'Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Composer/HanlinMorphComposer.swift',
 'catalog': 'Packages/HanlinPresentationSDK/Sources/HanlinPresentationKit/HanlinDesignCatalog.swift',
}
contents = {key: (root / name).read_text(encoding='utf-8') for key, name in files.items()}
hashes = {files[key]: hashlib.sha256((root / files[key]).read_bytes()).hexdigest() for key in files}
stub = '''
import Foundation
import Observation
struct Animation { static func easeInOut(duration: Double) -> Animation { Animation() } }
func withAnimation<T>(_ animation: Animation?, _ body: () -> T) -> T { body() }
struct Transaction { var disablesAnimations = false }
@MainActor var transactionWasDisabled = false
@MainActor func withTransaction<T>(_ transaction: Transaction, _ body: () -> T) -> T {
    transactionWasDisabled = transaction.disablesAnimations
    return body()
}
struct Binding<Value> {
    let read: () -> Value
    let write: (Value) -> Void
    init(get: @escaping () -> Value, set: @escaping (Value) -> Void) { read = get; write = set }
    var wrappedValue: Value { get { read() } nonmutating set { write(newValue) } }
}
'''
plain = lambda s: re.sub(r'^import (Foundation|Observation|SwiftUI)\n', '', s, flags=re.M)
geometry = contents['geometry'].split('public enum HanlinMorphGeometry {', 1)[1].split('\n/// Reference shell', 1)[0]
constants = '\n'.join(line for line in contents['catalog'].split('public enum HanlinMorphStyle {', 1)[1].split('\n}')[0].splitlines() if 'CGFloat =' in line)
test = '''
@main
@MainActor
struct ComposerChecks {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        for route in [ComposerGeneralSubroute.search, .thinking, .creative, .miniApps, .prompts] {
            let c = HanlinComposerPopupCoordinator()
            c.open(.general)
            c.pushGeneralSubroute(route, reduceMotion: true)
            c.open(.model)
            expect(c.activePopup == .general, "model displaced drawer")
            expect(c.morphRoute == .general(route), "model reset exact drawer page")
            c.pushModelSubroute()
            expect(c.modelNavigationPath == [.allModels], "model route was delayed")
            expect(c.modelFrameExpanded, "size not expanded with route")
            expect(transactionWasDisabled, "model has a second SwiftUI animation")
            c.pushModelSubroute()
            expect(c.modelNavigationPath.count == 1, "duplicate model route")
            c.popModelSubroute()
            expect(c.modelNavigationPath.isEmpty && !c.modelFrameExpanded, "return was two-stage")
            c.close(.model)
            expect(!c.isModelPresented && c.morphRoute == .general(route), "model close destroyed bubble")
            c.binding(for: .model).wrappedValue = true
            c.binding(for: .model).wrappedValue = false
            expect(c.morphRoute == .general(route), "binding dismiss destroyed bubble")
            c.dockState.handleInputFocusChange(true, preserveExpandedDrawer: true)
            expect(c.dockState.mode == .general, "native editor focus collapsed bubble")
        }
        let c = HanlinComposerPopupCoordinator()
        c.open(.tools)
        c.pushToolsSubroute(.skillsCenter, reduceMotion: true)
        c.open(.tools)
        expect(c.morphRoute == .tools(.skillsCenter), "idempotent open reset current page")
        c.open(.model)
        let old = c.modelPresentationGeneration
        c.close(.model)
        c.open(.model)
        c.pushModelSubroute()
        c.modelFrameResizeDidComplete(presentationID: old, size: c.modelPopoverSize)
        expect(c.isModelAnimatingExpand, "stale resize completed new presentation")
        c.modelFrameResizeDidComplete(presentationID: c.modelPresentationGeneration, size: c.modelPopoverSize)
        expect(!c.isModelAnimatingExpand, "current resize did not complete")
        expect(c.morphRoute == .tools(.skillsCenter), "resize reset tools")
        c.closeAll()
        expect(!c.isModelPresented && c.activePopup == nil && c.dockState.mode == .collapsed, "explicit teardown incomplete")
        let legacy = HanlinOrganizerDockState()
        legacy.openMode(.general)
        legacy.handleInputFocusChange(true)
        expect(legacy.mode == .collapsed, "legacy focus consumer behavior changed")
        for available in [CGFloat(240), 320, 400, 800, 1024] {
            for accessory in [CGFloat(0), 20, 100] {
                for input in [CGFloat(102), 150, 280] {
                    for open in [false, true] {
                        let budget = HanlinMorphGeometry.editorBudget(availableHeight: available, accessoryHeight: accessory,
                            inputHeight: input, editorHeight: input - 64, toolbarHeight: 44, isExpanded: open)
                        let height = HanlinMorphGeometry.expandedEditorHeight(availableHeight: available, editorBudget: budget)
                        expect(height.isFinite && height >= 0 && height <= budget, "expanded editor escaped keyboard budget")
                    }
                }
            }
        }
        expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: .nan, editorBudget: .infinity) == 0, "invalid bounds accepted")
        expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: 400, editorBudget: 169) == 169, "short viewport not respected")
        print("COMPOSER_PORTABLE_DOMAIN_PASS checks=\\(checks)")
    }
}
'''
source = stub + '\npublic enum HanlinMorphStyle {\n' + constants + '\n}\npublic enum HanlinMorphGeometry {' + geometry + '\n' + plain(contents['dock']) + '\n' + plain(contents['coordinator']) + '\n' + test
swift = out / 'ComposerChecks.swift'
swift.write_text(source, encoding='utf-8', newline='\n')
exe = out / ('ComposerChecks.exe' if os.name == 'nt' else 'ComposerChecks')
built = subprocess.run([args.swiftc, '-parse-as-library', '-swift-version', '6', str(swift), '-o', str(exe)], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
record = {'source_hashes': hashes, 'validation': 'Portable domain logic only; SwiftUI transaction/binding stand-ins, no Apple UI/runtime verification', 'compile_returncode': built.returncode, 'compile_output': built.stdout + built.stderr}
if built.returncode == 0:
    run = subprocess.run([str(exe)], capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=20)
    record.update(run_returncode=run.returncode, output=run.stdout+run.stderr)
(out / 'result.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
print(json.dumps(record))
sys.exit(record.get('run_returncode', built.returncode))
