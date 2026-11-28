import CoreFoundation
import Foundation
import XCTest
import XCUIAutomation

/// Genuine system surfaces, selected separately from the original 52 cases.
/// The external observer only reads real installed state/receipts and writes
/// coordination files in this XCTest runner's Documents directory.
@MainActor
final class HanlinEntrypointSystemSurfaceUITests: XCTestCase {
    private enum Engine: String {
        case expo, nativescript
        var title: String { self == .expo ? "Surface Expo" : "Surface NativeScript" }
        var archive: String { self == .expo ? "SurfaceExpo" : "SurfaceNativeScript" }
        var appID: String { "hanlin.surface." + rawValue }
        var actionLabel: String { self == .expo ? "Run Expo Surface" : "Run NativeScript Surface" }
    }
    private enum Surface: String { case widget, liveActivity, shortcuts, share, translation, miniAppShortcut }
    private struct ObservationFailure: Error, CustomStringConvertible {
        let description: String
    }

    private let mini = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    private let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private var deadline = Date.distantPast
    private var exchange: URL?
    private var runDirectory: URL?
    private var record: [String: Any] = [:]

    func testExpoPlacedWidgetInvokesAllFiveRuntimes() throws { try observe(.expo, .widget) }
    func testNativeScriptPlacedWidgetInvokesAllFiveRuntimes() throws { try observe(.nativescript, .widget) }
    func testExpoLiveActivityInvokesAllFiveRuntimes() throws { try observe(.expo, .liveActivity) }
    func testNativeScriptLiveActivityInvokesAllFiveRuntimes() throws { try observe(.nativescript, .liveActivity) }
    func testExpoShortcutInvokesAllFiveRuntimes() throws { try observe(.expo, .shortcuts) }
    func testNativeScriptShortcutInvokesAllFiveRuntimes() throws { try observe(.nativescript, .shortcuts) }
    func testExpoSystemShareInvokesAllFiveRuntimes() throws { try observe(.expo, .share) }
    func testNativeScriptSystemShareInvokesAllFiveRuntimes() throws { try observe(.nativescript, .share) }
    func testExpoSystemTranslationInvokesAllFiveRuntimes() throws { try observe(.expo, .translation) }
    func testNativeScriptSystemTranslationInvokesAllFiveRuntimes() throws { try observe(.nativescript, .translation) }


    func testExpoRunMiniAppActionSavedBackgroundReturnsTypedResult() throws {
        try observe(.expo, .miniAppShortcut, canPresentUI: false)
    }
    func testNativeScriptRunMiniAppActionSavedBackgroundReturnsTypedResult() throws {
        try observe(.nativescript, .miniAppShortcut, canPresentUI: false)
    }
    func testExpoRunMiniAppActionSavedForegroundReturnsTypedResult() throws {
        try observe(.expo, .miniAppShortcut, canPresentUI: true)
    }
    func testNativeScriptRunMiniAppActionSavedForegroundReturnsTypedResult() throws {
        try observe(.nativescript, .miniAppShortcut, canPresentUI: true)
    }


    func testMiniAppsPlacedWidgetRetainsLastGoodAfterRealFailureAndRecovers() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        deadline = Date().addingTimeInterval(420)
        let runID = UUID().uuidString.lowercased()
        let instanceName = "Recovery-" + runID
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "expo", "surface": "widgetRecovery",
                  "fixtureTitle": "Interactive Widget Matrix", "instanceName": instanceName,
                  "expectedFamily": "systemMedium", "status": "RUNNING", "test": name,
                  "startedAt": timestamp(), "phase": "preparing"]
        try checkpoint("preparing")
        defer {
            capture(mini, "widget-final-mini")
            capture(springboard, "widget-final-system")
            record["finishedAt"] = timestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try importMatrixWidgetAndCreateInstance(named: instanceName)
            capture(mini, "widget-created-instance")
            try checkpoint("widget-installed")
            let identity = try response("identity.json", timeout: 25)
            try require(identity["status"] as? String == "READY",
                        "The observer must bind the actual current Matrix program and fresh instance.")
            record["installedIdentity"] = identity
            try placeMatrixWidget(selecting: instanceName)
            let baselineText = springboard.staticTexts["Matrix count: 0"].firstMatch
            let fail = springboard.buttons["Fail refresh"].firstMatch
            let recover = springboard.buttons["Recover"].firstMatch
            try require(baselineText.waitForExistence(timeout: bounded(30)) &&
                        fail.exists && recover.exists && fail.isHittable && recover.isHittable,
                        "The actual placed Matrix must expose its zero-count layout and both authored controls.")
            try require(mini.state == .notRunning, "The widget test must begin with the MiniApps host terminated.")
            record["placedWidgetObserved"] = true
            record["visibleCount"] = 0
            capture(springboard, "widget-before-failure")
            try checkpoint("widget-baseline")
            let baseline = try response("widget-baseline.json", timeout: 30)
            try require(baseline["status"] as? String == "READY",
                        "An actual verified last-good render for this current configuration is required.")
            record["baseline"] = baseline
            try checkpoint("before-widget-failure")
            let armed = try response("widget-armed.json", timeout: 15)
            try require(armed["status"] as? String == "READY", "The real log observation was not armed.")
            try tap(fail, "Tap Fail refresh on the genuine placed WidgetKit widget.")
            record["failActionObserved"] = true
            try checkpoint("widget-failure-requested")
            let failure = try response("widget-failure.json", timeout: 60)
            try require(failure["status"] as? String == "RETAINED_AFTER_REAL_FAILURE",
                        "Unchanged UI alone is insufficient: the actual extension must report a matching failed-render fallback.")
            try require(baselineText.exists && recover.exists && mini.state == .notRunning,
                        "The last-good layout and Recover control must remain visible without opening MiniApps.")
            record["failure"] = failure
            capture(springboard, "widget-after-real-failure")
            let retryAfter = try XCTUnwrap(failure["retryAfter"] as? NSNumber).doubleValue
            try require(retryAfter.isFinite && retryAfter > 0,
                        "The real authored callback did not provide its finite recovery boundary.")
            var hostStarted = false
            let remaining = max(0, retryAfter / 1000 - Date().timeIntervalSince1970) + 2
            try require(wait(min(95, remaining)) {
                if self.mini.state != .notRunning { hostStarted = true }
                return Date().timeIntervalSince1970 * 1000 >= retryAfter + 250
            }, "The authored temporary failure window did not reach its recovery boundary.")
            try require(!hostStarted && mini.state == .notRunning && baselineText.exists,
                        "The host must remain terminated and passive time expiry must not substitute for the observed recovery action.")
            try checkpoint("before-widget-recovery")
            let ready = try response("widget-recovery-ready.json", timeout: 15)
            try require(ready["status"] as? String == "READY",
                        "The same failed state and last-good layout must still precede Recover.")
            try tap(recover, "Tap the original Recover callback on the retained WidgetKit layout.")
            record["recoverActionObserved"] = true
            let recoveredText = springboard.staticTexts["Matrix count: 2"].firstMatch
            try require(recoveredText.waitForExistence(timeout: bounded(40)) && mini.state == .notRunning,
                        "The actual Recover callback must publish and display the new count without launching the host.")
            record["visibleRecoveredCount"] = 2
            capture(springboard, "widget-after-recovery")
            try checkpoint("widget-recovery-requested")
            let completion = try response("completion.json", timeout: 25)
            try require(completion["status"] as? String == "EXECUTED_PASS" &&
                        completion["sameGeneration"] as? Bool == true &&
                        completion["family"] as? String == "systemMedium",
                        "The actual medium-family failure and recovery must retain the exact installation/generation/settings.")
            record["observerCompletion"] = completion
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"
            record["reason"] = String(describing: error)
            throw error
        }
    }

    func testMiniAppsPlacedWidgetToggleKeepsIndependentInstanceState() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        deadline = Date().addingTimeInterval(420)
        let runID = UUID().uuidString.lowercased()
        let names = ["A": "State-A-" + runID, "B": "State-B-" + runID]
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "expo", "surface": "widgetState",
                  "fixtureTitle": "Interactive Widget Matrix", "instanceNames": names,
                  "expectedFamily": "systemMedium", "startedAt": widgetStateTimestamp(), "test": name,
                  "status": "RUNNING", "placed": [String](), "phase": "preparing"]
        try checkpoint("preparing")
        defer {
            capture(springboard, "widget-state-final-system")
            capture(mini, "widget-state-final-host")
            record["finishedAt"] = timestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try importMatrixWidgetAndCreateInstance(named: try XCTUnwrap(names["A"]))
            try createSecondWidgetStateInstance(named: try XCTUnwrap(names["B"]))
            capture(mini, "widget-state-created-both-variants")
            try checkpoint("widget-instances-created")
            let identity = try response("identity.json", timeout: 25)
            try require(identity["status"] as? String == "READY", "Both actual fresh widget variants must be admitted.")
            record["attemptID"] = try string(identity, "attemptID")
            record["sourceSHA"] = try string(identity, "sourceSHA")
            record["installedIdentity"] = identity

            // Only A is placed while both native states are zero. A's actual
            // configuration is read before the first Toggle; counts alone are
            // never used to claim which named variant a placement selected.
            try placeMatrixWidget(selecting: try XCTUnwrap(names["A"]))
            var bindings: [String: Any] = [:]
            bindings["A"] = try confirmWidgetStateConfiguration("A", count: 0, names: names)
            record["configurationBindings"] = bindings
            record["placed"] = ["A"]
            record["ui"] = try widgetStateObservations(["A": 0])
            record["hostTerminated"] = mini.state == .notRunning
            try checkpoint("widget-state-placement")
            let placementA = try response("placement-A.json", timeout: 25)
            try require(placementA["status"] as? String == "READY",
                        "The actual first named placement and zero-state render were not observed.")
            try performWidgetStateAction(1, instance: "A", action: "toggle", desired: true,
                                         before: ["A": 0], after: ["A": 1])

            // Now counts1 and0 are distinct navigation anchors. Reopen BOTH
            // real configuration panels to bind their current physical frames
            // to the fresh named variants after Home Screen reflow.
            try placeMatrixWidget(selecting: try XCTUnwrap(names["B"]))
            bindings["A"] = try confirmWidgetStateConfiguration("A", count: 1, names: names)
            bindings["B"] = try confirmWidgetStateConfiguration("B", count: 0, names: names)
            record["configurationBindings"] = bindings
            record["placed"] = ["A", "B"]
            record["ui"] = try widgetStateObservations(["A": 1, "B": 0])
            record["hostTerminated"] = mini.state == .notRunning
            try checkpoint("widget-state-placement")
            let placementB = try response("placement-B.json", timeout: 25)
            try require(placementB["status"] as? String == "READY",
                        "Both actual named placements must be bound before the remaining controls.")
            try performWidgetStateAction(2, instance: "A", action: "toggle", desired: false,
                                         before: ["A": 1, "B": 0], after: ["A": 2, "B": 0])
            try performWidgetStateAction(3, instance: "A", action: "add", desired: nil,
                                         before: ["A": 2, "B": 0], after: ["A": 3, "B": 0])
            try performWidgetStateAction(4, instance: "B", action: "toggle", desired: true,
                                         before: ["A": 3, "B": 0], after: ["A": 3, "B": 1])
            try performWidgetStateAction(5, instance: "B", action: "toggle", desired: false,
                                         before: ["A": 3, "B": 1], after: ["A": 3, "B": 2])
            try performWidgetStateAction(6, instance: "B", action: "refresh", desired: nil,
                                         before: ["A": 3, "B": 2], after: ["A": 3, "B": 2])

            bindings["A"] = try confirmWidgetStateConfiguration("A", count: 3, names: names)
            bindings["B"] = try confirmWidgetStateConfiguration("B", count: 2, names: names)
            record["configurationBindings"] = bindings
            record["ui"] = try widgetStateObservations(["A": 3, "B": 2])
            record["hostTerminated"] = mini.state == .notRunning
            try checkpoint("widget-state-complete")
            let completion = try response("completion.json", timeout: 30)
            try require(completion["status"] as? String == "EXECUTED_PASS"
                        && completion["attemptID"] as? String == record["attemptID"] as? String
                        && completion["sourceSHA"] as? String == record["sourceSHA"] as? String,
                        "Final evidence must retain both exact current named variants and all six original actions.")
            _ = try widgetStateObservations(["A": 3, "B": 2])
            try require(mini.state == .notRunning, "The actual widget controls must leave the MiniApps host terminated.")
            record["observerCompletion"] = completion
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"
            record["reason"] = String(describing: error)
            throw error
        }
    }

    // Additive English/medium VoiceOver pilot. Only A is physically placed;
    // B remains an independently named, unchanged native-state control.
    func testMiniAppsPlacedWidgetToggleVoiceOverAnnouncesAndSetsBothValues() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        deadline = Date().addingTimeInterval(420)
        guard #available(iOS 27.0, *) else {
            throw ObservationFailure(description: "The actual iOS 27 public VoiceOver service is required.")
        }
        let service = XCUIDevice.shared.voiceOverService
        let priorEnabled = service.isEnabled
        let runID = UUID().uuidString.lowercased()
        let names = ["A": "VoiceOver-A-" + runID, "B": "VoiceOver-B-" + runID]
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "expo", "surface": "widgetVoiceOver",
                  "fixtureTitle": "Interactive Widget Matrix", "instanceNames": names,
                  "expectedFamily": "systemMedium", "requestedSpeechLocale": "en_US",
                  "priorVoiceOverEnabled": priorEnabled, "voiceOverEvents": [[String: Any]](),
                  "startedAt": widgetStateTimestamp(), "test": name, "status": "RUNNING",
                  "placed": [String](), "phase": "preparing"]
        defer {
            capture(springboard, "widget-voiceover-final-system")
            capture(mini, "widget-voiceover-final-host")
            record["finishedAt"] = widgetStateTimestamp()
            try? retainWidgetVoiceOverJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            try checkpoint("preparing")
            try setWidgetVoiceOver(false, reason: "setup")
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try importMatrixWidgetAndCreateInstance(named: try XCTUnwrap(names["A"]))
            try createSecondWidgetStateInstance(named: try XCTUnwrap(names["B"]))
            capture(mini, "widget-voiceover-created-both-variants")
            try checkpoint("widget-voiceover-instances-created")
            let identity = try response("identity.json", timeout: 25)
            try require(identity["status"] as? String == "READY", "Both actual fresh named variants must be admitted.")
            record["attemptID"] = try string(identity, "attemptID")
            record["sourceSHA"] = try string(identity, "sourceSHA")
            record["installedIdentity"] = identity

            try placeMatrixWidget(selecting: try XCTUnwrap(names["A"]))
            record["configurationBindings"] = ["A": try confirmWidgetStateConfiguration("A", count: 0, names: names)]
            record["placed"] = ["A"]
            record["ui"] = try widgetStateObservations(["A": 0])
            record["hostTerminated"] = mini.state == .notRunning
            try checkpoint("widget-voiceover-placement")
            let placement = try response("placement-A.json", timeout: 25)
            try require(placement["status"] as? String == "READY", "The actual named A placement was not bound.")

            try setWidgetVoiceOver(true, reason: "exercise")
            try performWidgetVoiceOverToggle(1, desired: true)
            try performWidgetVoiceOverToggle(2, desired: false)

            // Read the same physical selection through the existing ordinary
            // configuration UI, then restore the actual prior service state.
            try setWidgetVoiceOver(false, reason: "final-configuration")
            record["configurationBindings"] = ["A": try confirmWidgetStateConfiguration("A", count: 2, names: names)]
            record["ui"] = try widgetStateObservations(["A": 2])
            record["hostTerminated"] = mini.state == .notRunning
            try restoreWidgetVoiceOver(priorEnabled)
            try checkpoint("widget-voiceover-complete")
            let completion = try response("completion.json", timeout: 30)
            try require(completion["status"] as? String == "EXECUTED_PASS"
                        && completion["attemptID"] as? String == record["attemptID"] as? String
                        && completion["sourceSHA"] as? String == record["sourceSHA"] as? String,
                        "Both real spoken states, gestures, native transitions and prior-state restoration are required.")
            try require(service.isEnabled == priorEnabled && mini.state == .notRunning,
                        "The final public service state or terminated host changed before completion.")
            record["observerCompletion"] = completion
            record["status"] = "EXECUTED_PASS"
        } catch {
            let originalError = error
            record["status"] = "FAILED"
            record["reason"] = String(describing: originalError)
            do {
                try restoreWidgetVoiceOver(priorEnabled)
            } catch {
                record["restorationFailure"] = String(describing: error)
                throw ObservationFailure(description: "Original failure: \(originalError); VoiceOver restoration failure: \(error)")
            }
            throw originalError
        }
    }

    private func retainWidgetVoiceOverJSON(_ value: [String: Any], filename: String) throws {
        try writeJSON(value, filename: filename)
        let attachment = XCTAttachment(string: try jsonString(value))
        attachment.name = filename
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @available(iOS 27.0, *)
    private func setWidgetVoiceOver(_ enabled: Bool, reason: String) throws {
        let service = XCUIDevice.shared.voiceOverService
        let before = service.isEnabled
        let startedAt = widgetStateTimestamp()
        let startedUptime = ProcessInfo.processInfo.systemUptime
        var operationError: Error?
        do {
            if before != enabled {
                if enabled { try service.enable() } else { try service.disable() }
            }
        } catch { operationError = error }
        let after = service.isEnabled
        var event: [String: Any] = ["reason": reason, "requestedEnabled": enabled,
            "beforeEnabled": before, "afterEnabled": after,
            "operation": before == enabled ? "unchanged" : (enabled ? "enable" : "disable"),
            "startedAt": startedAt, "finishedAt": widgetStateTimestamp(),
            "startedUptime": startedUptime, "finishedUptime": ProcessInfo.processInfo.systemUptime,
            "status": operationError == nil && after == enabled ? "OK" : "FAILED"]
        if let operationError { event["error"] = String(describing: operationError) }
        var events = record["voiceOverEvents"] as? [[String: Any]] ?? []
        events.append(event)
        record["voiceOverEvents"] = events
        try retainWidgetVoiceOverJSON(["schema": 1, "runID": try string(record, "runID"), "events": events],
                                      filename: "voiceover-service-events.json")
        if let operationError { throw operationError }
        try require(after == enabled, "The actual VoiceOver service did not reach the requested state.")
    }

    @available(iOS 27.0, *)
    private func restoreWidgetVoiceOver(_ prior: Bool) throws {
        try setWidgetVoiceOver(prior, reason: "restore-prior")
        let current = XCUIDevice.shared.voiceOverService.isEnabled
        try require(current == prior, "The actual prior VoiceOver state was not restored.")
        record["voiceOverRestoration"] = ["priorEnabled": prior, "afterEnabled": current,
            "restoredAt": widgetStateTimestamp(), "restoredUptime": ProcessInfo.processInfo.systemUptime]
    }

    private func widgetVoiceOverSpokenValue(_ utterance: String) -> Bool? {
        let words = utterance.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let labelCount = zip(words, words.dropFirst()).filter { $0.0 == "widget" && $0.1 == "notifications" }.count
        guard labelCount == 1, words.contains("on") != words.contains("off") else { return nil }
        return words.contains("on")
    }

    private func uniqueWidgetVoiceOverControls(count: Int) throws -> WidgetStateControls {
        let controls = try widgetStateControls(count: count)
        let matches = springboard.switches.matching(NSPredicate(format: "label == %@", "Widget notifications"))
            .allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        try require(matches.count == 1 && matches[0].frame == controls.toggle.frame
                    && controls.toggle.label == "Widget notifications" && controls.toggle.isEnabled,
                    "The spoken label must belong to one current physical native switch, with no competing visible match.")
        return controls
    }

    @available(iOS 27.0, *)
    private func widgetVoiceOverSpeech(_ phase: String, count: Int, expected: Bool, until end: Date) throws -> [String: Any] {
        let service = XCUIDevice.shared.voiceOverService
        let controls = try uniqueWidgetVoiceOverControls(count: count)
        var trace: [[String: Any]] = []
        let startedAt = widgetStateTimestamp()
        let startedUptime = ProcessInfo.processInfo.systemUptime
        do {
            for index in 0..<128 {
                try require(Date() < end && Date() < deadline, "Actual VoiceOver traversal exceeded the existing phase deadline.")
                try require(service.isEnabled && mini.state == .notRunning,
                            "VoiceOver or host state changed during actual public speech observation.")
                let output: XCUIVoiceOverService.Output
                if index == 0 { output = try service.currentSpeech() }
                else { output = try service.moveForward() }
                let row: [String: Any] = ["index": index, "operation": index == 0 ? "currentSpeech" : "moveForward",
                    "utterance": output.utterance, "at": widgetStateTimestamp(),
                    "uptime": ProcessInfo.processInfo.systemUptime,
                    "serviceEnabled": service.isEnabled, "hostTerminated": mini.state == .notRunning]
                trace.append(row)
                record["lastVoiceOverTrace"] = ["phase": phase, "trace": trace]
                try require(output.utterance.count <= 4096 && service.isEnabled && mini.state == .notRunning,
                            "The actual speech observation is unbounded or its service/host changed.")
                if widgetVoiceOverSpokenValue(output.utterance) == expected {
                    let current = try uniqueWidgetVoiceOverControls(count: count)
                    try require(current.container.frame == controls.container.frame
                                && current.toggle.frame == controls.toggle.frame
                                && current.toggle.value as? String == (expected ? "1" : "0"),
                                "The actual spoken value must agree with this same physical switch.")
                    let value: [String: Any] = ["schema": 1, "runID": try string(record, "runID"),
                        "attemptID": try string(record, "attemptID"), "sourceSHA": try string(record, "sourceSHA"),
                        "phase": phase, "startedAt": startedAt, "startedUptime": startedUptime,
                        "label": current.toggle.label, "visibleMatchingSwitchCount": 1,
                        "ui": try widgetStateObservations(["A": count]), "trace": trace,
                        "focusAssociation": "Inferred from public current speech and the unique named physical switch"]
                    try retainWidgetVoiceOverJSON(value, filename: "voiceover-" + phase + ".json")
                    return value
                }
            }
            throw ObservationFailure(description: "The bounded public VoiceOver traversal did not speak the unique switch and required English value.")
        } catch {
            try? retainWidgetVoiceOverJSON(["schema": 1, "runID": try string(record, "runID"),
                "phase": phase, "trace": trace, "error": String(describing: error)], filename: "voiceover-" + phase + "-failure.json")
            throw error
        }
    }

    @available(iOS 27.0, *)
    private func performWidgetVoiceOverToggle(_ index: Int, desired: Bool) throws {
        let service = XCUIDevice.shared.voiceOverService
        let actionID = UUID().uuidString.lowercased()
        let beforeCount = index - 1
        let step: [String: Any] = ["index": index, "actionID": actionID, "instance": "A",
                                  "action": "toggle", "desiredValue": desired]
        let before = try widgetVoiceOverSpeech("before-" + String(index), count: beforeCount,
                                              expected: !desired, until: Date().addingTimeInterval(bounded(20)))
        record["step"] = step
        record["voiceOverBefore"] = before
        record["ui"] = try widgetStateObservations(["A": beforeCount])
        record["hostTerminated"] = mini.state == .notRunning
        try checkpoint("widget-voiceover-arm")
        let armed = try response("armed-" + String(index) + ".json", timeout: 20)
        let armedStep = try XCTUnwrap(armed["step"] as? [String: Any])
        try require(armed["status"] as? String == "READY" && armedStep["actionID"] as? String == actionID,
                    "The actual gesture must be armed against the current two native variants.")
        let controls = try uniqueWidgetVoiceOverControls(count: beforeCount)
        let currentSpeech = try service.currentSpeech()
        let speechAt = widgetStateTimestamp()
        let speechUptime = ProcessInfo.processInfo.systemUptime
        try require(service.isEnabled && mini.state == .notRunning
                    && widgetVoiceOverSpokenValue(currentSpeech.utterance) == !desired
                    && controls.toggle.value as? String == (desired ? "0" : "1"),
                    "The actual currently spoken switch and intended value changed before the double tap.")
        let actionEnd = Date().addingTimeInterval(bounded(35))
        var gesture: [String: Any] = ["schema": 1, "runID": try string(record, "runID"),
            "attemptID": try string(record, "attemptID"), "sourceSHA": try string(record, "sourceSHA"),
            "index": index, "actionID": actionID, "method": "XCUIElement.doubleTap",
            "label": controls.toggle.label, "visibleMatchingSwitchCount": 1,
            "beforeUI": try widgetStateObservations(["A": beforeCount]),
            "currentSpeech": ["utterance": currentSpeech.utterance, "at": speechAt, "uptime": speechUptime],
            "serviceEnabledBefore": service.isEnabled, "hostTerminatedBefore": mini.state == .notRunning,
            "startedAt": widgetStateTimestamp(), "startedUptime": ProcessInfo.processInfo.systemUptime]
        controls.toggle.doubleTap()
        gesture["finishedAt"] = widgetStateTimestamp()
        gesture["finishedUptime"] = ProcessInfo.processInfo.systemUptime
        gesture["serviceEnabledAfter"] = service.isEnabled
        gesture["hostTerminatedAfter"] = mini.state == .notRunning
        try retainWidgetVoiceOverJSON(gesture, filename: "voiceover-gesture-" + String(index) + ".json")
        var hostStarted = mini.state != .notRunning
        var serviceStopped = !service.isEnabled
        try require(wait(max(0, actionEnd.timeIntervalSinceNow)) {
            if self.mini.state != .notRunning { hostStarted = true }
            if !service.isEnabled { serviceStopped = true }
            return self.springboard.staticTexts["Matrix count: " + String(index)].firstMatch.exists
        }, "The actual VoiceOver gesture did not reach its expected visible native count.")
        try require(!hostStarted && !serviceStopped && mini.state == .notRunning && service.isEnabled,
                    "The host or VoiceOver service changed during the actual gesture/readback.")
        let after = try widgetVoiceOverSpeech("after-" + String(index), count: index,
                                             expected: desired, until: actionEnd)
        record["voiceOverGesture"] = gesture
        record["voiceOverAfter"] = after
        record["ui"] = try widgetStateObservations(["A": index])
        record["hostTerminated"] = mini.state == .notRunning
        capture(springboard, "widget-voiceover-step-" + String(index))
        try checkpoint("widget-voiceover-applied")
        let applied = try response("applied-" + String(index) + ".json", timeout: 35)
        let appliedStep = try XCTUnwrap(applied["step"] as? [String: Any])
        try require(applied["status"] as? String == "APPLIED" && appliedStep["actionID"] as? String == actionID,
                    "Actual speech and one fresh native nonce/revision must agree while B remains unchanged.")
    }


    func testMiniAppsMediumWidgetNativeControlsStayVisibleAcrossStateAndRotation() throws {
        let family = "systemMedium"
        let sizeLabel = "Medium"
        continueAfterFailure = false
        executionTimeAllowance = 420
        deadline = Date().addingTimeInterval(420)
        let orientationPreparation = try prepareWidgetFamilyInitialOrientation()
        let prior = XCUIDevice.shared.orientation
        let priorName = widgetFamilyOrientationName()
        let runID = UUID().uuidString.lowercased()
        let instanceName = "Layout-" + family + "-" + runID
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root; runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "expo", "surface": "widgetLayout",
                  "fixtureTitle": "Interactive Widget Matrix", "instanceName": instanceName,
                  "expectedFamily": family, "sizeLabel": sizeLabel, "priorOrientation": priorName,
                  "status": "RUNNING", "test": name, "startedAt": widgetStateTimestamp()]
        if let orientationPreparation { record["orientationPreparation"] = orientationPreparation }
        var boundPlacement = false
        var removed = false
        var restored = false
        defer {
            // Only a configuration already read as this exact fresh name may
            // be removed. An unbound placement is retained as a failed case.
            if boundPlacement && !removed {
                do { record["cleanup"] = try removeWidgetLayout(named: instanceName); removed = true }
                catch { record["cleanupFailure"] = String(describing: error) }
            }
            if !restored {
                XCUIDevice.shared.orientation = prior
                if wait(25, until: { self.widgetFamilyOrientationName() == priorName && self.widgetFamilyScreenMatches(priorName) }) {
                    record["orientationRestoration"] = widgetFamilyRestoration(priorName)
                } else {
                    record["restorationFailure"] = "The initial orientation was assigned but not effectively observed."
                }
            }
            capture(mini, "widget-layout-final-mini")
            capture(springboard, "widget-layout-final-system")
            record["finishedAt"] = widgetStateTimestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            try require(priorName != "unknown", "A real initial screen orientation is required before changing it.")
            try checkpoint("preparing")
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try importMatrixWidgetAndCreateInstance(named: instanceName)
            capture(mini, "widget-layout-instance-created")
            try checkpoint("widget-layout-instance-created")
            let identity = try response("identity.json", timeout: 25)
            try require(identity["status"] as? String == "READY", "The actual new family instance was not admitted.")
            record["attemptID"] = try string(identity, "attemptID")
            record["sourceSHA"] = try string(identity, "sourceSHA")
            record["installedIdentity"] = identity

            XCUIDevice.shared.press(.home)
            try setWidgetFamilyOrientation("portrait")
            try openWidgetFamilyGallery(sizeLabel: sizeLabel)
            try checkpoint("widget-layout-arm-placement")
            let armed = try response("placement-armed.json", timeout: 25)
            try require(armed["status"] as? String == "READY", "The named placement was not armed before the real Add Widget action.")
            record["placementArm"] = armed
            let add = try widgetFamilyUnique(springboard.buttons.matching(
                NSPredicate(format: "label MATCHES %@", "\\s*Add Widget\\s*")), "The selected gallery has no unique Add Widget action.")
            try tap(add, "Place the actually observed family page.")
            record["addWidgetTappedAt"] = widgetStateTimestamp()
            record["unboundPlacementCreated"] = true
            if springboard.buttons["Done"].firstMatch.exists { try tap(springboard.buttons["Done"].firstMatch, "Finish the actual Home Screen placement.") }
            let placeholders = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choose a widget instance"))
            try require(wait(25) { self.widgetFamilyVisible(placeholders).count == 1 },
                        "The newly added, previously absent configuration placeholder is missing or ambiguous.")
            let placeholder = try XCTUnwrap(widgetFamilyVisible(placeholders).first)
            record["placeholderFrame"] = widgetStateFrame(placeholder.frame)
            capture(springboard, "widget-layout-new-placeholder")
            placeholder.press(forDuration: 1.5)
            try tap(springboard.buttons["Edit Widget"].firstMatch, "Configure this new physical widget.")
            let choose = try widgetFamilyUnique(springboard.descendants(matching: .any).matching(
                NSPredicate(format: "label == 'Choose' OR label == 'Widget instance'")), "The actual instance configuration control is unavailable.")
            try tap(choose, "Open the original installed-instance query.")
            let entity = try widgetFamilyUnique(springboard.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", instanceName)), "The fresh named instance is not offered by the actual query.")
            try tap(entity, "Select this case's exact named variant.")
            XCUIDevice.shared.press(.home)
            mini.terminate()
            try require(mini.state == .notRunning, "The host must be terminated before observing the placed family.")

            let initialAt = widgetStateTimestamp()
            let initialUptime = ProcessInfo.processInfo.systemUptime
            let initialBinding = try confirmWidgetLayout(named: instanceName, count: 0,
                                                        label: "widget-layout-configuration-0")
            boundPlacement = true
            record["unboundPlacementCreated"] = false
            var observations = [try captureWidgetLayout(index: 0, count: 0, orientation: "portrait",
                requestedAt: initialAt, requestedUptime: initialUptime, configuration: initialBinding)]
            record["observations"] = observations
            record["hostTerminated"] = mini.state == .notRunning
            try checkpoint("widget-layout-placed")
            let placement = try response("observation-0.json", timeout: 35)
            try require(placement["status"] as? String == "READY", "The actual Medium placement and initial control layout were not admitted.")

            var count = 0
            var completedActionIDs: [String] = []
            for (offset, action) in ["toggle", "add", "refresh"].enumerated() {
                let index = offset + 1
                let actionID = UUID().uuidString.lowercased()
                let step: [String: Any] = ["index": index, "actionID": actionID, "action": action,
                                           "desiredValue": action == "toggle" ? true as Any : NSNull()]
                record["step"] = step
                record["armConfiguration"] = try confirmWidgetLayout(named: instanceName, count: count,
                    label: "widget-layout-arm-configuration-" + String(index))
                record["armUI"] = try widgetLayoutObservation(count: count)
                try checkpoint("widget-layout-arm-action")
                let arm = try response("armed-" + String(index) + ".json", timeout: 25)
                try require(arm["status"] as? String == "READY", "The actual control action was not armed against current native state.")
                let elements = try widgetLayoutElements(count: count)
                var tapObservation: [String: Any] = ["actionID": actionID, "beganAt": widgetStateTimestamp(),
                    "beganUptime": ProcessInfo.processInfo.systemUptime]
                if action == "toggle" {
                    try require(elements.controls.toggle.value as? String == "0", "The original real Toggle must start false.")
                    try tap(elements.controls.toggle, "Set the real native Widget notifications Toggle to true.")
                } else if action == "add" {
                    try tap(elements.controls.add, "Invoke the original native Add action.")
                } else {
                    try tap(elements.controls.refresh, "Invoke the original native Refresh action.")
                }
                tapObservation["returnedAt"] = widgetStateTimestamp()
                tapObservation["returnedUptime"] = ProcessInfo.processInfo.systemUptime
                record["tap"] = tapObservation
                // The unchanged Matrix increments count for Toggle and Add.
                // Refresh preserves values but must commit its own native nonce.
                if action != "refresh" { count += 1 }
                let requestedAt = widgetStateTimestamp()
                let requestedUptime = ProcessInfo.processInfo.systemUptime
                let configuration = try confirmWidgetLayout(named: instanceName, count: count,
                    label: "widget-layout-configuration-" + String(index))
                observations.append(try captureWidgetLayout(index: index, count: count, orientation: "portrait",
                    requestedAt: requestedAt, requestedUptime: requestedUptime, configuration: configuration))
                record["observations"] = observations
                record["hostTerminated"] = mini.state == .notRunning
                try checkpoint("widget-layout-applied")
                let applied = try response("observation-" + String(index) + ".json", timeout: 35)
                try require(applied["status"] as? String == "READY", "The actual control bounds/native revision/nonce did not qualify.")
                completedActionIDs.append(actionID)
                record["completedActionIDs"] = completedActionIDs
            }

            for (offset, orientation) in ["landscapeLeft", "portrait"].enumerated() {
                let index = offset + 4
                let requestedAt = widgetStateTimestamp()
                let requestedUptime = ProcessInfo.processInfo.systemUptime
                try setWidgetFamilyOrientation(orientation)
                let configuration = try confirmWidgetLayout(named: instanceName, count: count,
                    label: "widget-layout-configuration-" + String(index))
                observations.append(try captureWidgetLayout(index: index, count: count, orientation: orientation,
                    requestedAt: requestedAt, requestedUptime: requestedUptime, configuration: configuration))
                record["observations"] = observations
                record["hostTerminated"] = mini.state == .notRunning
                try checkpoint("widget-layout-rotated")
                let rotated = try response("observation-" + String(index) + ".json", timeout: 35)
                try require(rotated["status"] as? String == "READY", "Actual rotated control/PNG geometry did not qualify.")
            }
            record["cleanup"] = try removeWidgetLayout(named: instanceName)
            removed = true
            XCUIDevice.shared.orientation = prior
            try require(wait(25) { self.widgetFamilyOrientationName() == priorName && self.widgetFamilyScreenMatches(priorName) },
                        "The actual initial device orientation was not restored.")
            record["orientationRestoration"] = widgetFamilyRestoration(priorName)
            capture(springboard, "widget-layout-restored")
            restored = true
            try checkpoint("widget-layout-complete")
            let completion = try response("completion.json", timeout: 30)
            try require(completion["status"] as? String == "EXECUTED_PASS", "Final native/source/container/cleanup qualification did not pass.")
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"; record["error"] = String(describing: error)
            throw error
        }
    }

    private func widgetLayoutElements(count: Int) throws
        -> (controls: WidgetStateControls, marker: XCUIElement, window: XCUIElement) {
        let label = "Matrix count: " + String(count)
        let query = springboard.staticTexts.matching(NSPredicate(format: "label == %@", label))
        try require(wait(25) { self.widgetFamilyMarkerCount() == 1 && self.widgetFamilyVisible(query).count == 1 },
                    "A second or stale Matrix could alias this actual layout; require one visible marker.")
        let controls = try widgetStateControls(count: count)
        let marker = try XCTUnwrap(widgetFamilyVisible(query).first)
        let windows = springboard.windows.containing(.staticText, identifier: label).allElementsBoundByIndex.filter {
            $0.exists && $0.isHittable && $0.frame.width > 0 && $0.frame.height > 0
                && springboard.frame.contains($0.frame) && $0.frame.contains(controls.container.frame)
        }
        try require(windows.count == 1, "The real AX hierarchy must bind this widget to one visible SpringBoard window.")
        let window = try XCTUnwrap(windows.first)
        try require(controls.container.frame != springboard.frame && controls.container.frame.contains(marker.frame)
                    && mini.state == .notRunning, "The actual widget/container/host association is invalid.")
        return (controls, marker, window)
    }

    private func widgetLayoutControl(_ element: XCUIElement, kind: String) -> [String: Any] {
        ["kind": kind, "label": element.label, "value": element.value as? String ?? "",
         "exists": element.exists, "hittable": element.isHittable, "enabled": element.isEnabled,
         "frame": widgetStateFrame(element.frame)]
    }

    private func widgetLayoutObservation(count: Int) throws -> [String: Any] {
        let elements = try widgetLayoutElements(count: count)
        return ["visibleMatrixCount": widgetFamilyMarkerCount(), "hostTerminated": mini.state == .notRunning,
                "orientation": widgetFamilyOrientationName(), "screenFrame": widgetStateFrame(springboard.frame),
                "widgetFrame": widgetStateFrame(elements.controls.container.frame),
                "window": ["owner": "com.apple.springboard", "kind": "window", "matchingWindowCount": 1,
                           "identifier": elements.window.identifier, "exists": elements.window.exists,
                           "hittable": elements.window.isHittable, "frame": widgetStateFrame(elements.window.frame)],
                "controls": ["count": widgetLayoutControl(elements.marker, kind: "staticText"),
                             "toggle": widgetLayoutControl(elements.controls.toggle, kind: "switch"),
                             "add": widgetLayoutControl(elements.controls.add, kind: "button"),
                             "refresh": widgetLayoutControl(elements.controls.refresh, kind: "button")]]
    }

    private func confirmWidgetLayout(named name: String, count: Int, label: String) throws -> [String: Any] {
        let before = try widgetLayoutElements(count: count)
        let frame = before.controls.container.frame
        let windowFrame = before.window.frame
        before.controls.container.press(forDuration: 1.5)
        try tap(springboard.buttons["Edit Widget"].firstMatch, "Read this layout's exact saved named configuration.")
        let selected = try widgetFamilyUnique(springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", name, name)),
            "The actual configuration does not expose this fresh named layout instance.")
        let selectedLabel = selected.label; let value = selected.value as? String ?? ""
        try require(selectedLabel.contains(name) || value.contains(name), "A different instance cannot qualify this layout.")
        capture(springboard, label)
        XCUIDevice.shared.press(.home)
        let after = try widgetLayoutElements(count: count)
        try require(after.controls.container.frame == frame && after.window.frame == windowFrame
                    && mini.state == .notRunning, "Reading configuration changed the physical association or opened MiniApps.")
        return ["instanceName": name, "label": selectedLabel, "value": value,
                "frame": widgetStateFrame(frame), "verifiedAt": widgetStateTimestamp(),
                "verifiedUptime": ProcessInfo.processInfo.systemUptime, "attachmentLabel": label]
    }

    private func captureWidgetLayout(index: Int, count: Int, orientation: String,
                                     requestedAt: String, requestedUptime: TimeInterval,
                                     configuration: [String: Any]) throws -> [String: Any] {
        var row = try widgetLayoutObservation(count: count)
        row["index"] = index; row["requestedOrientation"] = orientation
        row["requestedAt"] = requestedAt; row["requestedUptime"] = requestedUptime
        row["configuration"] = configuration
        let label = "widget-layout-observation-" + String(index)
        row["attachmentLabel"] = label
        capture(springboard, label)
        row["capturedAt"] = widgetStateTimestamp()
        row["capturedUptime"] = ProcessInfo.processInfo.systemUptime
        return row
    }

    private func removeWidgetLayout(named name: String) throws -> [String: Any] {
        let markers = widgetFamilyVisible(springboard.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Matrix count: ")))
        try require(markers.count == 1, "Cleanup must not choose between multiple physical Matrix widgets.")
        let marker = try XCTUnwrap(markers.first)
        let count = try XCTUnwrap(Int(marker.label.dropFirst("Matrix count: ".count)),
                                 "The actual unique Matrix count is not a nonnegative integer.")
        try require(count >= 0, "A malformed count cannot identify the owned widget for removal.")
        let binding = try confirmWidgetLayout(named: name, count: count, label: "widget-family-cleanup-configuration")
        let elements = try widgetLayoutElements(count: count)
        elements.controls.container.press(forDuration: 1.5)
        try tap(springboard.buttons["Remove Widget"].firstMatch, "Remove only this freshly verified named layout widget.")
        let confirmation = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Remove' OR label == 'Remove Widget'"))
        let confirm = try widgetFamilyUnique(confirmation, "The actual widget-removal confirmation is unavailable.")
        let confirmationLabel = confirm.label
        capture(springboard, "widget-family-remove-confirmation")
        try tap(confirm, "Confirm the real owned-widget removal.")
        try require(wait(25) { self.widgetFamilyMarkerCount() == 0 }, "The owned layout widget remains visible after removal.")
        try require(mini.state == .notRunning, "Removing the widget unexpectedly opened MiniApps.")
        capture(springboard, "widget-family-removed")
        return ["instanceName": name, "configuration": binding, "action": "Remove Widget",
                "confirmationLabel": confirmationLabel, "visibleMatrixCountAfter": widgetFamilyMarkerCount(),
                "hostTerminated": mini.state == .notRunning, "removedAt": widgetStateTimestamp(),
                "removedUptime": ProcessInfo.processInfo.systemUptime]
    }


    func testMiniAppsSmallWidgetRetainsFamilyAndInstanceAcrossRotation() throws {
        try observeWidgetFamily("systemSmall", sizeLabel: "Small")
    }
    func testMiniAppsMediumWidgetRetainsFamilyAndInstanceAcrossRotation() throws {
        try observeWidgetFamily("systemMedium", sizeLabel: "Medium")
    }
    func testMiniAppsLargeWidgetRetainsFamilyAndInstanceAcrossRotation() throws {
        try observeWidgetFamily("systemLarge", sizeLabel: "Large")
    }
    func testMiniAppsExtraLargeWidgetRetainsFamilyAndInstanceAcrossRotation() throws {
        try observeWidgetFamily("systemExtraLarge", sizeLabel: "Extra Large")
    }

    private func observeWidgetFamily(_ family: String, sizeLabel: String) throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        deadline = Date().addingTimeInterval(420)
        let orientationPreparation = try prepareWidgetFamilyInitialOrientation()
        let prior = XCUIDevice.shared.orientation
        let priorName = widgetFamilyOrientationName()
        let runID = UUID().uuidString.lowercased()
        let instanceName = "Family-" + family + "-" + runID
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root; runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "expo", "surface": "widgetFamilies",
                  "fixtureTitle": "Interactive Widget Matrix", "instanceName": instanceName,
                  "expectedFamily": family, "sizeLabel": sizeLabel, "priorOrientation": priorName,
                  "status": "RUNNING", "test": name, "startedAt": widgetStateTimestamp()]
        if let orientationPreparation { record["orientationPreparation"] = orientationPreparation }
        var boundPlacement = false
        var removed = false
        var restored = false
        defer {
            // Only a configuration already read as this exact fresh name may
            // be removed. An unbound placement is retained as a failed case.
            if boundPlacement && !removed {
                do { record["cleanup"] = try removeWidgetFamily(named: instanceName); removed = true }
                catch { record["cleanupFailure"] = String(describing: error) }
            }
            if !restored {
                XCUIDevice.shared.orientation = prior
                if wait(25, until: { self.widgetFamilyOrientationName() == priorName && self.widgetFamilyScreenMatches(priorName) }) {
                    record["orientationRestoration"] = widgetFamilyRestoration(priorName)
                } else {
                    record["restorationFailure"] = "The initial orientation was assigned but not effectively observed."
                }
            }
            capture(mini, "widget-family-final-mini")
            capture(springboard, "widget-family-final-system")
            record["finishedAt"] = widgetStateTimestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            try require(priorName != "unknown", "A real initial screen orientation is required before changing it.")
            try checkpoint("preparing")
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try importMatrixWidgetAndCreateInstance(named: instanceName)
            capture(mini, "widget-family-instance-created")
            try checkpoint("widget-family-instance-created")
            let identity = try response("identity.json", timeout: 25)
            try require(identity["status"] as? String == "READY", "The actual new family instance was not admitted.")
            record["attemptID"] = try string(identity, "attemptID")
            record["sourceSHA"] = try string(identity, "sourceSHA")
            record["installedIdentity"] = identity

            XCUIDevice.shared.press(.home)
            try setWidgetFamilyOrientation("portrait")
            try openWidgetFamilyGallery(sizeLabel: sizeLabel)
            try checkpoint("widget-family-arm")
            let armed = try response("placement-armed.json", timeout: 25)
            try require(armed["status"] as? String == "READY", "The named placement was not armed before the real Add Widget action.")
            record["placementArm"] = armed
            let add = try widgetFamilyUnique(springboard.buttons.matching(
                NSPredicate(format: "label MATCHES %@", "\\s*Add Widget\\s*")), "The selected gallery has no unique Add Widget action.")
            try tap(add, "Place the actually observed family page.")
            record["addWidgetTappedAt"] = widgetStateTimestamp()
            record["unboundPlacementCreated"] = true
            if springboard.buttons["Done"].firstMatch.exists { try tap(springboard.buttons["Done"].firstMatch, "Finish the actual Home Screen placement.") }
            let placeholders = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choose a widget instance"))
            try require(wait(25) { self.widgetFamilyVisible(placeholders).count == 1 },
                        "The newly added, previously absent configuration placeholder is missing or ambiguous.")
            let placeholder = try XCTUnwrap(widgetFamilyVisible(placeholders).first)
            record["placeholderFrame"] = widgetStateFrame(placeholder.frame)
            capture(springboard, "widget-family-new-placeholder")
            placeholder.press(forDuration: 1.5)
            try tap(springboard.buttons["Edit Widget"].firstMatch, "Configure this new physical widget.")
            let choose = try widgetFamilyUnique(springboard.descendants(matching: .any).matching(
                NSPredicate(format: "label == 'Choose' OR label == 'Widget instance'")), "The actual instance configuration control is unavailable.")
            try tap(choose, "Open the original installed-instance query.")
            let entity = try widgetFamilyUnique(springboard.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", instanceName)), "The fresh named instance is not offered by the actual query.")
            try tap(entity, "Select this case's exact named variant.")
            XCUIDevice.shared.press(.home)
            mini.terminate()
            try require(mini.state == .notRunning, "The host must be terminated before observing the placed family.")

            var rotations: [[String: Any]] = []
            for (index, orientation) in ["portrait", "landscapeLeft", "portrait"].enumerated() {
                let requestedAt = widgetStateTimestamp()
                let requestedUptime = ProcessInfo.processInfo.systemUptime
                try setWidgetFamilyOrientation(orientation)
                let configuration = try confirmWidgetFamily(named: instanceName, label: "widget-family-configuration-" + String(index))
                boundPlacement = true
                record["unboundPlacementCreated"] = false
                var row = try widgetFamilyObservation()
                row["index"] = index; row["requestedOrientation"] = orientation
                row["requestedAt"] = requestedAt; row["requestedUptime"] = requestedUptime
                row["configuration"] = configuration
                row["attachmentLabel"] = "widget-family-rotation-" + String(index)
                capture(springboard, "widget-family-rotation-" + String(index))
                row["capturedAt"] = widgetStateTimestamp()
                row["capturedUptime"] = ProcessInfo.processInfo.systemUptime
                rotations.append(row)
                record["rotations"] = rotations
                record["hostTerminated"] = mini.state == .notRunning
                try checkpoint(index == 0 ? "widget-family-placed" : "widget-family-rotated")
                let reply = try response(index == 0 ? "placement.json" : "rotation-" + String(index) + ".json", timeout: 35)
                try require(reply["status"] as? String == "READY", "Actual family/configuration/rotation evidence was not accepted.")
            }
            record["cleanup"] = try removeWidgetFamily(named: instanceName)
            removed = true
            XCUIDevice.shared.orientation = prior
            try require(wait(25) { self.widgetFamilyOrientationName() == priorName && self.widgetFamilyScreenMatches(priorName) },
                        "The actual initial device orientation was not restored.")
            record["orientationRestoration"] = widgetFamilyRestoration(priorName)
            capture(springboard, "widget-family-restored")
            restored = true
            try checkpoint("widget-family-complete")
            let completion = try response("completion.json", timeout: 30)
            try require(completion["status"] as? String == "EXECUTED_PASS", "Final native/source/container/cleanup qualification did not pass.")
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"; record["error"] = String(describing: error)
            throw error
        }
    }

    private func prepareWidgetFamilyInitialOrientation() throws -> [String: Any]? {
        let initial = XCUIDevice.shared.orientation
        guard initial == .unknown else { return nil }
        var preparation: [String: Any] = [
            "schema": 1, "initialDeviceOrientation": "unknown", "initialRawValue": initial.rawValue,
            "requestedBaseline": "portrait", "startedAt": widgetStateTimestamp(),
            "scope": "Explicit owned-simulator preparation; the boot orientation is not inferred."
        ]
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.orientation = .portrait
        let ready = wait(25) {
            self.widgetFamilyOrientationName() == "portrait" && self.widgetFamilyScreenMatches("portrait")
        }
        let observed = widgetFamilyOrientationName()
        let geometryMatches = widgetFamilyScreenMatches("portrait")
        let verified = ready && observed == "portrait" && geometryMatches
        preparation["observedOrientation"] = observed
        preparation["homeGeometryMatches"] = geometryMatches
        preparation["status"] = verified ? "OBSERVED_BASELINE" : "FAILED"
        preparation["finishedAt"] = widgetStateTimestamp()
        if springboard.state == .runningForeground {
            preparation["homeFrame"] = widgetStateFrame(springboard.frame)
        }
        let attachment = XCTAttachment(string: try jsonString(preparation))
        attachment.name = "widget-family-orientation-preparation"
        attachment.lifetime = .keepAlways
        add(attachment)
        try require(verified, "The explicit starting orientation was not observed through the public device state and Home Screen geometry.")
        return preparation
    }

    private func widgetFamilyOrientationName() -> String {
        switch XCUIDevice.shared.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        default: return "unknown"
        }
    }

    private func widgetFamilyScreenMatches(_ orientation: String) -> Bool {
        let screen = springboard.frame
        guard springboard.state == .runningForeground, screen.width > 0, screen.height > 0 else { return false }
        if orientation == "portrait" || orientation == "portraitUpsideDown" { return screen.height > screen.width }
        if orientation == "landscapeLeft" || orientation == "landscapeRight" { return screen.width > screen.height }
        return false
    }

    private func setWidgetFamilyOrientation(_ name: String) throws {
        if name == "portrait" { XCUIDevice.shared.orientation = .portrait }
        else if name == "landscapeLeft" { XCUIDevice.shared.orientation = .landscapeLeft }
        else { throw ObservationFailure(description: "Unknown requested family orientation.") }
        try require(wait(25) { self.widgetFamilyOrientationName() == name && self.widgetFamilyScreenMatches(name) },
                    "Public orientation assignment did not produce the required effective Home Screen geometry.")
    }

    private func widgetFamilyVisible(_ query: XCUIElementQuery) -> [XCUIElement] {
        query.allElementsBoundByIndex.filter { $0.exists && $0.isHittable && $0.frame.width > 0
            && $0.frame.height > 0 && springboard.frame.contains($0.frame) }
    }

    private func widgetFamilyUnique(_ query: XCUIElementQuery, _ message: String) throws -> XCUIElement {
        try require(wait(12) { !self.widgetFamilyVisible(query).isEmpty }, message)
        let choices = widgetFamilyVisible(query).sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let element = try XCTUnwrap(choices.first, message)
        let area = element.frame.width * element.frame.height
        try require(choices.filter { $0.frame.width * $0.frame.height == area }.allSatisfy { $0.frame == element.frame }, message)
        return element
    }

    private func widgetFamilyMarkerCount() -> Int {
        widgetFamilyVisible(springboard.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Matrix count: "))).count
    }

    private func widgetFamilyContainer() throws -> XCUIElement {
        let labels = springboard.staticTexts.matching(NSPredicate(format: "label == %@", "Matrix count: 0"))
        try require(wait(25) { self.widgetFamilyMarkerCount() == 1 && self.widgetFamilyVisible(labels).count == 1 },
                    "A prior or second visible Matrix could alias this zero-count widget; physical identity is not unique.")
        let marker = try XCTUnwrap(widgetFamilyVisible(labels).first)
        let choices = springboard.descendants(matching: .any).containing(.staticText, identifier: "Matrix count: 0")
            .allElementsBoundByIndex.filter { element in
                let bounds = element.frame
                return bounds.width > 0 && bounds.height > 0 && bounds != springboard.frame
                    && springboard.frame.contains(bounds) && bounds.contains(marker.frame)
                    && element.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Matrix count: ")).count == 1
                    && element.switches.matching(NSPredicate(format: "label == %@", "Widget notifications")).count == 1
                    && element.buttons.matching(NSPredicate(format: "label == %@", "Add")).count == 1
                    && element.buttons.matching(NSPredicate(format: "label == %@", "Refresh")).count == 1
            }.sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        let selected = try XCTUnwrap(choices.first, "The actual AX tree does not expose one finite Matrix content container.")
        let area = selected.frame.width * selected.frame.height
        try require(choices.filter { $0.frame.width * $0.frame.height == area }.allSatisfy { $0.frame == selected.frame },
                    "The smallest actual Matrix container is ambiguous.")
        return selected
    }

    private func confirmWidgetFamily(named name: String, label: String) throws -> [String: Any] {
        let container = try widgetFamilyContainer()
        let frame = container.frame
        container.press(forDuration: 1.5)
        try tap(springboard.buttons["Edit Widget"].firstMatch, "Read this physical widget's saved instance before credit or removal.")
        let selected = try widgetFamilyUnique(springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", name, name)),
            "The actual configuration belongs to another or an unidentifiable widget.")
        let selectedLabel = selected.label; let value = selected.value as? String ?? ""
        try require(selectedLabel.contains(name) || value.contains(name), "The real configuration does not select the exact case UUID.")
        capture(springboard, label)
        XCUIDevice.shared.press(.home)
        let after = try widgetFamilyContainer()
        try require(after.frame == frame && mini.state == .notRunning, "Reading configuration replaced the physical widget or opened its host.")
        return ["instanceName": name, "label": selectedLabel, "value": value,
                "frame": widgetStateFrame(frame), "verifiedAt": widgetStateTimestamp(),
                "verifiedUptime": ProcessInfo.processInfo.systemUptime, "attachmentLabel": label]
    }

    private func widgetFamilyObservation() throws -> [String: Any] {
        let container = try widgetFamilyContainer()
        let marker = try XCTUnwrap(widgetFamilyVisible(springboard.staticTexts.matching(
            NSPredicate(format: "label == %@", "Matrix count: 0"))).first)
        try require(mini.state == .notRunning, "MiniApps must stay terminated during the actual family observation.")
        return ["visibleMatrixCount": widgetFamilyMarkerCount(), "markerLabel": marker.label,
                "markerHittable": marker.isHittable, "markerFrame": widgetStateFrame(marker.frame),
                "widgetFrame": widgetStateFrame(container.frame), "screenFrame": widgetStateFrame(springboard.frame),
                "orientation": widgetFamilyOrientationName(), "hostTerminated": mini.state == .notRunning]
    }

    private func widgetHomeScreenIcon() throws -> XCUIElement? {
        var reachedFirstPage = false
        for attempt in 0..<5 {
            let screen = springboard.frame
            try require(screen.width > 0 && screen.height > 0 &&
                        [screen.minX, screen.minY, screen.maxX, screen.maxY].allSatisfy { $0.isFinite },
                        "The owned Home Screen has no finite visible frame.")
            // App Library exposes the same app icon label, but a different menu.
            let library = springboard.searchFields.matching(
                NSPredicate(format: "identifier == %@", "dewey-search-field"))
            if !widgetFamilyVisible(library).isEmpty {
                if attempt < 4 { springboard.swipeRight() }
                continue
            }
            let homes = springboard.otherElements.matching(
                NSPredicate(format: "identifier == %@", "Home screen icons"))
                .allElementsBoundByIndex.filter {
                    $0.exists && $0.frame.width > 0 && $0.frame.height > 0 && screen.contains($0.frame)
                }
            try require(homes.count == 1, "The actual Home Screen icon container is missing or ambiguous.")
            let pages = widgetFamilyVisible(homes[0].descendants(matching: .pageIndicator).matching(
                NSPredicate(format: "identifier == %@", "Page control")))
            try require(pages.count == 1, "The current Home Screen page indicator is not uniquely visible.")
            let pageValue = try XCTUnwrap(pages[0].value as? String, "The Home Screen page has no actual value.")
            let fields = pageValue.split(separator: " ")
            try require(fields.count == 4 && fields[0] == "Page" && fields[2] == "of",
                        "The actual Home Screen page value is unrecognized.")
            let page = try XCTUnwrap(Int(fields[1]), "The Home Screen page index is invalid.")
            let count = try XCTUnwrap(Int(fields[3]), "The Home Screen page count is invalid.")
            try require(page > 0 && count > 0 && page <= count,
                        "The current surface is outside the actual Home Screen pages.")
            let icons = widgetFamilyVisible(homes[0].descendants(matching: .icon).matching(
                NSPredicate(format: "label == %@", "Hanlin MiniApps")))
                .filter { $0.frame.maxY < screen.maxY - 140 }
            try require(icons.count <= 1, "Multiple MiniApps icons are visible on the same Home Screen page.")
            if let icon = icons.first { return icon }
            if page == 1 { reachedFirstPage = true }
            if attempt == 4 { break }
            if !reachedFirstPage && page > 1 {
                springboard.swipeRight()
            } else if page < count {
                springboard.swipeLeft()
            } else {
                break
            }
        }
        return nil
    }

    private func openWidgetFamilyGallery(sizeLabel: String) throws {
        let selectedIcon = try widgetHomeScreenIcon()
        let icon = try XCTUnwrap(selectedIcon, "The installed MiniApps Home Screen icon is absent.")
        let placeholders = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choose a widget instance"))
        try require(widgetFamilyMarkerCount() == 0 && widgetFamilyVisible(placeholders).isEmpty,
                    "This placement page already has an unowned Matrix or placeholder; do not reuse or remove it.")
        record["prePlacement"] = ["visibleMatrixCount": 0, "visiblePlaceholderCount": 0,
            "screenFrame": widgetStateFrame(springboard.frame), "orientation": widgetFamilyOrientationName(),
            "at": widgetStateTimestamp(), "uptime": ProcessInfo.processInfo.systemUptime]
        capture(springboard, "widget-family-before-placement")
        icon.press(forDuration: 1.2)
        let editHome = springboard.buttons["Edit Home Screen"].firstMatch
        if !editHome.exists && springboard.buttons["Options"].firstMatch.exists { springboard.buttons["Options"].firstMatch.tap() }
        try tap(editHome, "Open the actual Home Screen edit mode.")
        if springboard.buttons["Edit"].firstMatch.exists { springboard.buttons["Edit"].firstMatch.tap() }
        try tap(firstButton(springboard, ["Add Widget", "Add Widgets"]), "Open the real widget gallery.")
        let search = springboard.searchFields.firstMatch
        try tap(search, "Search the actual MiniApps widget provider."); search.typeText("Hanlin MiniApps")
        let gallery = springboard.collectionViews["add-sheet-collection-view"].firstMatch
        try require(gallery.waitForExistence(timeout: bounded(15)), "The system gallery collection is unavailable.")
        try tap(gallery.cells.matching(NSPredicate(format: "label == %@", "Hanlin MiniApps")).firstMatch,
                "Open the real installed MiniApps widget provider.")
        let end = Date().addingTimeInterval(bounded(35))
        var pages: [[String: Any]] = []
        var seen = Set<String>()
        for index in 0..<12 {
            try require(Date() < end && Date() < deadline, "The bounded actual gallery traversal did not offer this named family.")
            let rowTypes: [XCUIElement.ElementType] = [.staticText, .button, .pageIndicator]
            let candidates = rowTypes.flatMap {
                springboard.descendants(matching: $0).allElementsBoundByIndex
            }
            let rows = candidates.filter {
                $0.exists && $0.isHittable && springboard.frame.contains($0.frame)
            }.map { ["label": $0.label, "value": $0.value as? String ?? "", "frame": widgetStateFrame($0.frame)] as [String: Any] }
            try require(rows.count <= 128 && rows.allSatisfy { ($0["label"] as? String ?? "").count <= 1024 },
                        "The actual gallery page evidence exceeded its finite observation bound.")
            let texts = rows.flatMap { [$0["label"] as? String ?? "", $0["value"] as? String ?? ""] }
            let normalized = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let selected = normalized.contains("hanlin script") &&
                normalized.contains(where: { $0 == sizeLabel.lowercased() || $0 == sizeLabel.lowercased() + " widget" })
            let signature = try String(data: JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), encoding: .utf8)
            let actualSignature = try XCTUnwrap(signature)
            try require(seen.insert(actualSignature).inserted, "The actual gallery repeated a page without offering the named family.")
            let page: [String: Any] = ["index": index, "rows": rows, "selected": selected,
                "observedAt": widgetStateTimestamp(), "uptime": ProcessInfo.processInfo.systemUptime,
                "attachmentLabel": "widget-family-gallery-" + String(index)]
            pages.append(page); record["galleryPages"] = pages
            capture(springboard, "widget-family-gallery-" + String(index))
            if selected {
                _ = try widgetFamilyUnique(springboard.buttons.matching(NSPredicate(format: "label MATCHES %@", "\\s*Add Widget\\s*")),
                                            "The observed named family page has no unique Add Widget control.")
                return
            }
            springboard.swipeLeft()
        }
        throw ObservationFailure(description: "The actual gallery never exposed Hanlin Script and the requested family label; swipe count is not family evidence.")
    }

    private func removeWidgetFamily(named name: String) throws -> [String: Any] {
        let binding = try confirmWidgetFamily(named: name, label: "widget-family-cleanup-configuration")
        let container = try widgetFamilyContainer()
        container.press(forDuration: 1.5)
        try tap(springboard.buttons["Remove Widget"].firstMatch, "Remove only the physical widget just verified as this case's name.")
        let confirmation = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Remove' OR label == 'Remove Widget'"))
        let confirm = try widgetFamilyUnique(confirmation, "The actual widget-removal confirmation is unavailable.")
        let confirmationLabel = confirm.label
        capture(springboard, "widget-family-remove-confirmation")
        try tap(confirm, "Confirm the real owned-widget removal.")
        try require(wait(25) { self.widgetFamilyMarkerCount() == 0 }, "The owned Matrix remains physically visible after removal.")
        try require(mini.state == .notRunning, "Removing the widget unexpectedly opened MiniApps.")
        capture(springboard, "widget-family-removed")
        return ["instanceName": name, "configuration": binding, "action": "Remove Widget",
                "confirmationLabel": confirmationLabel, "visibleMatrixCountAfter": widgetFamilyMarkerCount(),
                "hostTerminated": mini.state == .notRunning, "removedAt": widgetStateTimestamp(),
                "removedUptime": ProcessInfo.processInfo.systemUptime]
    }

    private func widgetFamilyRestoration(_ prior: String) -> [String: Any] {
        ["priorOrientation": prior, "orientation": widgetFamilyOrientationName(),
         "screenFrame": widgetStateFrame(springboard.frame), "restoredAt": widgetStateTimestamp(),
         "restoredUptime": ProcessInfo.processInfo.systemUptime]
    }


    private struct WidgetStateControls {
        let container: XCUIElement
        let toggle: XCUIElement
        let add: XCUIElement
        let refresh: XCUIElement
    }

    private func createSecondWidgetStateInstance(named name: String) throws {
        let field = mini.textFields["hanlin-widget-instance-name"].firstMatch
        try reveal(field, in: mini, message: "The shipping independent-instance editor is unavailable.")
        try tap(field, "Name the second independent widget variant.")
        try require((field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue,
                    "The original instance-name field did not reset after creating A.")
        field.typeText(name)
        let create = mini.buttons["hanlin-widget-create-instance"].firstMatch
        try reveal(create, in: mini, message: "The shipping create-instance action is unavailable.")
        try tap(create, "Create B through the original instance API.")
        try require(mini.staticTexts[name].firstMatch.waitForExistence(timeout: bounded(15)),
                    "The actual second independent variant was not published.")
    }

    private func widgetStateControls(count: Int) throws -> WidgetStateControls {
        let text = "Matrix count: " + String(count)
        let counts = springboard.staticTexts.matching(NSPredicate(format: "label == %@", text))
        try require(wait(25) { counts.count == 1 && counts.firstMatch.isHittable },
                    "The actual placed Matrix count is absent or ambiguous: " + text)
        let grouped = springboard.descendants(matching: .any).containing(.staticText, identifier: text)
        var choices: [WidgetStateControls] = []
        for container in grouped.allElementsBoundByIndex {
            let countLabels = container.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Matrix count: "))
            let toggles = container.switches.matching(NSPredicate(format: "label == %@", "Widget notifications"))
            let adds = container.buttons.matching(NSPredicate(format: "label == %@", "Add"))
            let refreshes = container.buttons.matching(NSPredicate(format: "label == %@", "Refresh"))
            if countLabels.count == 1 && toggles.count == 1 && adds.count == 1 && refreshes.count == 1
                && toggles.firstMatch.isHittable && adds.firstMatch.isHittable && refreshes.firstMatch.isHittable {
                let bounds = container.frame
                if bounds.width > 0 && bounds.height > 0 && bounds.contains(toggles.firstMatch.frame)
                    && bounds.contains(adds.firstMatch.frame) && bounds.contains(refreshes.firstMatch.frame) {
                    choices.append(.init(container: container, toggle: toggles.firstMatch,
                                         add: adds.firstMatch, refresh: refreshes.firstMatch))
                }
            }
        }
        choices.sort { $0.container.frame.width * $0.container.frame.height < $1.container.frame.width * $1.container.frame.height }
        let selected = try XCTUnwrap(choices.first, "The live AX tree does not group one real Toggle/Add/Refresh with this widget.")
        let area = selected.container.frame.width * selected.container.frame.height
        try require(choices.filter { $0.container.frame.width * $0.container.frame.height == area }
            .allSatisfy { $0.container.frame == selected.container.frame },
                    "The smallest real AX widget container is physically ambiguous.")
        return selected
    }

    private func widgetStateFrame(_ frame: CGRect) -> [Double] {
        [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)]
    }

    private func widgetStateObservations(_ counts: [String: Int]) throws -> [String: Any] {
        try require(mini.state == .notRunning, "MiniApps opened during a genuine widget action.")
        var result: [String: Any] = [:]
        var frames: [CGRect] = []
        for key in counts.keys.sorted() {
            let count = try XCTUnwrap(counts[key])
            let controls = try widgetStateControls(count: count)
            let value = try XCTUnwrap(controls.toggle.value as? String,
                                     "The actual native switch did not expose a string AX value.")
            try require(value == "0" || value == "1", "Unrecognized actual native switch value: " + value)
            try require(!frames.contains(where: { $0.intersects(controls.container.frame) }),
                        "The two named variants must occupy distinct visible physical containers.")
            frames.append(controls.container.frame)
            result[key] = ["count": count, "switchValue": value, "switchEnabled": controls.toggle.isEnabled,
                           "switchHittable": controls.toggle.isHittable, "addHittable": controls.add.isHittable,
                           "refreshHittable": controls.refresh.isHittable,
                           "frame": widgetStateFrame(controls.container.frame),
                           "switchFrame": widgetStateFrame(controls.toggle.frame),
                           "addFrame": widgetStateFrame(controls.add.frame),
                           "refreshFrame": widgetStateFrame(controls.refresh.frame)]
        }
        return result
    }

    private func confirmWidgetStateConfiguration(_ key: String, count: Int,
                                                names: [String: String]) throws -> [String: Any] {
        let expected = try XCTUnwrap(names[key])
        let other = try XCTUnwrap(names[key == "A" ? "B" : "A"])
        let controls = try widgetStateControls(count: count)
        let before = controls.container.frame
        controls.container.press(forDuration: 1.5)
        try tap(springboard.buttons["Edit Widget"].firstMatch, "Read this physical widget's actual saved instance selection.")
        let selected = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected))
        try require(wait(15) { selected.allElementsBoundByIndex.contains { $0.exists && $0.isHittable } },
                    "The real Edit Widget panel does not expose the expected saved named instance.")
        let element = try XCTUnwrap(selected.allElementsBoundByIndex.first { $0.exists && $0.isHittable })
        let label = element.label
        let value = element.value as? String ?? ""
        try require((label.contains(expected) || value.contains(expected))
                    && !label.contains(other) && !value.contains(other),
                    "The actual configuration does not uniquely select this fresh named variant.")
        capture(springboard, "widget-state-" + key + "-configuration-" + String(count))
        XCUIDevice.shared.press(.home)
        let after = try widgetStateControls(count: count)
        try require(after.container.frame == before && mini.state == .notRunning,
                    "Reading the actual configuration changed the physical widget or opened MiniApps.")
        return ["instanceName": expected, "count": count, "label": label, "value": value,
                "frame": widgetStateFrame(before), "verifiedAt": widgetStateTimestamp()]
    }

    private func performWidgetStateAction(_ index: Int, instance: String, action: String, desired: Bool?,
                                          before: [String: Int], after: [String: Int]) throws {
        let actionID = UUID().uuidString.lowercased()
        let step: [String: Any] = ["index": index, "actionID": actionID, "instance": instance,
                                  "action": action, "desiredValue": desired.map { $0 as Any } ?? NSNull()]
        record["step"] = step
        record["tapObserved"] = false
        record["ui"] = try widgetStateObservations(before)
        record["hostTerminated"] = mini.state == .notRunning
        try checkpoint("widget-state-arm")
        let armed = try response("armed-" + String(index) + ".json", timeout: 20)
        let armedStep = try XCTUnwrap(armed["step"] as? [String: Any])
        try require(armed["status"] as? String == "READY" && armedStep["actionID"] as? String == actionID,
                    "The exact fresh action must be armed against both current native states.")
        let controls = try widgetStateControls(count: try XCTUnwrap(before[instance]))
        let element: XCUIElement
        switch action {
        case "toggle":
            let current = try XCTUnwrap(controls.toggle.value as? String)
            try require(current == (desired == true ? "0" : "1"), "The real Toggle must receive the opposite intended value.")
            element = controls.toggle
        case "add": element = controls.add
        case "refresh": element = controls.refresh
        default: throw ObservationFailure(description: "Unknown widget-state action.")
        }
        try tap(element, "Invoke the original " + action + " control on physical widget " + instance + ".")
        var hostStarted = mini.state != .notRunning
        try require(wait(35) {
            if self.mini.state != .notRunning { hostStarted = true }
            return after.values.allSatisfy {
                self.springboard.staticTexts["Matrix count: " + String($0)].firstMatch.exists
            }
        }, "The actual placed widgets did not reach the expected visible counts.")
        try require(!hostStarted && mini.state == .notRunning, "The original widget action opened MiniApps.")
        record["tapObserved"] = true
        record["tapObservedAt"] = widgetStateTimestamp()
        record["ui"] = try widgetStateObservations(after)
        record["hostTerminated"] = true
        capture(springboard, "widget-state-step-" + String(index))
        try checkpoint("widget-state-applied")
        let applied = try response("applied-" + String(index) + ".json", timeout: 35)
        let appliedStep = try XCTUnwrap(applied["step"] as? [String: Any])
        try require(applied["status"] as? String == "APPLIED" && appliedStep["actionID"] as? String == actionID,
                    "The actual AppIntent must commit one fresh nonce/revision and preserve the other variant.")
    }

    private func widgetStateTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func importMatrixWidgetAndCreateInstance(named instanceName: String) throws {
        try tap(mini.buttons["hanlin-apps-add"].firstMatch, "Open the shipping MiniApps package catalog.")
        try tap(mini.buttons["hanlin-import-script-package"].firstMatch, "Open the original package importer.")
        let list = mini.collectionViews["hanlin-package-import-list"].firstMatch
        try require(list.waitForExistence(timeout: bounded(15)), "The original import list is unavailable.")
        let archive = list.buttons["Hanlin-Expo-Widget-Interactive-Matrix"].firstMatch
        try reveal(archive, in: list, message: "The exact original Matrix archive was not staged.")
        try tap(archive, "Import the authored Matrix through the original compiler.")
        let install = mini.buttons["hanlin-package-install"].firstMatch
        let importError = mini.descendants(matching: .any)["hanlin-import-error-message"].firstMatch
        let diagnostics = mini.descendants(matching: .any)["hanlin-import-diagnostics-sheet"].firstMatch
        try require(wait(120) { install.exists || importError.exists || diagnostics.exists },
                    "The original Matrix import did not reach a concrete outcome.")
        capture(mini, "widget-import-preview")
        try require(!importError.exists && !diagnostics.exists && install.exists,
                    "The real compiler rejected the authored Matrix fixture.")
        try tap(install, "Install through the original production preview.")
        try require(wait(45) { !install.exists || importError.exists }, "The real installer did not finish.")
        try require(!importError.exists, "The original installer reported an error.")
        try tap(mini.buttons["hanlin-package-import-done"].firstMatch, "Return to the installed package list.")
        let card = mini.buttons["hanlin-package-card-Interactive Widget Matrix"].firstMatch
        try reveal(card, in: mini, message: "The installed widget-only package is absent.")
        try tap(card, "Open the widget-only package's original Package Information.")
        let field = mini.textFields["hanlin-widget-instance-name"].firstMatch
        try reveal(field, in: mini, message: "The original independent-instance editor is unavailable.")
        try tap(field, "Name a new independent widget instance.")
        field.typeText(instanceName)
        let create = mini.buttons["hanlin-widget-create-instance"].firstMatch
        try reveal(create, in: mini, message: "The original create-instance action is unavailable.")
        try tap(create, "Create an independent instance through production UI.")
        try require(mini.staticTexts[instanceName].firstMatch.waitForExistence(timeout: bounded(15)),
                    "The actual new instance was not published in Package Information.")
    }

    private func tapWidgetInstanceChooseButton(_ message: String) throws {
        var selectedButton: XCUIElement?
        try require(wait(12) {
            selectedButton = nil
            let screen = self.springboard.frame
            let rows = self.springboard.cells.containing(.staticText, identifier: "Widget instance")
                .allElementsBoundByIndex.filter { row in
                    guard row.exists else { return false }
                    let frame = row.frame
                    return frame.minX.isFinite && frame.minY.isFinite &&
                        frame.maxX.isFinite && frame.maxY.isFinite &&
                        frame.width > 0 && frame.height > 0 && screen.contains(frame)
                }
            guard rows.count == 1 else { return false }
            let row = rows[0]
            let buttons = row.buttons.matching(NSPredicate(format: "label == %@", "Choose"))
                .allElementsBoundByIndex.filter { button in
                    guard button.exists && button.isEnabled && button.isHittable else { return false }
                    let frame = button.frame
                    return frame.minX.isFinite && frame.minY.isFinite &&
                        frame.maxX.isFinite && frame.maxY.isFinite &&
                        frame.width > 0 && frame.height > 0 &&
                        row.frame.contains(frame) && screen.contains(frame)
                }
            guard buttons.count == 1 else { return false }
            selectedButton = buttons[0]
            return true
        }, message)
        try XCTUnwrap(selectedButton, message).tap()
    }

    private func placeMatrixWidget(selecting instanceName: String) throws {
        // This reuses the original SpringBoard gallery/configuration path.
        // A fresh matching native fallback event later proves the actual family.
        XCUIDevice.shared.press(.home)
        let selectedIcon = try widgetHomeScreenIcon()
        let icon = try XCTUnwrap(selectedIcon, "The installed MiniApps Home Screen icon is absent.")
        icon.press(forDuration: 1.2)
        let editHome = springboard.buttons["Edit Home Screen"].firstMatch
        if !editHome.exists && springboard.buttons["Options"].firstMatch.exists {
            springboard.buttons["Options"].firstMatch.tap()
        }
        try tap(editHome, "Open the real Home Screen edit mode.")
        if springboard.buttons["Edit"].firstMatch.exists { springboard.buttons["Edit"].firstMatch.tap() }
        try tap(firstButton(springboard, ["Add Widget", "Add Widgets"]), "Open the real system widget gallery.")
        let search = springboard.searchFields.firstMatch
        try tap(search, "Search the functioning system widget gallery.")
        search.typeText("Hanlin MiniApps")
        let gallery = springboard.collectionViews["add-sheet-collection-view"].firstMatch
        try require(gallery.waitForExistence(timeout: bounded(15)), "The system widget gallery list is unavailable.")
        let app = gallery.cells.matching(NSPredicate(format: "label == %@", "Hanlin MiniApps")).firstMatch
        try tap(app, "Select the installed standalone MiniApps widget provider.")
        capture(springboard, "widget-gallery-first-family")
        let add = springboard.buttons.matching(NSPredicate(format: "label MATCHES %@", "\\s*Add Widget\\s*")).firstMatch
        try require(add.waitForExistence(timeout: bounded(15)), "The real WidgetKit family preview is unavailable.")
        springboard.swipeLeft()
        capture(springboard, "widget-gallery-medium-request")
        try tap(add, "Place the requested medium widget using the real gallery.")
        if springboard.buttons["Done"].firstMatch.exists { springboard.buttons["Done"].firstMatch.tap() }
        let placeholder = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Choose a widget instance")).firstMatch
        try require(placeholder.waitForExistence(timeout: bounded(25)),
                    "The new placed widget did not expose its original configuration placeholder.")
        placeholder.press(forDuration: 1.5)
        try tap(springboard.buttons["Edit Widget"].firstMatch, "Configure the genuine placed widget.")
        try tapWidgetInstanceChooseButton("Open the original installed-instance entity query.")
        let entity = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", instanceName)).firstMatch
        try tap(entity, "Choose the exact fresh instance created by the MiniApps UI.")
        XCUIDevice.shared.press(.home)
        mini.terminate()
        try require(mini.state == .notRunning, "Terminate the host after the real entity query before native widget actions.")
        capture(springboard, "widget-configured")
    }


    private func observe(_ engine: Engine, _ surface: Surface, canPresentUI: Bool? = nil) throws {
        continueAfterFailure = false
        let allowance: TimeInterval = surface == .miniAppShortcut ? 360 : 240
        executionTimeAllowance = allowance
        deadline = Date().addingTimeInterval(allowance)
        let runID = UUID().uuidString.lowercased()
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": engine.rawValue,
                  "surface": surface.rawValue, "fixtureAppID": engine.appID,
                  "fixtureTitle": engine.title, "status": "RUNNING",
                  "startedAt": timestamp(), "test": name, "phase": "preparing",
                  "systemLaunchObserved": false]
        if surface == .miniAppShortcut {
            record["expectedCanPresentUI"] = try XCTUnwrap(canPresentUI)
            record["shortcutIntent"] = "Run MiniApp Action"
        }
        try checkpoint("preparing")
        defer {
            capture(mini, "final-mini")
            capture(springboard, "final-system")
            record["finishedAt"] = timestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }

        do {
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try openInstalledFixture(engine)
            let status = mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "App ID:")).firstMatch
            try require(wait(20) { status.exists && self.stateFields(status.label)["App ID"] == engine.appID },
                        "The fixture did not expose its actual initial state.")
            let previousStatus = status.label
            let previousChallenge = stateFields(previousStatus)["Challenge"]
            let prepare = mini.buttons["Prepare challenge"].firstMatch
            try tap(prepare, "The real fixture must prepare its private challenge.")
            try require(wait(20) {
                guard status.exists else { return false }
                let fields = self.stateFields(status.label)
                guard let challenge = fields["Challenge"], !challenge.isEmpty,
                      challenge != "not-prepared", challenge != previousChallenge else { return false }
                return fields["App ID"] == engine.appID && fields["Counter"] == "0" && prepare.isEnabled
            }, "Prepare challenge must finish its actual asynchronous state write with a new non-placeholder challenge and counter zero.")
            let fields = stateFields(status.label)
            let challenge = try XCTUnwrap(fields["Challenge"])
            let counter = try XCTUnwrap(fields["Counter"].flatMap { Int($0) })
            try require(fields["App ID"] == engine.appID && !challenge.isEmpty && challenge != "not-prepared" &&
                        challenge != previousChallenge && counter == 0,
                        "The visible fixture identity/challenge does not match the newly prepared state.")
            record["visibleStateBeforePreparation"] = previousStatus
            record["challenge"] = challenge
            record["baselineCounter"] = counter
            record["visibleStateBefore"] = status.label
            capture(mini, "prepared-fixture")
            try checkpoint("prepared")

            // The observer resolves the real post-XCTest MCM containers and the
            // installed published identity. It never installs a package or seeds
            // a command, grant, receipt, result or queue on this test's behalf.
            let identity = try response("identity.json", timeout: 20)
            try require(identity["status"] as? String == "READY" &&
                        identity["appID"] as? String == engine.appID,
                        "The observer could not authenticate the actual installed target.")
            record["installedIdentity"] = identity

            switch surface {
            case .widget: try runPlacedWidget(engine, identity: identity)
            case .liveActivity: try runLiveActivity(engine, identity: identity)
            case .shortcuts: try runShortcut(engine, identity: identity)
            case .miniAppShortcut: try runMiniAppShortcut(engine, identity: identity, canPresentUI: try XCTUnwrap(canPresentUI))
            case .share: try runShare(engine, identity: identity)
            case .translation: try runTranslation(engine, identity: identity)
            }

            record["systemLaunchObserved"] = true
            try checkpoint("system-action-sent")
            let completion = surface == .miniAppShortcut
                ? try shortcutCompletion(canPresentUI: try XCTUnwrap(canPresentUI))
                : try response("completion.json", timeout: 100)
            record["observerCompletion"] = completion
            try require(completion["status"] as? String == "EXECUTED_PASS",
                        "The actual system action did not produce the required correlated five-engine receipts: \(completion)")
            try require(completion["challenge"] as? String == challenge &&
                        completion["counter"] as? Int == counter + 1,
                        "The result must belong to this fresh challenge and increment its actual state once.")
            try require(completion["engines"] as? [String] == ["node", "typescript", "python", "javascript", "shell"],
                        "The observer did not verify all five canonical runtimes.")
            try require(completion["invocationID"] as? String != nil &&
                        completion["receipt"] as? [String: Any] != nil,
                        "A real durable invocation receipt is required.")
            if surface == .miniAppShortcut {
                try verifyChainedShortcutResult(engine, completion: completion)
            }
            mini.activate()
            if mini.buttons["Read last result"].firstMatch.waitForExistence(timeout: bounded(10)) {
                try tap(mini.buttons["Read last result"].firstMatch, "Read the real persisted result.")
            }
            capture(mini, "actual-result")
            record["status"] = "EXECUTED_PASS"
        } catch let skipped as XCTSkip {
            record["status"] = "BLOCKED"
            record["reason"] = String(describing: skipped)
            throw skipped
        } catch {
            record["status"] = "FAILED"
            record["reason"] = String(describing: error)
            throw error
        }
    }

    private func stateFields(_ label: String) -> [String: String] {
        var fields: [String: String] = [:]
        for part in label.components(separatedBy: " | ") {
            guard let range = part.range(of: ": ") else { return [:] }
            let key = String(part[..<range.lowerBound])
            guard fields[key] == nil else { return [:] }
            fields[key] = String(part[range.upperBound...])
        }
        return fields
    }

    private func openInstalledFixture(_ engine: Engine) throws {
        let close = mini.buttons["hanlin-script-app-close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
        let manage = mini.buttons["hanlin-apps-add"].firstMatch
        try require(manage.waitForExistence(timeout: bounded(25)), "The shipping MiniApps catalog is unavailable.")
        let card = mini.buttons["hanlin-package-card-" + engine.title].firstMatch
        if !card.exists {
            try tap(manage, "Open the existing package importer.")
            try tap(mini.buttons["hanlin-import-script-package"].firstMatch, "Open original package import.")
            let list = mini.collectionViews["hanlin-package-import-list"].firstMatch
            try require(list.waitForExistence(timeout: bounded(15)), "The original import list is unavailable.")
            let archive = list.buttons[engine.archive].firstMatch
            try reveal(archive, in: list, message: "The exact staged surface archive is absent.")
            try tap(archive, "Import the exact surface archive.")
            let install = mini.buttons["hanlin-package-install"].firstMatch
            let importError = mini.descendants(matching: .any)["hanlin-import-error-message"].firstMatch
            let diagnostics = mini.descendants(matching: .any)["hanlin-import-diagnostics-sheet"].firstMatch
            try require(wait(120) { install.exists || importError.exists || diagnostics.exists },
                        "Original strict package validation did not reach an actual outcome.")
            capture(mini, "actual-import-preview")
            try require(!importError.exists && !diagnostics.exists && install.exists,
                        "The real compiler/importer rejected the new surface fixture.")
            try tap(install, "Install through the original production preview.")
            try require(wait(45) { !install.exists || importError.exists }, "The real installer did not finish.")
            try require(!importError.exists, "The original installer reported a real error.")
            try tap(mini.buttons["hanlin-package-import-done"].firstMatch, "Dismiss the completed package importer.")
            try tap(mini.buttons["hanlin-apps-add-done"].firstMatch, "Return to the installed catalog.")
        }
        try reveal(card, in: mini, message: "The installed surface package card is absent.")
        try tap(card, "Open the actual installed surface package.")
        try require(mini.buttons["Prepare challenge"].firstMatch.waitForExistence(timeout: bounded(30)),
                    "The actual surface package runtime UI did not load.")
    }

    private func runPlacedWidget(_ engine: Engine, identity: [String: Any]) throws {
        if engine == .expo {
            try tap(mini.buttons["Publish widget"].firstMatch, "Publish through the actual Expo Host API.")
        } else {
            try tap(mini.buttons["Widget setup"].firstMatch, "Inspect the original installed ScriptWidget setup.")
        }
        capture(mini, "widget-preparation")
        try checkpoint("widget-published")
        let publication = try response("widget.json", timeout: 15)
        try require(publication["status"] as? String == "READY", "No actual current published widget is available.")
        let widgetName = try XCTUnwrap(publication["configurationTitle"] as? String)
        let entityName = try XCTUnwrap(publication["entityTitle"] as? String)

        XCUIDevice.shared.press(.home)
        let icon = springboard.icons["Hanlin MiniApps"].firstMatch
        try reveal(icon, in: springboard, message: "The installed app icon is not observable on the owned Home Screen.", horizontal: true)
        icon.press(forDuration: 1.2)
        capture(springboard, "home-edit-menu")
        try tap(firstButton(springboard, ["Edit Home Screen"]), "The actual Home Screen edit command is unavailable.")
        if springboard.buttons["Edit"].firstMatch.exists { springboard.buttons["Edit"].firstMatch.tap() }
        try tap(firstButton(springboard, ["Add Widget", "Add Widgets"]), "The actual system widget gallery could not be opened.")
        capture(springboard, "widget-gallery")
        let search = springboard.searchFields.firstMatch
        try tap(search, "The functioning widget gallery must expose its search.")
        search.typeText("Hanlin MiniApps")
        let application = springboard.staticTexts["Hanlin MiniApps"].firstMatch
        try require(application.waitForExistence(timeout: bounded(15)),
                    "PRODUCT FAILED: our widget registration is missing from the functioning system gallery.")
        try tap(application, "Select the real Hanlin MiniApps widget registration.")
        let configuration = springboard.staticTexts[widgetName].firstMatch
        try reveal(configuration, in: springboard, message: "PRODUCT FAILED: the declared widget configuration is absent.")
        try tap(configuration, "Select the actual configuration.")
        try tap(firstButton(springboard, ["Add Widget"]), "Place the real WidgetKit widget.")
        if springboard.buttons["Done"].firstMatch.exists { springboard.buttons["Done"].firstMatch.tap() }
        capture(springboard, "placed-widget")
        let action = springboard.buttons[engine.actionLabel].firstMatch
        if !action.exists {
            let widget = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", widgetName)).firstMatch
            try require(widget.exists, "PRODUCT FAILED: the placed widget has no observable current content.")
            widget.press(forDuration: 1.2)
            try tap(firstButton(springboard, ["Edit Widget"]), "Configure the actual placed widget.")
            let choice = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Widget")).firstMatch
            try tap(choice, "Select an installed widget entity.")
            try tap(springboard.staticTexts[entityName].firstMatch, "Choose the exact published installed identity.")
            if springboard.buttons["Done"].firstMatch.exists { springboard.buttons["Done"].firstMatch.tap() }
            XCUIDevice.shared.press(.home)
        }
        capture(springboard, "widget-before-action")
        try require(action.waitForExistence(timeout: bounded(15)),
                    "PRODUCT FAILED: our declared Host action is missing from the placed widget.")
        try checkpoint("before-system-action")
        try tap(action, "Tap the genuine placed widget action.")
    }

    private func runLiveActivity(_ engine: Engine, identity: [String: Any]) throws {
        try tap(mini.buttons["Start Live Activity"].firstMatch, "Start through the actual production ActivityKit route.")
        capture(mini, "activity-start")
        try checkpoint("activity-started")
        let activity = try response("activity.json", timeout: 15)
        if activity["status"] as? String == "UNAVAILABLE" {
            try block("The actual OS ActivityKit authorization/capability is unavailable.", evidence: activity)
        }
        try require(activity["status"] as? String == "READY" &&
                    !(activity["activityID"] as? String ?? "").isEmpty,
                    "PRODUCT FAILED: a real ActivityKit instance was not created.")
        record["activity"] = activity
        XCUIDevice.shared.press(.home)
        capture(springboard, "activity-home")
        // Open the real Notification Centre/Lock Screen surface using a public
        // XCTest gesture. No in-app preview or direct intent call is substituted.
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
        capture(springboard, "activity-system-surface")
        let action = springboard.buttons[engine.actionLabel].firstMatch
        try require(action.waitForExistence(timeout: bounded(15)),
                    "The real ActivityKit surface/action was not observed. Retained UI must distinguish a product failure from an unavailable system surface; this is not an assumed BLOCKED result.")
        try checkpoint("before-system-action")
        try tap(action, "Tap the actual Live Activity action.")
    }

    private func createSystemShortcut(_ message: String) throws {
        // Onboarding and the observed expanded sidebar share the original
        // creation allowance; no navigation tap substitutes for actual creation.
        var continuedWhatsNew = false
        var hidSidebar = false
        var create = shortcuts.buttons["Create Shortcut"].firstMatch
        try require(wait(12) {
            let whatsNew = self.shortcuts.staticTexts["What’s New in Shortcuts"].firstMatch
            if whatsNew.exists {
                let next = self.shortcuts.buttons["Continue"].firstMatch
                guard !continuedWhatsNew && whatsNew.isHittable &&
                        next.exists && next.isEnabled && next.isHittable else { return false }
                continuedWhatsNew = true
                next.tap()
                return false
            }
            create = self.firstButton(self.shortcuts, ["Create Shortcut", "Add", "New Shortcut"])
            if create.exists && create.isEnabled && create.isHittable { return true }

            let newShortcut = self.shortcuts.buttons["New Shortcut"].firstMatch
            guard !hidSidebar && newShortcut.exists && newShortcut.isEnabled &&
                    !newShortcut.isHittable else { return false }
            let sidebarBars = self.shortcuts.navigationBars
                .containing(.button, identifier: "sidebar.button.edit").allElementsBoundByIndex
                .filter { $0.buttons["sidebar.button.newfolder"].firstMatch.exists }
            guard sidebarBars.count == 1 else { return false }
            let hideButtons = sidebarBars[0].buttons.matching(identifier: "Hide Sidebar")
                .allElementsBoundByIndex.filter { $0.exists && $0.isEnabled && $0.isHittable }
            guard hideButtons.count == 1 else { return false }
            hidSidebar = true
            hideButtons[0].tap()
            return false
        }, message)
        create.tap()
    }

    private func shortcutActionSearchFields() -> [XCUIElement] {
        let labels = ["Search Actions", "Search for apps and actions"]
        return shortcuts.searchFields.allElementsBoundByIndex.filter { field in
            field.exists &&
                (labels.contains(field.label) || labels.contains(field.placeholderValue ?? "")) &&
                field.isEnabled && field.isHittable
        }
    }

    private func findShortcutActionSearch(
        _ message: String, navigateFromNewShortcut: Bool = true
    ) throws -> XCUIElement {
        // The original search allowance includes only observed navigation.
        // All Shortcuts' generic Search is never an action-gallery candidate.
        var enteredEditor = false
        var openedActions = false
        var search = shortcuts.searchFields["Search Actions"].firstMatch
        try require(wait(12) {
            let fields = self.shortcutActionSearchFields()
            if fields.count == 1 {
                search = fields[0]
                return true
            }
            guard fields.isEmpty && navigateFromNewShortcut else { return false }
            if !enteredEditor {
                let editors = self.shortcuts.navigationBars.matching(identifier: "New Shortcut")
                    .buttons.matching(identifier: "Editor").allElementsBoundByIndex
                    .filter { $0.exists && $0.isEnabled && $0.isHittable }
                guard editors.count <= 1 else { return false }
                if let editor = editors.first {
                    enteredEditor = true
                    editor.tap()
                    return false
                }
            }
            if !openedActions {
                for label in ["Add Action", "Search Actions"] {
                    let buttons = self.shortcuts.buttons.matching(identifier: label)
                        .allElementsBoundByIndex.filter { $0.exists && $0.isEnabled && $0.isHittable }
                    guard buttons.count <= 1 else { return false }
                    if let button = buttons.first {
                        openedActions = true
                        button.tap()
                        return false
                    }
                }
            }
            return false
        }, message)
        search.tap()
        return search
    }

    private func runShortcut(_ engine: Engine, identity: [String: Any]) throws {
        try requireSystemApp("shortcuts", identity: identity)
        shortcuts.launch()
        capture(shortcuts, "shortcuts-start")
        try createSystemShortcut("Create one actual system Shortcut.")
        let search = try findShortcutActionSearch("Search the real Shortcuts action gallery.")
        search.typeText("Hanlin MiniApps")
        let app = shortcuts.staticTexts["Hanlin MiniApps"].firstMatch
        try require(app.waitForExistence(timeout: bounded(15)),
                    "PRODUCT FAILED: our containing app is absent from the functioning Shortcuts gallery.")
        try tap(app, "Open the app's actual indexed actions.")
        try tap(shortcuts.staticTexts["Run Script Action"].firstMatch,
                "PRODUCT FAILED: the original discoverable Run Script Action is absent.")
        let parameters = [
            ("Installed Package", try string(identity, "installedPackageID")),
            ("Package", try string(identity, "packageID")),
            ("Generation", String(try XCTUnwrap(identity["generation"] as? Int))),
            ("Entrypoint", "surface-intent"), ("Action", "surface.run"),
            ("Parameters", try jsonString(["surface": "shortcuts", "challenge": try string(record, "challenge")]))
        ]
        for (title, value) in parameters { try fillShortcutParameter(title, value: value) }
        capture(shortcuts, "shortcut-configured")
        try checkpoint("before-system-action")
        try tap(firstButton(shortcuts, ["Run Shortcut", "Run"]), "Run through the actual Shortcuts application.")
    }


    /// Additional real OS route; the original Run Script Action methods above
    /// and their raw-identity/five-runtime assertions are unchanged.
    private func runMiniAppShortcut(_ engine: Engine, identity: [String: Any], canPresentUI: Bool) throws {
        try requireSystemApp("shortcuts", identity: identity)
        shortcuts.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        shortcuts.launch()
        capture(shortcuts, "miniapp-shortcuts-start")
        try createSystemShortcut("Create an actual new system Shortcut.")
        let search = try findShortcutActionSearch("Search the functioning Shortcuts gallery.")
        search.typeText("Hanlin MiniApps")
        let app = shortcuts.staticTexts["Hanlin MiniApps"].firstMatch
        try require(app.waitForExistence(timeout: bounded(15)),
                    "PRODUCT FAILED: MiniApps is absent from the functioning Shortcuts gallery.")
        try tap(app, "Inspect MiniApps' actually indexed actions.")
        try tap(shortcuts.staticTexts["Run MiniApp Action"].firstMatch,
                "PRODUCT FAILED: the new Run MiniApp Action is absent from the functioning gallery.")
        try tap(firstButton(shortcuts, ["Action", "Script Action"]),
                "Open the new intent's actual installed-action entity picker.")
        let entityName = try string(identity, "actionDisplayName")
        try tap(shortcuts.staticTexts[entityName].firstMatch,
                "PRODUCT FAILED: the current installed fixture action is absent from the entity picker.")
        if shortcuts.buttons["Show More"].firstMatch.exists { shortcuts.buttons["Show More"].firstMatch.tap() }
        try tap(shortcuts.buttons["Input Type"].firstMatch, "Choose the actual typed JSON input mode.")
        try tap(shortcuts.staticTexts["Dictionary or List (JSON)"].firstMatch,
                "The source-declared Dictionary or List input choice is unavailable.")
        let input: [String: Any] = [
            "surface": "miniAppShortcut", "challenge": try string(record, "challenge"),
            "typed": ["text": "שלום עולם", "count": 42, "enabled": true, "empty": NSNull()] as [String: Any]
        ]
        record["configuredInput"] = input
        try fillShortcutParameter("Input", value: jsonString(input))
        let mode = try shortcutModeSwitch()
        let defaultMode = try observedSwitchValue(mode)
        try require(defaultMode == false, "A newly added action must default to background.")
        record["newOpenWhenRunDefault"] = false
        if canPresentUI { try tap(mode, "Enable the system's actual Open When Run choice.") }
        let selectedMode = try observedSwitchValue(mode)
        try require(selectedMode == canPresentUI, "The actual selected Open When Run mode differs.")
        capture(shortcuts, "miniapp-shortcut-mode")
        try addShortcutAction("Get Text from Input")
        try addShortcutAction("Show Result")
        let name = "Hanlin-" + engine.rawValue + "-" + (canPresentUI ? "foreground-" : "background-") +
            String(try string(record, "runID").prefix(8))
        try renameShortcut(name)
        record["savedShortcutName"] = name
        try tap(firstButton(shortcuts, ["Done"]), "Save the actual Shortcut.")
        capture(shortcuts, "miniapp-shortcut-saved")
        shortcuts.terminate()
        mini.terminate()
        shortcuts.launch()
        let saved = shortcuts.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", name)).firstMatch
        try require(saved.waitForExistence(timeout: bounded(15)),
                    "The system did not preserve the saved Shortcut after process restart.")
        saved.press(forDuration: 1.2)
        try tap(firstButton(shortcuts, ["Edit", "Edit Shortcut"]),
                "Reopen the saved system Shortcut without executing it.")
        let restoredMode = try shortcutModeSwitch()
        let savedMode = try observedSwitchValue(restoredMode)
        try require(savedMode == canPresentUI,
                    "The OS did not persist Open When Run across save/reopen and process restart.")
        record["savedOpenWhenRun"] = canPresentUI
        capture(shortcuts, "miniapp-shortcut-reopened")
        try require(shortcuts.state == .runningForeground && mini.state != .runningForeground,
                    "The real Shortcuts application must own the initial execution surface.")
        try checkpoint("before-system-action")
        try tap(firstButton(shortcuts, ["Run Shortcut", "Run"]),
                "Execute the saved action and built-in result chain through the actual Shortcuts UI.")
    }

    private func shortcutModeSwitch() throws -> XCUIElement {
        if shortcuts.buttons["Show More"].firstMatch.exists { shortcuts.buttons["Show More"].firstMatch.tap() }
        let control = shortcuts.switches["Open When Run"].firstMatch
        try require(wait(10) { control.exists && control.isHittable },
                    "The system Open When Run control was not observed; inspect the retained system UI.")
        return control
    }

    private func observedSwitchValue(_ control: XCUIElement) throws -> Bool {
        let value = try XCTUnwrap(control.value as? String, "The actual switch has no observable value.")
        try require(value == "0" || value == "1", "The actual switch state is not a boolean.")
        return value == "1"
    }

    private func addShortcutAction(_ title: String) throws {
        if shortcutActionSearchFields().isEmpty {
            try tap(firstButton(shortcuts, ["Add Action", "Search Actions"]), "Open the system action search.")
        }
        let search = try findShortcutActionSearch(
            "Search for the original built-in " + title + " action.", navigateFromNewShortcut: false)
        if let current = search.value as? String, !current.isEmpty,
           current != "Search Actions" && current != "Search for apps and actions" {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        search.typeText(title)
        try tap(shortcuts.staticTexts[title].firstMatch, "Append the actual built-in " + title + " action.")
        capture(shortcuts, "added-" + title.replacingOccurrences(of: " ", with: "-").lowercased())
    }

    private func renameShortcut(_ name: String) throws {
        try tap(firstButton(shortcuts, ["New Shortcut", "Run MiniApp Action"]),
                "Open the real Shortcut title menu.")
        try tap(firstButton(shortcuts, ["Rename"]), "Give this real Shortcut a unique test-run name.")
        let field = shortcuts.textFields.firstMatch
        try tap(field, "Edit the actual Shortcut name.")
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(name + "\n")
        capture(shortcuts, "miniapp-shortcut-named")
    }

    private func shortcutCompletion(canPresentUI: Bool) throws -> [String: Any] {
        let directory = try XCTUnwrap(runDirectory)
        let completion = directory.appendingPathComponent("completion.json")
        var foregroundObserved = false
        var samples: [[String: Any]] = []
        let end = Date().addingTimeInterval(bounded(100))
        while Date() < end {
            let state = mini.state
            foregroundObserved = foregroundObserved || state == .runningForeground
            samples.append(["at": timestamp(), "miniAppsState": state.rawValue])
            if !canPresentUI {
                try require(state != .runningForeground,
                            "The background system action brought MiniApps to the foreground.")
            }
            if FileManager.default.fileExists(atPath: completion.path) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        record["executionApplicationStates"] = samples
        record["miniAppsForegroundObserved"] = foregroundObserved
        try require(!canPresentUI || foregroundObserved,
                    "Open When Run did not produce an actual foreground MiniApps surface.")
        capture(shortcuts, "miniapp-shortcut-terminal-system")
        capture(mini, "miniapp-shortcut-terminal-app")
        return try response("completion.json", timeout: 1)
    }

    private func equalTypedJSON(_ left: Any, _ right: Any) -> Bool {
        switch (left, right) {
        case (_ as NSNull, _ as NSNull):
            return true
        case (let left as NSNumber, let right as NSNumber):
            let leftIsBoolean = CFGetTypeID(left) == CFBooleanGetTypeID()
            let rightIsBoolean = CFGetTypeID(right) == CFBooleanGetTypeID()
            guard leftIsBoolean == rightIsBoolean else { return false }
            if leftIsBoolean { return left.boolValue == right.boolValue }
            let leftIsFloating = ["f", "d"].contains(String(cString: left.objCType))
            let rightIsFloating = ["f", "d"].contains(String(cString: right.objCType))
            guard leftIsFloating == rightIsFloating,
                  left.doubleValue.isFinite, right.doubleValue.isFinite else { return false }
            return left.compare(right) == .orderedSame
        case (let left as String, let right as String):
            return left.utf8.elementsEqual(right.utf8)
        case (let left as [Any], let right as [Any]):
            return left.count == right.count &&
                zip(left, right).allSatisfy { equalTypedJSON($0.0, $0.1) }
        case (let left as [String: Any], let right as [String: Any]):
            guard left.count == right.count else { return false }
            for (key, value) in left {
                guard let counterpart = right[key], equalTypedJSON(value, counterpart) else { return false }
            }
            return true
        default:
            return false
        }
    }

    private func verifyChainedShortcutResult(_ engine: Engine, completion: [String: Any]) throws {
        try require(wait(15) { self.shortcuts.state == .runningForeground },
                    "The result chain did not return to the real Shortcuts application.")
        let challenge = try string(record, "challenge")
        var observed: [String: Any]?
        try require(wait(15) {
            let texts = self.shortcuts.staticTexts.allElementsBoundByIndex.map(\.label) +
                self.shortcuts.textViews.allElementsBoundByIndex.compactMap { $0.value as? String }
            for text in texts where text.contains(challenge) {
                if let data = text.data(using: .utf8),
                   let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   result["challenge"] as? String == challenge {
                    observed = result
                    return true
                }
            }
            return false
        }, "The real Get Text from Input → Show Result chain did not display this invocation's JSON.")
        let output = try XCTUnwrap(observed)
        let privateProof = try XCTUnwrap(completion["privateProof"] as? [String: Any])
        let privateState = try XCTUnwrap(privateProof["value"] as? [String: Any])
        let nativeResult = try XCTUnwrap(privateState["lastResult"] as? [String: Any])
        try require(equalTypedJSON(output, nativeResult),
                    "The OS-chained JSON differs from the exact native terminal/private result.")
        try require(output["appID"] as? String == engine.appID,
                    "The system result belongs to a different installed MiniApp.")
        record["systemChainedResult"] = output
        capture(shortcuts, "miniapp-shortcut-chained-json")
        if shortcuts.buttons["Done"].firstMatch.exists {
            shortcuts.buttons["Done"].firstMatch.tap()
        }
    }

    private func runShare(_ engine: Engine, identity: [String: Any]) throws {
        try requireSystemApp("files", identity: identity)
        let folder = try string(identity, "shareInputFolder")
        let names = try XCTUnwrap(identity["shareInputNames"] as? [String])
        try require(!names.isEmpty, "The genuine file payload manifest is absent.")
        files.launch()
        if files.buttons["Browse"].firstMatch.exists { files.buttons["Browse"].firstMatch.tap() }
        try tap(files.staticTexts["On My iPad"].firstMatch, "Use the actual Files local storage browser.")
        try tap(files.staticTexts["Hanlin MiniApps"].firstMatch, "Open the containing app's normal Documents.")
        try tap(files.staticTexts[folder].firstMatch, "Open the exact staged input folder.")
        try tap(firstButton(files, ["Select"]), "Select the actual source items.")
        for name in names {
            let item = files.staticTexts[name].firstMatch
            try reveal(item, in: files, message: "The exact original shared input is absent: " + name)
            try tap(item, "Select actual shared input " + name)
        }
        try tap(firstButton(files, ["Share"]), "Open the real system Share sheet.")
        capture(files, "system-share-sheet")
        var target = files.buttons["Hanlin MiniApps"].firstMatch
        if !target.exists {
            try tap(firstButton(files, ["More"]), "Inspect the actual extension chooser.")
            target = files.buttons["Hanlin MiniApps"].firstMatch
        }
        try require(target.waitForExistence(timeout: bounded(15)),
                    "PRODUCT FAILED: our declared extension is absent from the functioning Share chooser.")
        try tap(target, "Launch the real Share extension with the actual item providers.")
        let saved = files.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Saved for Hanlin")).firstMatch
        try require(saved.waitForExistence(timeout: bounded(30)), "The actual Share extension did not retain the items.")
        capture(files, "share-extension-saved")
        try tap(firstButton(files, ["Done"]), "Finish the original Share extension.")
        try checkpoint("share-batch-saved")
        let batch = try response("share.json", timeout: 15)
        try require(batch["status"] as? String == "READY", "No matching real shared batch was observed.")
        let batchID = try string(batch, "batchID").lowercased()
        record["shareBatch"] = batch
        mini.activate()
        let close = mini.buttons["hanlin-script-app-close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
        try tap(mini.buttons["hanlin-apps-add"].firstMatch, "Open the existing MiniApps management screen.")
        try tap(mini.buttons["Shared Items"].firstMatch, "Review the actual system-shared items.")
        let chooser = mini.buttons["hanlin-share-choose-" + batchID].firstMatch
        try reveal(chooser, in: mini, message: "The actual shared batch has no delivery control.")
        try tap(chooser, "Choose an installed MiniApp action explicitly.")
        let action = mini.buttons.matching(NSPredicate(format: "label CONTAINS %@", engine.title)).firstMatch
        try require(action.waitForExistence(timeout: bounded(10)),
                    "PRODUCT FAILED: this installed engine has no declared share action.")
        capture(mini, "share-before-action")
        try checkpoint("before-system-action")
        try tap(action, "Submit the real shared batch to the installed action.")
    }

    private func runTranslation(_ engine: Engine, identity: [String: Any]) throws {
        try requireSystemApp("safari", identity: identity)
        settings.launch()
        let search = settings.searchFields.firstMatch
        if !search.exists { settings.swipeDown() }
        try tap(search, "Find the actual system default-app settings.")
        search.typeText("Default Apps")
        try tap(settings.staticTexts["Default Apps"].firstMatch, "Inspect the real default-app chooser.")
        let translation = settings.staticTexts["Translation"].firstMatch
        for _ in 0..<5 {
            if translation.exists && translation.isHittable { break }
            settings.swipeUp()
        }
        capture(settings, "translation-provider-settings")
        if !translation.exists && settings.navigationBars["Default Apps"].exists {
            try block("The working system Default Apps settings expose no Translation capability on this Simulator.",
                      evidence: ["settingsPage": "Default Apps", "translationRowObserved": false])
        }
        try tap(translation, "Choose the real Translation provider.")
        capture(settings, "translation-provider-chooser")
        let provider = settings.staticTexts["Hanlin MiniApps"].firstMatch
        try require(provider.waitForExistence(timeout: bounded(10)),
                    "PRODUCT FAILED: our declared provider is absent from the functioning Translation chooser.")
        try tap(provider, "Select the original installed MiniApps Translation extension.")

        let sourceURL = try XCTUnwrap(URL(string: try string(identity, "translationInputURL")))
        try require(["http", "https"].contains(sourceURL.scheme ?? ""), "The text source must be a genuine Safari page.")
        safari.open(sourceURL)
        let sourceText = try string(identity, "translationInputText")
        let text = safari.staticTexts[sourceText].firstMatch
        try require(text.waitForExistence(timeout: bounded(20)), "The actual source page text did not load.")
        text.press(forDuration: 1.2)
        if safari.buttons["Select All"].firstMatch.exists { safari.buttons["Select All"].firstMatch.tap() }
        capture(safari, "translation-source-selection")
        try tap(firstButton(safari, ["Translate"]), "Invoke the genuine system Translate action on selected text.")
        capture(safari, "translation-extension")
        try tap(safari.buttons["Mini Apps"].firstMatch, "Open the existing provider's installed Mini Apps picker.")
        try tap(safari.buttons[engine.title].firstMatch, "Select the actual installed Translation surface.")
        capture(safari, "translation-before-action")
        try checkpoint("before-system-action")
        try tap(safari.buttons["Run " + engine.title + " in all five runtimes"].firstMatch, "Tap the actual provider's declared Host action.")
    }

    private func fillShortcutParameter(_ title: String, value: String) throws {
        var field = shortcuts.textFields[title].firstMatch
        if !field.exists {
            if shortcuts.buttons["Show More"].firstMatch.exists { shortcuts.buttons["Show More"].firstMatch.tap() }
            try tap(shortcuts.buttons[title].firstMatch, "Edit the real Shortcut parameter " + title)
            field = shortcuts.textFields.firstMatch
        }
        try tap(field, "Type the actual installed identity into " + title)
        if let previous = field.value as? String, !previous.isEmpty && previous != title {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(value)
        if shortcuts.buttons["Done"].firstMatch.exists { shortcuts.buttons["Done"].firstMatch.tap() }
    }

    private func requireSystemApp(_ key: String, identity: [String: Any]) throws {
        let apps = try XCTUnwrap(identity["systemApps"] as? [String: Any])
        let app = try XCTUnwrap(apps[key] as? [String: Any])
        if app["available"] as? Bool == false {
            try require(app["observation"] as? [String: Any] != nil,
                        "An absent system app must have a concrete retained OS observation.")
            try block("The required system application is absent from this Simulator: " + key, evidence: app)
        }
        try require(app["available"] as? Bool == true, "System application availability was not observed.")
    }

    private func block(_ reason: String, evidence: [String: Any]) throws -> Never {
        record["blockerEvidence"] = evidence
        capture(springboard, "blocked-system-surface")
        throw XCTSkip("BLOCKED: " + reason)
    }

    private func response(_ filename: String, timeout: TimeInterval) throws -> [String: Any] {
        let directory = try XCTUnwrap(runDirectory)
        let file = directory.appendingPathComponent(filename)
        try require(wait(timeout) { FileManager.default.fileExists(atPath: file.path) },
                    "The read-only observer did not finish " + filename + " within this case's bound.")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        try require(value["schema"] as? Int == 1 && value["runID"] as? String == record["runID"] as? String,
                    "The observer response belongs to another case.")
        return value
    }

    private func checkpoint(_ phase: String) throws {
        record["phase"] = phase
        record["observedAt"] = timestamp()
        try writeJSON(record, filename: "request.json")
        let root = try XCTUnwrap(exchange)
        let active: [String: Any] = ["schema": 1, "runID": try string(record, "runID"),
                                     "engine": try string(record, "engine"), "surface": try string(record, "surface"),
                                     "startedAt": try string(record, "startedAt"), "phase": phase]
        try JSONSerialization.data(withJSONObject: active, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("active.json"), options: .atomic)
    }

    private func writeJSON(_ value: [String: Any], filename: String) throws {
        let directory = try XCTUnwrap(runDirectory)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent(filename), options: .atomic)
    }

    private func capture(_ app: XCUIApplication, _ label: String) {
        guard let directory = runDirectory else { return }
        let tree = app.state == .runningForeground ? app.debugDescription : "Observed application state: \(app.state.rawValue)"
        let text = XCTAttachment(string: tree)
        text.name = label + "-accessibility"; text.lifetime = .keepAlways; add(text)
        try? Data(tree.utf8).write(to: directory.appendingPathComponent(label + "-accessibility.txt"), options: .atomic)
        let screenshot = XCUIScreen.main.screenshot()
        let image = XCTAttachment(screenshot: screenshot)
        image.name = label; image.lifetime = .keepAlways; add(image)
        try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(label + ".png"), options: .atomic)
    }

    private func firstButton(_ app: XCUIApplication, _ labels: [String]) -> XCUIElement {
        for label in labels {
            let candidate = app.buttons[label].firstMatch
            if candidate.exists && candidate.isHittable { return candidate }
        }
        return app.buttons[labels[0]].firstMatch
    }

    private func reveal(_ element: XCUIElement, in container: XCUIElement,
                        message: String, horizontal: Bool = false) throws {
        for _ in 0..<6 {
            if element.exists && element.isHittable { break }
            if horizontal { container.swipeLeft() } else { container.swipeUp() }
        }
        try require(element.exists && element.isHittable, message)
    }

    private func tap(_ element: XCUIElement, _ message: String) throws {
        try require(wait(12) { element.exists && element.isEnabled && element.isHittable }, message)
        element.tap()
    }

    private func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(bounded(seconds))
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func bounded(_ seconds: TimeInterval) -> TimeInterval {
        max(0, min(seconds, deadline.timeIntervalSinceNow))
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw ObservationFailure(description: message) }
    }

    private func string(_ value: [String: Any], _ key: String) throws -> String {
        let result = try XCTUnwrap(value[key] as? String, "Missing actual field: " + key)
        try require(!result.isEmpty, "Empty actual field: " + key)
        return result
    }

    private func jsonString(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // Additive SCRIPTABLE06 pilot. Insert these methods inside the existing
    // HanlinEntrypointSystemSurfaceUITests class; preserve every existing method.
    func testNativeScriptOwnerSurvivesThreeOverlappingBackgroundShortcutsInReverseOrder() throws {
        try observeShortcutConcurrency(cancelOne: false)
    }

    func testNativeScriptOwnerSurvivesCancellingOneOfThreeOverlappingBackgroundShortcuts() throws {
        try observeShortcutConcurrency(cancelOne: true)
    }

    private func observeShortcutConcurrency(cancelOne: Bool) throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        deadline = Date().addingTimeInterval(540)
        let runID = UUID().uuidString.lowercased()
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinShortcutConcurrencyObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "nativescript",
                  "surface": "miniAppShortcutConcurrency",
                  "scenario": cancelOne ? "cancelOne" : "reverseCompletion",
                  "fixtureAppID": Engine.nativescript.appID, "fixtureTitle": Engine.nativescript.title,
                  "status": "RUNNING", "startedAt": concurrencyTimestamp(),
                  "test": name, "phase": "preparing", "launches": [] as [[String: Any]]]
        try checkpoint("preparing")
        defer {
            capture(mini, "concurrency-final-mini")
            capture(shortcuts, "concurrency-final-shortcuts")
            record["finishedAt"] = concurrencyTimestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try openInstalledFixture(.nativescript)
            let status = mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "App ID:")).firstMatch
            try require(wait(20) {
                status.exists && self.stateFields(status.label)["App ID"] == Engine.nativescript.appID
            }, "The actual NativeScript owner did not expose its private state.")
            let oldChallenge = stateFields(status.label)["Challenge"]
            let prepare = mini.buttons["Prepare challenge"].firstMatch
            try tap(prepare, "Prepare a fresh challenge in the actual visible owner.")
            try require(wait(20) {
                guard status.exists else { return false }
                let fields = self.stateFields(status.label)
                guard let challenge = fields["Challenge"], !challenge.isEmpty,
                      challenge != "not-prepared", challenge != oldChallenge else { return false }
                return fields["Counter"] == "0" && prepare.isEnabled
            }, "The actual owner's new challenge must finish writing before system execution.")
            let challenge = try XCTUnwrap(stateFields(status.label)["Challenge"])
            let stateLabel = mini.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "State file: ")).firstMatch
            try require(stateLabel.exists, "The actual owner's canonical state path is not observable.")
            let ownerPath = String(stateLabel.label.dropFirst("State file: ".count))
            let ownerWindowLabel = mini.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Owner window: ")).firstMatch
            try require(ownerWindowLabel.exists, "The actual initial NativeScript window identity is not observable.")
            let ownerWindowID = String(ownerWindowLabel.label.dropFirst("Owner window: ".count))
            try require(!ownerWindowID.isEmpty, "The actual initial owner window identity is empty.")
            let ownerPID = try observedConcurrencyPID("prepared")
            record["challenge"] = challenge
            record["baselineCounter"] = 0
            record["ownerStatePath"] = ownerPath
            record["ownerProcessID"] = ownerPID
            record["ownerWindowID"] = ownerWindowID
            record["visibleOwnerBefore"] = status.label
            let holds = cancelOne ? [45000, 30000, 60000] : [45000, 30000, 15000]
            let invocations: [[String: Any]] = holds.enumerated().map { index, hold in
                let token = UUID().uuidString.lowercased()
                let input: [String: Any] = [
                    "surface": "miniAppShortcutConcurrency", "challenge": challenge,
                    "concurrency": ["schema": 1, "token": token, "holdMilliseconds": hold] as [String: Any],
                    "typed": ["text": "שלום עולם", "count": 42, "enabled": true, "empty": NSNull(),
                              "list": [true, 42, "שלום"] as [Any]] as [String: Any]
                ]
                return ["token": token, "savedShortcutName": "Hanlin-NS-" + String(runID.prefix(8)) + "-" + String(index + 1),
                        "configuredInput": input,
                        "expectedTerminal": cancelOne && index == 2 ? "cancelled" : "succeeded"] as [String: Any]
            }
            record["invocations"] = invocations
            capture(mini, "concurrency-prepared-owner")
            try checkpoint("prepared")
            let identity = try response("identity.json", timeout: 25)
            try require(identity["status"] as? String == "READY" &&
                        identity["appID"] as? String == Engine.nativescript.appID,
                        "The observer did not bind the real current NativeScript installation.")
            record["installedIdentity"] = identity
            try requireSystemApp("shortcuts", identity: identity)
            shortcuts.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            shortcuts.launch()
            for spec in invocations {
                try configureConcurrencyShortcut(spec, identity: identity)
            }

            // Refocus the already running owner, without terminating or launching
            // it again, and retain the actual public accessibility PID.
            mini.activate()
            let beforeLaunchPID = try observedConcurrencyPID("before-os-launches")
            try require(beforeLaunchPID == ownerPID,
                        "Saving Shortcuts replaced the original MiniApps owner process.")
            try require(stateFields(status.label)["Challenge"] == challenge &&
                        stateFields(status.label)["Counter"] == "0",
                        "Saving Shortcuts changed the original owner's actual private state.")
            try require(ownerWindowLabel.label == "Owner window: " + ownerWindowID,
                        "Saving Shortcuts replaced the original foreground window.")
            shortcuts.activate()
            try checkpoint("before-system-actions")
            var launches: [[String: Any]] = []
            for spec in invocations {
                let shortcutName = try string(spec, "savedShortcutName")
                var components = URLComponents()
                components.scheme = "shortcuts"
                components.host = "run-shortcut"
                components.queryItems = [URLQueryItem(name: "name", value: shortcutName)]
                let url = try XCTUnwrap(components.url)
                let requestedAt = concurrencyTimestamp()
                // Existing repository API: MiniAppsNativeScriptWindowUITests.swift
                // uses XCUIDevice.shared.system.open(url) to preserve the SUT PID.
                XCUIDevice.shared.system.open(url)
                try require(wait(10) { self.shortcuts.state == .runningForeground },
                            "The public URL did not open the real Shortcuts application.")
                try require(mini.state != .runningForeground,
                            "A background action brought the MiniApps owner to the foreground.")
                launches.append(["token": try string(spec, "token"), "savedShortcutName": shortcutName,
                                 "url": url.absoluteString, "requestedAt": requestedAt,
                                 "observedAt": concurrencyTimestamp(), "systemLaunchObserved": true])
                record["launches"] = launches
                capture(shortcuts, "concurrency-launch-" + String(launches.count))
                try checkpoint("system-actions-sent")
            }
            try checkpoint("overlap-requested")
            let overlapping = try concurrencyResponse("overlap.json", timeout: 30)
            try require(overlapping["status"] as? String == "OVERLAP_OBSERVED",
                        "The system serialized, rejected, or failed to start three actual handlers.")
            record["actualOverlap"] = overlapping
            capture(shortcuts, "concurrency-observed-overlap")
            if cancelOne {
                let selected = invocations[2]
                let selectedName = try string(selected, "savedShortcutName")
                let title = shortcuts.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", selectedName)).firstMatch
                try require(title.exists && title.isHittable,
                            "The last-launched running Shortcut must be visibly identified before Stop.")
                let stop = firstButton(shortcuts, ["Stop Shortcut", "Stop"])
                try require(stop.exists && stop.isEnabled && stop.isHittable,
                            "The actual system Stop control is unavailable for the selected running Shortcut.")
                capture(shortcuts, "concurrency-before-system-stop")
                let requestedAt = concurrencyTimestamp()
                try tap(stop, "Cancel only the visibly selected running Shortcut through its system Stop control.")
                record["stop"] = ["token": try string(selected, "token"), "savedShortcutName": selectedName,
                                  "visibleShortcutName": selectedName, "requestedAt": requestedAt,
                                  "observedAt": concurrencyTimestamp(), "systemStopObserved": true]
                capture(shortcuts, "concurrency-after-system-stop")
                try checkpoint("system-stop-sent")
            }
            let actions = try concurrencyResponse("actions-complete.json", timeout: 130)
            try require(actions["status"] as? String == "ACTIONS_COMPLETED",
                        "The real native invocation receipts did not satisfy this scenario.")
            record["actualActionCompletion"] = actions

            mini.activate()
            let afterPID = try observedConcurrencyPID("before-owner-callback")
            try require(afterPID == ownerPID, "The original MiniApps process did not survive all three actions.")
            try require(wait(15) {
                status.exists && self.stateFields(status.label)["Challenge"] == challenge &&
                self.stateFields(status.label)["Counter"] == "0"
            }, "The original window did not retain its own zero counter and prepared challenge.")
            let run = mini.buttons["Run all five runtimes"].firstMatch
            try tap(run, "Execute the original owner's real foreground callback after the system actions.")
            try require(wait(90) {
                status.exists && self.stateFields(status.label)["Challenge"] == challenge &&
                self.stateFields(status.label)["Counter"] == "1" && run.isEnabled
            }, "The surviving owner did not complete its actual five-runtime callback.")
            record["ownerProcessIDAfter"] = try observedConcurrencyPID("after-owner-callback")
            try require(record["ownerProcessIDAfter"] as? Int == ownerPID,
                        "The owner callback replaced the process instead of using the surviving owner.")
            try require(ownerWindowLabel.label == "Owner window: " + ownerWindowID,
                        "The foreground callback came from a replacement owner window.")
            record["ownerCallbackObserved"] = true
            record["visibleOwnerAfter"] = status.label
            capture(mini, "concurrency-owner-callback")
            try checkpoint("owner-after")
            let complete = try response("completion.json", timeout: 25)
            try require(complete["status"] as? String == "EXECUTED_PASS",
                        "The observer rejected owner isolation or a changed native terminal receipt.")
            record["observerCompletion"] = complete
            record["status"] = "EXECUTED_PASS"
        } catch let skipped as XCTSkip {
            record["status"] = "BLOCKED"
            record["reason"] = String(describing: skipped)
            throw skipped
        } catch {
            record["status"] = "FAILED"
            record["reason"] = String(describing: error)
            throw error
        }
    }

    private func configureConcurrencyShortcut(_ spec: [String: Any], identity: [String: Any]) throws {
        try createSystemShortcut("Create one actual saved concurrency Shortcut.")
        let search = try findShortcutActionSearch("Find the actual MiniApps system action.")
        search.typeText("Hanlin MiniApps")
        let app = shortcuts.staticTexts["Hanlin MiniApps"].firstMatch
        try require(app.waitForExistence(timeout: bounded(15)),
                    "The current MiniApps application is absent from the functioning gallery.")
        try tap(app, "Open the shipping MiniApps indexed actions.")
        try tap(shortcuts.staticTexts["Run MiniApp Action"].firstMatch,
                "The shipping Run MiniApp Action is absent from Shortcuts.")
        try tap(firstButton(shortcuts, ["Action", "Script Action"]), "Select the current installed action entity.")
        try tap(shortcuts.staticTexts[try string(identity, "actionDisplayName")].firstMatch,
                "The current NativeScript surface action is missing from the real entity picker.")
        if shortcuts.buttons["Show More"].firstMatch.exists { shortcuts.buttons["Show More"].firstMatch.tap() }
        try tap(shortcuts.buttons["Input Type"].firstMatch, "Choose the actual dictionary input mode.")
        try tap(shortcuts.staticTexts["Dictionary or List (JSON)"].firstMatch, "Choose typed JSON input.")
        let input = try XCTUnwrap(spec["configuredInput"] as? [String: Any])
        try fillShortcutParameter("Input", value: jsonString(input))
        let mode = try shortcutModeSwitch()
        let backgroundDefault = try observedSwitchValue(mode)
        try require(backgroundDefault == false,
                    "Each new concurrent action must retain the actual background default.")
        let longRunning = shortcuts.switches["Allow Long Running"].firstMatch
        try require(longRunning.waitForExistence(timeout: bounded(10)),
                    "The declared Allow Long Running system parameter is not observable.")
        let longRunningDefault = try observedSwitchValue(longRunning)
        try require(longRunningDefault == false,
                    "A new action has an unexpected long-running default.")
        try tap(longRunning, "Enable the existing original long-running progress route.")
        let selectedLongRunning = try observedSwitchValue(longRunning)
        try require(selectedLongRunning == true,
                    "The actual system long-running selection did not change.")
        let selectedBackgroundMode = try observedSwitchValue(mode)
        try require(selectedBackgroundMode == false,
                    "Long-running selection unexpectedly changed Open When Run.")
        let shortcutName = try string(spec, "savedShortcutName")
        try renameShortcut(shortcutName)
        try tap(firstButton(shortcuts, ["Done"]), "Save the actual configured system Shortcut.")
        let saved = shortcuts.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", shortcutName)).firstMatch
        try require(saved.waitForExistence(timeout: bounded(15)),
                    "The configured Shortcut was not actually saved in the system collection.")
        let token = try string(spec, "token")
        capture(shortcuts, "saved-concurrency-" + token)
    }

    private func concurrencyResponse(_ filename: String, timeout: TimeInterval) throws -> [String: Any] {
        let directory = try XCTUnwrap(runDirectory)
        let file = directory.appendingPathComponent(filename)
        let end = Date().addingTimeInterval(bounded(timeout))
        while Date() < end {
            try require(mini.state != .runningForeground,
                        "A background concurrency action presented the MiniApps application.")
            if FileManager.default.fileExists(atPath: file.path) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return try response(filename, timeout: 1)
    }

    private func observedConcurrencyPID(_ label: String) throws -> Int {
        let header = String(mini.debugDescription.split(separator: "\n", maxSplits: 1).first ?? "")
        let pattern = try NSRegularExpression(pattern: "^Attributes: Application, .*?, pid: ([0-9]+),")
        let match = try XCTUnwrap(pattern.firstMatch(
            in: header, range: NSRange(header.startIndex..<header.endIndex, in: header)
        ), "The actual public accessibility snapshot must identify the owner process.")
        let range = try XCTUnwrap(Range(match.range(at: 1), in: header))
        let process = try XCTUnwrap(Int(header[range]))
        try require(process > 0, "The actual owner PID must be positive.")
        let attachment = XCTAttachment(string: header)
        attachment.name = "concurrency-owner-process-" + label
        attachment.lifetime = .keepAlways
        add(attachment)
        return process
    }

    private func concurrencyTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    // Additive local Studio acceptance. Every project write below is a real
    // shipping gallery/editor action; the companion observer is read-only.
    private enum StudioExample: String {
        case expoHello = "expo-hello-world"
        case departureBudget = "sdk-only-departure-budget"
        case nativeHello = "nativescript-hello-world"
        case tableShare = "sdk-only-table-share"
        case imageDrawing = "nativescript-image-drawing"

        var engine: String {
            self == .expoHello || self == .departureBudget ? "expo" : "nativescript"
        }
        var sourceFile: String { engine == "expo" ? "App.tsx" : "index.ts" }
        var originalHeading: String {
            switch self {
            case .expoHello: "Hello from Expo!"
            case .departureBudget: "Departure Budget"
            case .nativeHello: "Hello from NativeScript!"
            case .tableShare: "Table Share"
            case .imageDrawing: "Native image drawing"
            }
        }
        var before: String {
            switch self {
            case .expoHello, .nativeHello: "Button taps: 0"
            case .departureBudget: "55 minutes reserved before the target"
            case .tableShare: "3 people pay $35.42 each."
            case .imageDrawing: "0° clockwise • 8 invalid inputs rejected"
            }
        }
        var after: String {
            switch self {
            case .expoHello, .nativeHello: "Button taps: 1"
            case .departureBudget: "35 minutes reserved before the target"
            case .tableShare: "2 pay $26.57; 2 pay $26.56."
            case .imageDrawing: "180° clockwise • 8 invalid inputs rejected"
            }
        }
    }

    func testStudioExpoHelloWorldCopiesEditsBuildsInstallsAndRuns() throws {
        try observeStudioGallery(.expoHello)
    }
    func testStudioDepartureBudgetCopiesEditsBuildsInstallsAndRuns() throws {
        try observeStudioGallery(.departureBudget)
    }
    func testStudioNativeScriptHelloWorldCopiesEditsBuildsInstallsAndRuns() throws {
        try observeStudioGallery(.nativeHello)
    }
    func testStudioTableShareCopiesEditsBuildsInstallsAndRuns() throws {
        try observeStudioGallery(.tableShare)
    }
    func testStudioNativeImageDrawingCopiesEditsBuildsInstallsAndRuns() throws {
        try observeStudioGallery(.imageDrawing)
    }

    private func observeStudioGallery(_ example: StudioExample) throws {
        continueAfterFailure = false
        executionTimeAllowance = 1200
        deadline = Date().addingTimeInterval(1140)
        let runID = UUID().uuidString.lowercased()
        let marker = "שלום Studio " + runID.prefix(8)
        let packageTitle = "Studio " + example.rawValue + " " + runID.prefix(8)
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": example.engine, "surface": "studioGallery",
                  "exampleID": example.rawValue, "marker": marker, "packageTitle": packageTitle,
                  "status": "RUNNING", "test": name, "startedAt": timestamp(), "phase": "preparing"]
        try checkpoint("preparing")
        defer {
            capture(mini, "studio-final-app")
            record["finishedAt"] = timestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.terminate()
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            let studio = mini.buttons["miniapps-open-studio"].firstMatch
            try require(studio.waitForExistence(timeout: bounded(60)), "The shipping MiniApps catalog has no Developer Studio entry.")
            try tap(studio, "Open Developer Studio from the standalone MiniApps catalog.")
            try require(mini.descendants(matching: .any)["miniapps-studio"].firstMatch.waitForExistence(timeout: bounded(20)),
                        "The shipping Developer Studio screen did not open.")
            try tap(mini.buttons["On this device"].firstMatch, "Open the actual local project library.")
            try openStudioGallery(example)
            record["galleryLoaded"] = true
            capture(mini, "studio-gallery")
            try checkpoint("gallery-ready")
            let admitted = try response("identity.json", timeout: 45)
            try require(admitted["status"] as? String == "READY" && admitted["exampleID"] as? String == example.rawValue,
                        "The observer must bind the app's actual shipped SDK and selected example.")

            try copyStudioExample(example)
            record["copyOneObserved"] = true
            try checkpoint("copy-one")
            let first = try response("studio-copy-one.json", timeout: 30)
            let firstNames = try XCTUnwrap(first["projectNames"] as? [String])
            try require(first["status"] as? String == "READY" && firstNames.count == 1,
                        "Exactly one real independent copy must be observed.")
            let projectName = firstNames[0]
            try openStudioGallery(example)
            try copyStudioExample(example)
            record["copyTwoObserved"] = true
            try checkpoint("copy-two")
            let second = try response("studio-copy-two.json", timeout: 30)
            let projectNames = try XCTUnwrap(second["projectNames"] as? [String])
            try require(second["status"] as? String == "READY" && projectNames.count == 2 &&
                        projectNames[0] == projectName && projectNames[1] != projectName,
                        "The gallery must create two distinct original project copies.")
            record["projectNames"] = projectNames
            capture(mini, "studio-two-project-copies")
            let row = mini.descendants(matching: .any).matching(NSPredicate(format: "label == %@", projectName)).firstMatch
            try reveal(row, in: mini.collectionViews.firstMatch, message: "The first actual gallery copy is not visible in My Projects.")
            try tap(row, "Open the first independently copied project in the original editor.")
            try selectStudioFile(example.sourceFile)
            let editor = mini.textViews["miniapps-studio-editor"].firstMatch
            let original = try XCTUnwrap(editor.value as? String)
            try require(original.components(separatedBy: example.originalHeading).count == 2,
                        "The original gallery heading must occur exactly once in the editable source.")
            try replaceStudioEditorText(original.replacingOccurrences(of: example.originalHeading, with: marker))
            try selectStudioFile("script.json")
            let manifestText = try XCTUnwrap(editor.value as? String)
            var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(manifestText.utf8)) as? [String: Any])
            manifest["name"] = packageTitle
            let editedManifest = String(decoding: try JSONSerialization.data(withJSONObject: manifest,
                options: [.prettyPrinted, .sortedKeys]), as: UTF8.self) + "\n"
            try replaceStudioEditorText(editedManifest)
            record["editorReplacementObserved"] = true
            capture(mini, "studio-edited-source")
            try checkpoint("source-edited")
            let edited = try response("studio-source.json", timeout: 30)
            try require(edited["status"] as? String == "READY",
                        "The actual autosaved source, untouched second copy and shipped SDK must agree.")

            try tap(mini.buttons["miniapps-studio-validate"].firstMatch, "Validate the edited source with the original shipped compiler.")
            record["validatePressed"] = true
            let success = mini.buttons["Validation succeeded"].firstMatch
            let editorError = mini.alerts["Editor"].firstMatch
            try require(wait(240) { success.exists || editorError.exists }, "Original source validation produced no concrete UI outcome.")
            try require(success.exists && !editorError.exists, "The original source validator rejected the edited gallery project.")
            record["validationSucceededObserved"] = true
            capture(mini, "studio-original-validation")
            try tap(mini.buttons["miniapps-studio-build-install"].firstMatch, "Build and install through the shipping Studio action.")
            record["buildPressed"] = true
            let install = mini.buttons["hanlin-package-install"].firstMatch
            let importError = mini.descendants(matching: .any)["hanlin-import-error-message"].firstMatch
            let diagnostics = mini.descendants(matching: .any)["hanlin-import-diagnostics-sheet"].firstMatch
            try require(wait(360) { install.exists || importError.exists || diagnostics.exists || editorError.exists },
                        "The original Studio build did not reach a real import preview or error.")
            capture(mini, "studio-original-build-preview")
            try require(install.exists && !importError.exists && !diagnostics.exists && !editorError.exists,
                        "The actual compiler/importer rejected the newly authored project.")
            record["importPreviewObserved"] = true
            try checkpoint("build-preview")
            let built = try response("studio-build.json", timeout: 45)
            try require(built["status"] as? String == "READY" && built["independentCopyUnchanged"] as? Bool == true &&
                        built["shippedExampleUnchanged"] as? Bool == true,
                        "The actual compiled archive must bind the edited copy and unchanged original SDK.")
            try tap(install, "Install the real Studio-produced archive through the original import preview.")
            record["installPressed"] = true
            try require(wait(90) { !install.exists || importError.exists }, "The original installer did not finish.")
            try require(!importError.exists, "The real Studio package installation failed.")
            try tap(mini.buttons["hanlin-package-import-done"].firstMatch, "Return from the original import preview to Studio.")
            try tap(mini.navigationBars.buttons["My Projects"].firstMatch, "Return from the editor to the actual local project library.")
            try tap(mini.navigationBars["My Projects"].buttons["BackButton"].firstMatch, "Return to the shipping Studio root.")
            try tap(mini.navigationBars["Developer Studio"].buttons["Done"].firstMatch, "Close Studio and return to the standalone catalog.")
            let card = mini.buttons["hanlin-package-card-" + packageTitle].firstMatch
            try require(card.waitForExistence(timeout: bounded(30)), "The newly named Studio package is absent from the real catalog.")
            record["catalogCardObserved"] = true
            try reveal(card, in: mini.collectionViews.firstMatch, message: "The actual Studio-installed catalog card is not tappable.")
            try tap(card, "Launch the newly built MiniApp through its original installed card.")
            try observeStudioRuntime(example, marker: marker)
            try checkpoint("runtime-observed")
            let completion = try response("completion.json", timeout: 60)
            try require(completion["status"] as? String == "EXECUTED_PASS" &&
                        completion["independentCopyUnchanged"] as? Bool == true &&
                        completion["shippedExampleUnchanged"] as? Bool == true,
                        "The current installed source and actual runtime callback did not match this Studio build.")
            record["observerCompletion"] = completion
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"
            record["reason"] = String(describing: error)
            throw error
        }
    }

    private func openStudioGallery(_ example: StudioExample) throws {
        try tap(mini.buttons["miniapps-studio-add"].firstMatch, "Open the original local library's create/import menu.")
        try tap(mini.buttons["Gallery"].firstMatch, "Open the actual SDK-backed Example Gallery.")
        try require(mini.buttons["miniapps-gallery-" + example.rawValue].firstMatch.waitForExistence(timeout: bounded(120)),
                    "The actual shipped SDK example did not appear in the gallery.")
    }

    private func copyStudioExample(_ example: StudioExample) throws {
        try tap(mini.buttons["miniapps-gallery-" + example.rawValue].firstMatch,
                "Copy the selected example through the real gallery action.")
        let copied = mini.alerts["Project copied"].firstMatch
        try require(copied.waitForExistence(timeout: bounded(30)), "The original project-copy operation did not succeed.")
        try tap(copied.buttons["Open library"].firstMatch, "Return to My Projects after the actual copy.")
        try require(mini.navigationBars["My Projects"].waitForExistence(timeout: bounded(20)),
                    "The actual local library did not reopen after copying.")
    }

    private func selectStudioFile(_ path: String) throws {
        let files = mini.buttons["miniapps-studio-files"].firstMatch
        try require(files.waitForExistence(timeout: bounded(25)), "The original project editor did not open.")
        try tap(files, "Open the original editor's actual source-file menu.")
        try tap(mini.buttons[path].firstMatch, "Select the actual project file " + path + ".")
        try require(mini.textViews["miniapps-studio-editor"].firstMatch.waitForExistence(timeout: bounded(15)),
                    "The original native source editor is unavailable.")
    }

    private func replaceStudioEditorText(_ value: String) throws {
        let editor = mini.textViews["miniapps-studio-editor"].firstMatch
        try tap(editor, "Focus the original native source text view.")
        editor.press(forDuration: 1.2)
        let selectAll = mini.menuItems["Select All"].firstMatch
        let selectAllButton = mini.buttons["Select All"].firstMatch
        try require(wait(10) { selectAll.exists || selectAllButton.exists },
                    "The native text-selection menu did not expose Select All.")
        try tap(selectAll.exists ? selectAll : selectAllButton, "Select all current source through the actual editor menu.")
        editor.typeText(value)
        try require(wait(15) { editor.value as? String == value },
                    "The native editor did not retain the exact typed source, including Hebrew text.")
    }

    private func studioRuntimeText(_ value: String) -> XCUIElement {
        mini.staticTexts.matching(NSPredicate(format: "label == %@", value)).firstMatch
    }

    private func revealStudioRuntime(_ element: XCUIElement, towardEnd: Bool) throws {
        try require(element.waitForExistence(timeout: bounded(30)), "The original runtime did not expose the expected control or result.")
        for _ in 0..<8 {
            if element.isHittable { break }
            if towardEnd { mini.swipeUp() } else { mini.swipeDown() }
        }
        try require(element.exists && element.isHittable, "The actual original runtime control or result is not visible.")
    }

    private func observeStudioRuntime(_ example: StudioExample, marker: String) throws {
        let heading = studioRuntimeText(marker)
        try require(heading.waitForExistence(timeout: bounded(45)), "The installed runtime did not render the actual edited Hebrew heading.")
        record["runtimeHeadingObserved"] = true
        record["runtimeProcessID"] = try observedConcurrencyPID("studio-runtime")
        let before = studioRuntimeText(example.before)
        try revealStudioRuntime(before, towardEnd: true)
        record["runtimeBefore"] = example.before
        if example == .imageDrawing {
            let image = mini.descendants(matching: .any)["miniapps-drawing-image"].firstMatch
            try require(image.exists && image.isHittable && image.frame.width > 0 && image.frame.height > 0,
                        "The original native image view did not display a drawable image region.")
            record["nativeImageObserved"] = true
            var angles = [0]
            capture(mini, "studio-drawing-0")
            for angle in [45, 90, 180] {
                try tap(mini.buttons["miniapps-drawing-rotate"].firstMatch, "Run the original native Rotate image callback.")
                try require(studioRuntimeText("\(angle)° clockwise • 8 invalid inputs rejected").waitForExistence(timeout: bounded(15)),
                            "The actual native drawing callback did not show the next angle and original guard result.")
                angles.append(angle)
                capture(mini, "studio-drawing-" + String(angle))
            }
            record["drawingAnglesObserved"] = angles
        } else {
            capture(mini, "studio-runtime-before")
            let title = example == .departureBudget ? "Local" : example == .tableShare ? "+" : "Say hello"
            let action = mini.buttons[title].firstMatch
            try revealStudioRuntime(action, towardEnd: example == .departureBudget)
            try tap(action, "Run the original installed example's native callback.")
            try revealStudioRuntime(studioRuntimeText(example.after), towardEnd: example == .tableShare)
            capture(mini, "studio-runtime-after")
        }
        try require(studioRuntimeText(example.after).exists && heading.exists && mini.state == .runningForeground,
                    "The original runtime did not retain its edited heading and actual callback result.")
        let finalProcessID = try observedConcurrencyPID("studio-after")
        try require(finalProcessID == record["runtimeProcessID"] as? Int,
                    "The actual MiniApps process changed across the original runtime callback.")
        record["runtimeAfter"] = example.after
        record["runtimeActionObserved"] = true
    }


    // Additive original Studio editor acceptance. Only real UI actions write
    // project source, preferences, journals and exported logs. The companion
    // reads those outcomes; ordinary Files input staging is separately bound.
    private enum StudioEditorScenario: String {
        case files, assistance, conflict
        case importSource = "import"
    }

    func testStudioExpoCreatesMovesStylesAndReopensSource() throws {
        try observeStudioEditor(.files, engine: .expo)
    }
    func testStudioNativeScriptCreatesMovesStylesAndReopensSource() throws {
        try observeStudioEditor(.files, engine: .nativescript)
    }
    func testStudioOriginalTypeScriptHelpPreferencesAndLiveLogExport() throws {
        try observeStudioEditor(.assistance, engine: .expo)
    }
    func testStudioImportsActualFilesSourceAndReopensIndependentEdit() throws {
        try observeStudioEditor(.importSource, engine: .expo)
    }
    func testStudioTwoRealWindowsConflictReloadAndRecoverSeparateCopy() throws {
        try observeStudioEditor(.conflict, engine: .nativescript)
    }

    private func observeStudioEditor(_ scenario: StudioEditorScenario, engine: Engine) throws {
        continueAfterFailure = false
        executionTimeAllowance = 1200
        deadline = Date().addingTimeInterval(1140)
        let runID = UUID().uuidString.lowercased()
        let example: StudioExample = engine == .expo ? .expoHello : .nativeHello
        let marker = "שלום Editor " + runID.prefix(8)
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root
        runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": engine.rawValue, "surface": "studioEditor",
                  "scenario": scenario.rawValue, "exampleID": example.rawValue, "marker": marker,
                  "status": "RUNNING", "test": name, "startedAt": timestamp(), "phase": "preparing"]
        try checkpoint("preparing")
        defer {
            capture(mini, "studio-editor-final-app")
            record["finishedAt"] = timestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
            if scenario == .conflict { try studioEnableWindowedApps() }
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try studioOpenLocalLibrary(in: mini)
            record["processID"] = try observedConcurrencyPID("studio-editor-initial")
            try openStudioGallery(example)
            record["galleryLoaded"] = true
            _ = try studioEditorCheckpoint("gallery-ready")
            if scenario == .importSource {
                let input = try studioEditorCheckpoint("import-input-ready", timeout: 90)
                try tap(mini.navigationBars["Example Gallery"].buttons["Done"].firstMatch,
                        "Close the actual gallery before selecting a normal Files source folder.")
                try studioImportFolder(try string(input, "folder"), project: try string(input, "projectFolder"))
            } else {
                try copyStudioExample(example)
            }
            record["copyObserved"] = true
            let copied = try studioEditorCheckpoint("copy-ready")
            let project = try string(copied, "projectName")
            try studioOpenProject(project, in: mini)
            switch scenario {
            case .files:
                try studioFilesCase(project, marker: marker, runID: runID)
            case .assistance:
                try studioAssistanceCase(project, marker: marker, runID: runID)
            case .importSource:
                try selectStudioFile(example.sourceFile)
                let editor = mini.textViews["miniapps-studio-editor"].firstMatch
                let original = try XCTUnwrap(editor.value as? String)
                try require(original.components(separatedBy: example.originalHeading).count == 2,
                            "The actual imported original source heading is absent or ambiguous.")
                try studioReplaceText(editor, with: original.replacingOccurrences(of: example.originalHeading, with: marker))
                try studioSave(in: mini)
                record["importEditObserved"] = true
                _ = try studioEditorCheckpoint("source-edited")
                try studioRestartAndOpen(project, file: example.sourceFile)
            case .conflict:
                try studioConflictCase(project, marker: marker, runID: runID)
            }
            record["reopenedSourceObserved"] = true
            record["reopenedProcessID"] = try observedConcurrencyPID("studio-editor-reopened")
            capture(mini, "studio-editor-reopened")
            let completion = try studioEditorCheckpoint("reopened", timeout: 90)
            try require(completion["status"] as? String == "EXECUTED_PASS" &&
                        completion["scenario"] as? String == scenario.rawValue,
                        "The original Studio UI/files/current SDK observer did not confirm this actual case.")
            record["observerCompletion"] = completion
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"
            record["reason"] = String(describing: error)
            throw error
        }
    }

    private func studioEditorCheckpoint(_ phase: String, timeout: TimeInterval = 45) throws -> [String: Any] {
        record["currentProcessID"] = try observedConcurrencyPID("studio-editor-" + phase)
        capture(mini, "studio-editor-phase-" + phase)
        try checkpoint(phase)
        let filename = phase == "gallery-ready" ? "identity.json" : phase == "reopened" ? "completion.json" : "editor-" + phase + ".json"
        let value = try response(filename, timeout: timeout)
        try require(value["runID"] as? String == record["runID"] as? String &&
                    value["status"] as? String == (phase == "reopened" ? "EXECUTED_PASS" : "READY"),
                    "The read-only Studio observer did not admit the exact UI phase " + phase + ".")
        return value
    }

    private func studioOpenLocalLibrary(in container: XCUIElement) throws {
        let entry = container.buttons["miniapps-open-studio"].firstMatch
        try require(entry.waitForExistence(timeout: bounded(60)), "The actual app window has no Developer Studio entry.")
        try tap(entry, "Open Studio in this actual app window.")
        try tap(container.buttons["On this device"].firstMatch, "Open this window's local project library.")
        try require(container.navigationBars["My Projects"].waitForExistence(timeout: bounded(30)),
                    "The actual local library did not open in this window.")
    }

    private func studioOpenProject(_ project: String, in container: XCUIElement) throws {
        for component in project.split(separator: "/").map(String.init) {
            let row = container.descendants(matching: .any).matching(NSPredicate(format: "label == %@", component)).firstMatch
            try reveal(row, in: container, message: "The real project/folder is absent: " + component)
            try tap(row, "Open the actual source path component " + component + ".")
        }
        try require(container.textViews["miniapps-studio-editor"].firstMatch.waitForExistence(timeout: bounded(30)),
                    "The real project source editor did not open.")
    }

    private func studioOptions(_ action: String, in container: XCUIElement) throws {
        try tap(container.buttons["miniapps-studio-editor-options"].firstMatch, "Open this original editor's options.")
        try tap(mini.buttons[action].firstMatch, "Use the original editor action " + action + ".")
    }

    private func studioSave(in container: XCUIElement) throws {
        try studioOptions("Save", in: container)
        try require(!mini.alerts["Editor"].firstMatch.exists, "The actual editor refused its source save.")
    }

    private func studioReplaceText(_ field: XCUIElement, with value: String, clearingObservedValue: Bool = false) throws {
        try tap(field, "Focus the actual native source/path field.")
        if clearingObservedValue {
            let original = try XCTUnwrap(field.value as? String, "The actual path field has no readable current value.")
            if !original.isEmpty {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count))
                let remaining = try XCTUnwrap(field.value as? String, "The actual path field has no readable value after backward deletion.")
                try require(remaining.count <= original.count && original.hasSuffix(remaining),
                            "The path field changed beyond the original suffix during clearing.")
                for _ in remaining {
                    try require(Date() < deadline, "The original Studio case deadline expired while clearing its observed path suffix.")
                    field.typeKey(XCUIKeyboardKey.forwardDelete, modifierFlags: [])
                }
            }
            try require(field.value as? String == "", "The actual path field did not become empty before replacement.")
        } else if let original = field.value as? String, !original.isEmpty {
            field.press(forDuration: 1.2)
            var selectAll = mini.menuItems["Select All"].firstMatch
            if !selectAll.exists { selectAll = mini.buttons["Select All"].firstMatch }
            if !selectAll.exists {
                let select = firstButton(mini, ["Select"])
                if select.exists && select.isHittable { select.tap() }
                selectAll = mini.menuItems["Select All"].firstMatch
                if !selectAll.exists { selectAll = mini.buttons["Select All"].firstMatch }
            }
            try tap(selectAll, "Select the exact current text using the native selection menu.")
        }
        field.typeText(value)
        try require(wait(15) { field.value as? String == value }, "The real native editor/path field did not retain the exact typed bytes.")
    }

    private func studioPathAlert(_ title: String, field: String, value: String) throws {
        let alert = mini.alerts[title].firstMatch
        try require(alert.waitForExistence(timeout: bounded(15)), "The actual source/path alert did not open.")
        try studioReplaceText(alert.textFields[field].firstMatch, with: value, clearingObservedValue: true)
        try tap(alert.buttons["Save"].firstMatch, "Commit the actual path operation through the shipping UI.")
        try require(wait(20) { !alert.exists }, "The actual path operation did not complete.")
        try require(!mini.alerts["Project unavailable"].exists && !mini.alerts["Editor"].exists,
                    "The original source/path operation reported a real error.")
    }

    private func studioNewSource(_ path: String, text: String, in container: XCUIElement) throws {
        try studioOptions("New source file", in: container)
        try studioPathAlert("New source file", field: "Relative path", value: path)
        let editor = container.textViews["miniapps-studio-editor"].firstMatch
        try require(wait(15) { editor.value as? String == "" }, "A fresh source file must start empty.")
        try studioReplaceText(editor, with: text)
        try studioSave(in: container)
    }

    private func studioSource(_ marker: String, _ version: String) throws -> String {
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: marker + " " + version,
                              options: [.fragmentsAllowed]), as: UTF8.self)
        return "export const marker = " + literal + ";\n"
    }

    private func studioFilesCase(_ project: String, marker: String, runID: String) throws {
        let suffix = String(runID.prefix(8))
        let created = "notes/first-" + suffix + ".ts"
        let moved = "notes/nested/moved-" + suffix + ".ts"
        let folder = "Libraries-" + suffix + "/Nested"
        try studioNewSource(created, text: studioSource(marker, "created"), in: mini)
        record["createdPath"] = created; record["fileCreateObserved"] = true
        _ = try studioEditorCheckpoint("file-created")
        try studioOptions("Rename or move file", in: mini)
        try studioPathAlert("Rename or move", field: "Relative path", value: moved)
        try studioReplaceText(mini.textViews["miniapps-studio-editor"].firstMatch,
                              with: studioSource(marker, "after move"))
        try studioSave(in: mini)
        record["movedPath"] = moved; record["fileMoveObserved"] = true
        _ = try studioEditorCheckpoint("file-moved")
        try tap(mini.navigationBars.buttons["My Projects"].firstMatch, "Return to the actual source library.")
        try tap(mini.buttons["miniapps-studio-add"].firstMatch, "Open the original library menu.")
        try tap(mini.buttons["New folder"].firstMatch, "Create nested folders through the real library action.")
        try studioPathAlert("New folder", field: "Path in this library", value: folder)
        record["folderCreateObserved"] = true
        _ = try studioEditorCheckpoint("folders-created")
        try studioProjectContext(project, action: "Icon and color", in: mini)
        try studioReplaceText(mini.textFields["Symbol name"].firstMatch, with: "star.fill")
        try tap(mini.buttons["Color"].firstMatch, "Choose the actual folder color.")
        try tap(mini.buttons["Purple"].firstMatch, "Select Purple in the original folder appearance picker.")
        try tap(mini.navigationBars["Folder appearance"].buttons["Save"].firstMatch, "Save original folder appearance metadata.")
        record["styleSaveObserved"] = true
        _ = try studioEditorCheckpoint("style-saved")
        try studioProjectContext(project, action: "Rename or move", in: mini)
        let destination = folder + "/" + project
        try studioPathAlert("Rename or move", field: "Path in this library", value: destination)
        record["movedProject"] = destination; record["projectMoveObserved"] = true
        _ = try studioEditorCheckpoint("project-moved")
        mini.terminate(); mini.launch()
        try studioOpenLocalLibrary(in: mini)
        for component in folder.split(separator: "/").map(String.init) {
            try tap(mini.buttons[component].firstMatch, "Reopen the actual moved library folder.")
        }
        try studioProjectContext(project, action: "Icon and color", in: mini)
        let symbol = try XCTUnwrap(mini.textFields["Symbol name"].firstMatch.value as? String)
        let purple = mini.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value == %@", "Purple", "Purple")).firstMatch
        try require(symbol == "star.fill" && purple.exists, "Actual saved symbol/color did not survive restarting the app.")
        record["reopenedSymbolObserved"] = symbol; record["reopenedColorObserved"] = "purple"
        capture(mini, "studio-editor-reopened-appearance")
        try tap(mini.navigationBars["Folder appearance"].buttons["Cancel"].firstMatch, "Close the read-only appearance inspection.")
        try studioOpenProject(project, in: mini)
        try selectStudioFile(moved)
        let expected = try studioSource(marker, "after move")
        try require(mini.textViews["miniapps-studio-editor"].firstMatch.value as? String == expected,
                    "Moved source bytes did not survive reopening through the actual editor.")
    }

    private func studioProjectContext(_ project: String, action: String, in container: XCUIElement) throws {
        let row = container.descendants(matching: .any).matching(NSPredicate(format: "label == %@", project)).firstMatch
        try reveal(row, in: container, message: "The original project row is unavailable for its actual context menu.")
        row.press(forDuration: 1.2)
        try tap(mini.buttons[action].firstMatch, "Use the shipping project context action " + action + ".")
    }

    private func studioRestartAndOpen(_ project: String, file: String) throws {
        let before = try observedConcurrencyPID("studio-editor-before-restart")
        mini.terminate(); mini.launch()
        try studioOpenLocalLibrary(in: mini)
        try studioOpenProject(project, in: mini)
        try selectStudioFile(file)
        let after = try observedConcurrencyPID("studio-editor-after-restart")
        try require(after != before, "The app did not actually restart before reopening source.")
    }

    private func studioAssistanceCase(_ project: String, marker: String, runID: String) throws {
        let path = "notes/assistance-" + runID.prefix(8) + ".ts"
        let literal = String(decoding: try JSONSerialization.data(withJSONObject: marker, options: [.fragmentsAllowed]), as: UTF8.self)
        let prefix = "const greeting = " + literal + ";\ngreeting.toU"
        try studioNewSource(String(path), text: prefix, in: mini)
        let editor = mini.textViews["miniapps-studio-editor"].firstMatch
        let completion = mini.buttons["toUpperCase"].firstMatch
        try require(completion.waitForExistence(timeout: bounded(90)), "The original TypeScript service produced no toUpperCase completion.")
        capture(mini, "studio-editor-completion")
        try tap(mini.buttons["Documentation for toUpperCase"].firstMatch, "Request actual original completion documentation.")
        try require(mini.buttons["Open API reference"].firstMatch.waitForExistence(timeout: bounded(60)),
                    "The original completion details did not expose documentation/reference UI.")
        capture(mini, "studio-editor-documentation")
        record["inlineDocumentationObserved"] = true
        try tap(completion, "Apply the actual TypeScript completion to the native editor.")
        let completedPrefix = "const greeting = " + literal + ";\ngreeting.toUpperCase"
        try require(wait(15) { editor.value as? String == completedPrefix },
                    "The completion did not replace only the actual typed prefix.")
        record["completionApplied"] = true
        record["completionIntermediateSource"] = editor.value as? String
        editor.typeText("();\ngreeting.substring(")
        let parameterSource = completedPrefix + "();\ngreeting.substring("
        try require(wait(15) { editor.value as? String == parameterSource }, "The actual parameter-help source is different.")
        let signature = mini.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@", "substring", "start", "number")).firstMatch
        try require(signature.waitForExistence(timeout: bounded(90)), "The original TypeScript parameter signature did not appear.")
        capture(mini, "studio-editor-parameter-hint")
        record["parameterHintObserved"] = true; record["parameterIntermediateSource"] = editor.value as? String
        try tap(mini.buttons["Open API reference"].firstMatch, "Open the original SDK reference through its shipping Link.")
        try require(wait(60) { safari.state == .runningForeground }, "The actual system browser did not open the reference.")
        let address = safari.textFields.firstMatch
        try tap(address, "Read the actual browser address for the opened API reference.")
        let actualAddress = try XCTUnwrap(address.value as? String)
        let url = try XCTUnwrap(URL(string: actualAddress))
        try require(url.scheme == "https" && url.host == "docs.expo.dev", "The real reference opened another destination.")
        record["referenceOpened"] = true; record["referenceURL"] = "https://docs.expo.dev/"
        record["referenceAddressObserved"] = actualAddress
        record["referenceProcessID"] = try studioObservedPID(safari)
        capture(safari, "studio-editor-reference")
        mini.activate()
        let finished = completedPrefix + "();\ngreeting.substring(0, 2);\n"
        try studioReplaceText(editor, with: finished)
        try studioSave(in: mini)
        _ = try studioEditorCheckpoint("assistance-observed")

        try studioOptions("Choose font", in: mini)
        let fontSearch = mini.searchFields.firstMatch
        if fontSearch.exists { try tap(fontSearch, "Find the actual installed font family."); fontSearch.typeText("Courier New") }
        let family = mini.staticTexts["Courier New"].firstMatch
        try reveal(family, in: mini, message: "The actual UIFont picker does not offer Courier New.")
        capture(mini, "studio-editor-font-picker")
        try tap(family, "Open the original installed font family's faces.")
        let regular = mini.staticTexts["Regular"].firstMatch
        try require(regular.waitForExistence(timeout: bounded(20)), "The actual font picker did not expose the Regular face.")
        capture(mini, "studio-editor-font-face")
        try tap(regular, "Select the real Courier New Regular font face.")
        try require(mini.buttons["miniapps-studio-editor-options"].firstMatch.waitForExistence(timeout: bounded(20)),
                    "The native font picker did not return to the original editor.")
        try studioOptions("Font size", in: mini)
        try tap(mini.buttons["22 pt"].firstMatch, "Select the real22-point editor size.")
        try tap(mini.buttons["miniapps-studio-editor-options"].firstMatch, "Open the original theme picker.")
        if !mini.buttons["Dark"].firstMatch.exists { try tap(mini.buttons["Theme"].firstMatch, "Open the Theme choices.") }
        capture(mini, "studio-editor-theme")
        try tap(mini.buttons["Dark"].firstMatch, "Select the actual Dark theme.")
        record["fontPickerObserved"] = true; record["fontFamilySelected"] = "Courier New"
        record["fontFaceSelected"] = "Regular"; record["fontSizeSelected"] = 22; record["themeSelected"] = "dark"
        _ = try studioEditorCheckpoint("preferences-saved")
        try tap(mini.navigationBars.buttons["My Projects"].firstMatch, "Return to the original local library.")
        try tap(mini.navigationBars.buttons["Developer Studio"].firstMatch, "Return to the real Studio tools.")
        try tap(mini.buttons["Live logs"].firstMatch, "Open the actual runtime log reader.")
        try tap(mini.buttons["Choose log"].firstMatch, "Choose the real Node runtime log.")
        try tap(mini.buttons["node-runtime.log"].firstMatch, "Read the original Node log file.")
        let search = mini.searchFields["Find messages"].firstMatch
        try tap(search, "Use the real live-log search field.")
        search.typeText("runtime_paths_configured")
        try require(mini.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "runtime_paths_configured")).firstMatch.waitForExistence(timeout: bounded(30)),
                    "No actual matching runtime startup message is displayed.")
        record["logSearchQuery"] = "runtime_paths_configured"; record["logSearchObserved"] = true
        capture(mini, "studio-editor-logs")
        _ = try studioEditorCheckpoint("logs-ready")
        let exportName = "studio-log-" + runID.prefix(8) + ".log"
        try studioExportLog(String(exportName))
        record["logExportObserved"] = true; record["logExportName"] = exportName
        _ = try studioEditorCheckpoint("log-exported")
        try studioRestartAndOpen(project, file: String(path))
        try require(editor.value as? String == finished, "Actual assisted source did not survive reopening.")
    }

    private func studioObservedPID(_ app: XCUIApplication) throws -> Int {
        let header = String(app.debugDescription.split(separator: "\n", maxSplits: 1).first ?? "")
        let regex = try NSRegularExpression(pattern: "^Attributes: Application, .*?, pid: ([0-9]+),")
        let match = try XCTUnwrap(regex.firstMatch(in: header, range: NSRange(header.startIndex..<header.endIndex, in: header)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: header))
        let value = try XCTUnwrap(Int(header[range]))
        try require(value > 0, "The actual app accessibility snapshot has no positive process identity.")
        return value
    }

    private func studioVisibleFilesControl(_ labels: [String], in application: XCUIApplication,
                                           buttons: Bool = false) -> XCUIElement? {
        let state = application.state
        guard state != .notRunning && state != .unknown else { return nil }
        let exact = NSPredicate(format: "label IN %@ OR identifier IN %@", labels as NSArray, labels as NSArray)
        if !buttons && labels != ["On My iPad"] {
            // Folder names belong to File View cells; their label children are not the folder action.
            let fileViews = application.collectionViews.matching(identifier: "File View")
                .allElementsBoundByAccessibilityElement.filter {
                    $0.exists && $0.isEnabled && $0.isHittable
                }
            guard fileViews.count == 1 else { return nil }
            let containerIdentifiers = labels.map { "\($0), Container" }
            let containers = fileViews[0].cells.allElementsBoundByAccessibilityElement.filter { cell in
                guard cell.exists && cell.isEnabled && cell.isHittable else { return false }
                let hasExactName = cell.staticTexts.matching(exact).allElementsBoundByAccessibilityElement
                    .contains { $0.exists && $0.isEnabled && $0.isHittable }
                return labels.contains(cell.identifier) || containerIdentifiers.contains(cell.identifier) || hasExactName
            }
            return containers.count == 1 ? containers[0] : nil
        }
        let queries = buttons ? [application.buttons] : [application.cells, application.staticTexts]
        return queries.flatMap { $0.matching(exact).allElementsBoundByAccessibilityElement }
            .first { $0.exists && $0.isEnabled && $0.isHittable }
    }

    private func studioTapFilesControl(_ labels: [String], in application: XCUIApplication,
                                       buttons: Bool = false, _ message: String) throws {
        var control: XCUIElement?
        try require(wait(12) {
            control = studioVisibleFilesControl(labels, in: application, buttons: buttons)
            return control != nil
        }, message)
        try XCTUnwrap(control).tap()
    }

    private func studioLocalFilesProvider(_ message: String) throws -> XCUIApplication {
        let candidates = [mini, files]
        for application in candidates {
            let state = application.state
            if state == .notRunning || state == .unknown { continue }
            let browse = application.buttons["Browse"].firstMatch
            if browse.exists && browse.isEnabled && browse.isHittable { browse.tap(); break }
        }
        var owner: XCUIApplication?
        var location: XCUIElement?
        let ready = wait(12) {
            for application in candidates {
                if let row = studioVisibleFilesControl(["On My iPad"], in: application) {
                    owner = application; location = row
                    return true
                }
            }
            return false
        }
        record["filesApplicationState"] = String(describing: files.state)
        if !ready && files.state != .notRunning { capture(files, "studio-files-unresolved-owner") }
        try require(ready, message)
        let application = try XCTUnwrap(owner)
        let row = try XCTUnwrap(location)
        record["filesProviderQueryBundleID"] = application === mini ? "com.itorah.hanlinminiapps" : "com.apple.DocumentsApp"
        record["filesProviderProcessID"] = try studioObservedPID(application)
        capture(application, "studio-files-presented-provider")
        try require(row.exists && row.isEnabled && row.isHittable, message)
        row.tap()
        return application
    }

    private func studioImportFolder(_ folder: String, project: String) throws {
        try tap(mini.buttons["miniapps-studio-add"].firstMatch, "Open the actual local library import action.")
        try tap(mini.buttons["Import source folder"].firstMatch, "Select a real ordinary source folder through Files.")
        let provider = try studioLocalFilesProvider("Use the actual local Files provider.")
        try studioTapFilesControl(["Hanlin MiniApps"], in: provider, "Open normal MiniApps Documents inputs.")
        try studioTapFilesControl([folder], in: provider, "Open this run's actual SDK source input folder.")
        try studioTapFilesControl([project], in: provider, "Select the original source project's folder.")
        try studioTapFilesControl(["Open", "Done"], in: provider, buttons: true, "Confirm the actual folder import.")
        try require(mini.navigationBars["My Projects"].waitForExistence(timeout: bounded(30)) &&
                    !mini.alerts["Project unavailable"].exists, "The real source-folder import failed.")
        capture(mini, "studio-editor-import-selected")
    }

    private func studioExportLog(_ filename: String) throws {
        try tap(mini.buttons["Export complete log"].firstMatch, "Export the actual complete log through its ShareLink.")
        let save = mini.buttons["Save to Files"].firstMatch
        try reveal(save, in: mini, message: "The real Share sheet offers no Save to Files action.")
        try tap(save, "Save the original log using the actual Files provider.")
        if mini.buttons["Browse"].firstMatch.exists { mini.buttons["Browse"].firstMatch.tap() }
        try tap(mini.staticTexts["On My iPad"].firstMatch, "Choose real local file storage for the log export.")
        try tap(mini.staticTexts["Hanlin MiniApps"].firstMatch, "Use the app's normal Documents export destination.")
        let name = mini.textFields.firstMatch
        try studioReplaceText(name, with: filename)
        capture(mini, "studio-editor-log-files-export")
        try tap(firstButton(mini, ["Save"]), "Save the real exported log under this fresh run's name.")
        try require(!mini.alerts.buttons["Replace"].exists, "A fresh log export must never replace an existing file.")
        try require(mini.navigationBars["Live logs"].waitForExistence(timeout: bounded(30)),
                    "The actual Files export did not return to the log reader.")
    }

    private func studioEnableWindowedApps() throws {
        settings.launch()
        let multitasking = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Multitasking & Gestures")).firstMatch
        try reveal(multitasking, in: settings, message: "The actual iPad Settings has no windowing configuration.")
        try tap(multitasking, "Open the real iPad multitasking settings.")
        let windowed = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Windowed Apps")).firstMatch
        try tap(windowed, "Enable actual Windowed Apps on this owned iPad simulator.")
        capture(settings, "studio-editor-windowing-settings")
        record["windowingSettingsProcessID"] = try studioObservedPID(settings)
        record["windowingEnabledObserved"] = true
    }

    private func studioEditorWindows() -> [XCUIElement] {
        mini.windows.allElementsBoundByAccessibilityElement.filter {
            $0.exists && $0.frame.width >= 100 && $0.frame.height > 20 &&
            $0.textViews.matching(identifier: "miniapps-studio-editor").count == 1
        }.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func studioOpenSecondWindow(project: String, file: String) throws {
        // Apple's public iPad route: Home app icon → New Window. No injected
        // scene activation, second source writer or guessed persistent AX ID.
        XCUIDevice.shared.press(.home)
        let screen = springboard.frame
        try require(screen.width > 500 && screen.height > 500, "The actual iPad Home Screen bounds are unavailable.")
        record["windowingScreenFrame"] = [Double(screen.minX), Double(screen.minY), Double(screen.width), Double(screen.height)]
        let icon = springboard.icons["Hanlin MiniApps"].firstMatch
        for _ in 0..<4 {
            if icon.exists && icon.isHittable { break }
            springboard.swipeLeft()
        }
        try require(icon.exists && icon.isHittable, "The actual installed MiniApps icon is unavailable.")
        icon.press(forDuration: 1.2)
        record["windowingSystemProcessID"] = try studioObservedPID(springboard)
        capture(springboard, "studio-editor-new-window-menu")
        try tap(springboard.buttons["New Window"].firstMatch, "Open a genuine second MiniApps scene through the system menu.")
        try require(wait(30) { mini.state == .runningForeground }, "The system did not activate the new MiniApps window.")
        let roots = mini.windows.allElementsBoundByAccessibilityElement.filter { $0.buttons["miniapps-open-studio"].firstMatch.exists }
        try require(roots.count == 1, "The actual new catalog window is absent or ambiguous.")
        let newWindow = roots[0]
        record["newWindowCreatedObserved"] = true
        try studioOpenLocalLibrary(in: newWindow)
        try studioOpenProject(project, in: newWindow)
        try studioSelectFile(file, in: newWindow)
        capture(mini, "studio-editor-before-tiling")
        try studioTile(newWindow, onLeft: false)
        let candidates = studioEditorWindows().filter { $0.frame.minX < screen.width / 2 - 20 }
        try require(candidates.count == 1, "The actual other editor window is not visible after right tiling.")
        try studioTile(candidates[0], onLeft: true)
        try require(wait(20) {
            let windows = studioEditorWindows()
            return windows.count == 2 && windows[0].frame.maxX <= windows[1].frame.minX + 2
        }, "The system did not present two independently visible tiled editor windows.")
    }

    private func studioTile(_ window: XCUIElement, onLeft: Bool) throws {
        // Standard public drag/resize gestures, based on the actual window and
        // retained screen. A native pilot must verify the OS recognizes them.
        let bounds = try XCTUnwrap(record["windowingScreenFrame"] as? [Double])
        try require(bounds.count == 4, "The actual screen bounds were not retained before opening the second window.")
        let screen = CGSize(width: CGFloat(bounds[2]), height: CGFloat(bounds[3]))
        if window.frame.width > screen.width * 0.85 {
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
            let target = mini.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screen.width * 0.68, dy: screen.height * 0.78))
            corner.press(forDuration: 0.2, thenDragTo: target)
        }
        capture(mini, onLeft ? "studio-editor-before-left-tile" : "studio-editor-before-right-tile")
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: min(150, window.frame.width * 0.3), dy: 12))
        let target = mini.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: onLeft ? 3 : screen.width - 3, dy: screen.height * 0.18))
        start.press(forDuration: 0.15, thenDragTo: target)
    }

    private func studioSelectFile(_ path: String, in window: XCUIElement) throws {
        try tap(window.buttons["miniapps-studio-files"].firstMatch, "Open this real window's source menu.")
        try tap(mini.buttons[path].firstMatch, "Select the actual same source in this distinct window.")
        try require(window.textViews["miniapps-studio-editor"].firstMatch.exists, "The window's actual source editor is absent.")
    }

    private func studioWindow(_ left: Bool) throws -> XCUIElement {
        let windows = studioEditorWindows()
        try require(windows.count == 2 && windows[0].frame.maxX <= windows[1].frame.minX + 2,
                    "Both actual tiled UIWindow/editor instances must remain distinct.")
        return windows[left ? 0 : 1]
    }

    private func studioRecordWindows() throws {
        let windows = studioEditorWindows()
        try require(windows.count == 2 && windows[0].frame.maxX <= windows[1].frame.minX + 2,
                    "A two-editor observation requires two genuine nonoverlapping windows.")
        func rectangle(_ frame: CGRect) -> [Double] { [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)] }
        record["editorWindowCount"] = windows.count
        record["editorWindows"] = try windows.enumerated().map { index, window -> [String: Any] in
            let editor = window.textViews["miniapps-studio-editor"].firstMatch
            return ["side": index == 0 ? "left" : "right", "windowFrame": rectangle(window.frame),
                    "editorFrame": rectangle(editor.frame), "text": try XCTUnwrap(editor.value as? String)]
        }
    }

    private func studioDismissConflictAlert() throws {
        let alert = mini.alerts["Editor"].firstMatch
        if alert.waitForExistence(timeout: bounded(3)) { try tap(alert.buttons["OK"].firstMatch, "Keep the real conflicting draft and dismiss its error alert.") }
    }

    private func studioConflictCase(_ project: String, marker: String, runID: String) throws {
        let path = "notes/conflict-" + runID.prefix(8) + ".ts"
        let original = try studioSource(marker, "original")
        try studioNewSource(String(path), text: original, in: mini)
        record["documentCreateObserved"] = true
        _ = try studioEditorCheckpoint("document-ready")
        try studioOpenSecondWindow(project: project, file: String(path))
        try studioRecordWindows()
        capture(mini, "studio-editor-two-windows")
        _ = try studioEditorCheckpoint("two-editors-ready")

        for pass in 0..<2 {
            let winner = try studioSource(marker, pass == 0 ? "writer A" : "writer A again")
            let stale = try studioSource(marker, pass == 0 ? "original" : "writer A")
            let draft = try studioSource(marker, pass == 0 ? "writer B draft" : "writer B recovered")
            let first = try studioWindow(true)
            try studioReplaceText(first.textViews["miniapps-studio-editor"].firstMatch, with: winner)
            try studioSave(in: first)
            let second = try studioWindow(false)
            let secondEditor = second.textViews["miniapps-studio-editor"].firstMatch
            try require(secondEditor.value as? String == stale, "The independently open second editor did not retain its stale source.")
            record["writerAObserved"] = first.textViews["miniapps-studio-editor"].firstMatch.value as? String
            record["staleWriterBObserved"] = secondEditor.value as? String
            try studioRecordWindows()
            _ = try studioEditorCheckpoint(pass == 0 ? "first-save" : "second-save")
            try studioReplaceText(secondEditor, with: draft)
            try require(wait(20) { second.buttons["Reload file"].firstMatch.exists || mini.alerts["Editor"].firstMatch.exists },
                        "The real stale writer did not encounter its compare-before-save conflict.")
            try studioDismissConflictAlert()
            try require(second.buttons["Reload file"].firstMatch.exists && second.buttons["Save a copy"].firstMatch.exists,
                        "The actual conflict must expose both safe recovery choices.")
            record["conflictObserved"] = true; record["draftTextObserved"] = secondEditor.value as? String
            try studioRecordWindows()
            let phase = pass == 0 ? "conflict-visible" : "second-conflict"
            capture(mini, "studio-editor-" + phase)
            _ = try studioEditorCheckpoint(phase)
            if pass == 0 {
                try tap(second.buttons["Reload file"].firstMatch, "Reload the real winning bytes without rewriting either writer.")
                try require(wait(15) { secondEditor.value as? String == winner }, "The actual reload did not adopt the first writer's source.")
                record["reloadPressed"] = true; record["reloadedText"] = secondEditor.value as? String
                _ = try studioEditorCheckpoint("reload-observed")
            }
        }
        let previousPID = try observedConcurrencyPID("studio-before-recovery-restart")
        mini.terminate(); mini.launch()
        let recoveryRoot = mini.windows.allElementsBoundByAccessibilityElement.first { $0.buttons["miniapps-open-studio"].firstMatch.exists }
        let root = try XCTUnwrap(recoveryRoot, "The relaunched actual MiniApps scene did not expose its catalog.")
        try tap(root.buttons["miniapps-open-studio"].firstMatch, "Open the real relaunched Studio recovery tools.")
        try tap(root.buttons["Recovered drafts"].firstMatch, "Use the actual persisted draft recovery list.")
        let draftRow = root.descendants(matching: .any).matching(NSPredicate(format: "label == %@", String(path))).firstMatch
        try require(draftRow.waitForExistence(timeout: bounded(30)), "The actual conflicting draft did not survive application termination.")
        capture(mini, "studio-editor-recovery-list")
        try tap(draftRow, "Reopen the same native recovery journal through its original UI.")
        let recovered = root.textViews["miniapps-studio-editor"].firstMatch
        let draft = try studioSource(marker, "writer B recovered")
        try require(wait(20) { recovered.value as? String == draft && root.buttons["Save a copy"].firstMatch.exists },
                    "The actual recovery UI did not retain the conflicting draft and safe copy action.")
        let recoveredPID = try observedConcurrencyPID("studio-recovered-draft")
        try require(recoveredPID != previousPID, "The recovery observation did not come from a new actual process.")
        record["conflictObserved"] = true; record["recoveredDraftOpened"] = true
        record["draftTextObserved"] = recovered.value as? String
        capture(mini, "studio-editor-recovered-conflict")
        _ = try studioEditorCheckpoint("recovered-draft")
        try tap(root.buttons["Save a copy"].firstMatch, "Preserve the winning file and save the real recovered draft separately.")
        record["saveCopyPressed"] = true
        let saved = try studioEditorCheckpoint("copy-saved")
        let copied = try string(saved, "copyPath")
        try studioRestartAndOpen(project, file: String(path))
        let editor = mini.textViews["miniapps-studio-editor"].firstMatch
        let winning = try studioSource(marker, "writer A again")
        try require(editor.value as? String == winning, "Saving the recovery copy changed the genuine winning source.")
        record["winningTextObserved"] = editor.value as? String
        try selectStudioFile(copied)
        try require(editor.value as? String == draft, "The actual recovered separate source copy did not survive reopening.")
        record["copyTextObserved"] = editor.value as? String; record["conflictCopyPath"] = copied
    }

    // Separate authored packages keep every previously qualified surface input
    // unchanged. These are paced-work Simulator cases, not CPU/network-duration
    // or physical-device lock/power acceptance.
    func testExpoSavedLongRunningBackgroundActionReturnsAfterThreeHundredSeconds() throws {
        try observeLongRunningShortcut(.expo, cancel: false)
    }

    func testNativeScriptSavedLongRunningBackgroundActionReturnsAfterThreeHundredSeconds() throws {
        try observeLongRunningShortcut(.nativescript, cancel: false)
    }

    func testExpoSavedLongRunningBackgroundActionCancelsAfterThreeHundredSeconds() throws {
        try observeLongRunningShortcut(.expo, cancel: true)
    }

    func testNativeScriptSavedLongRunningBackgroundActionCancelsAfterThreeHundredSeconds() throws {
        try observeLongRunningShortcut(.nativescript, cancel: true)
    }

    private func observeLongRunningShortcut(_ engine: Engine, cancel: Bool) throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        deadline = Date().addingTimeInterval(540)
        let runID = UUID().uuidString.lowercased()
        let token = UUID().uuidString.lowercased()
        let appID = "hanlin.longrunning." + engine.rawValue
        let title = engine == .expo ? "Long Running Expo" : "Long Running NativeScript"
        let shortcutName = "Hanlin-LR-" + engine.rawValue + "-" + String(runID.prefix(8))
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let root = documents.appendingPathComponent("HanlinShortcutLongRunningObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root; runDirectory = directory
        record = ["schema": 1, "runID": runID, "token": token, "engine": engine.rawValue,
                  "surface": "miniAppShortcutLongRunning", "scenario": cancel ? "cancel" : "return",
                  "fixtureAppID": appID, "fixtureTitle": title, "savedShortcutName": shortcutName,
                  "startedAt": concurrencyTimestamp(), "status": "RUNNING", "test": name, "phase": "preparing"]
        try checkpoint("preparing")
        defer {
            capture(mini, "long-running-final-mini")
            capture(shortcuts, "long-running-final-shortcuts")
            record["finishedAt"] = concurrencyTimestamp()
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            mini.launch()
            try openLongRunningFixture(engine)
            let status = mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "App ID:")).firstMatch
            try require(wait(20) { status.exists && self.stateFields(status.label)["App ID"] == appID },
                        "The independent long-running package did not expose its real private state.")
            let oldChallenge = stateFields(status.label)["Challenge"]
            let prepare = mini.buttons["Prepare challenge"].firstMatch
            try tap(prepare, "Prepare a new challenge through the actual installed package UI.")
            try require(wait(20) {
                guard status.exists else { return false }
                let fields = self.stateFields(status.label)
                return fields["Challenge"] != nil && fields["Challenge"] != oldChallenge &&
                    fields["Challenge"] != "not-prepared" && fields["Counter"] == "0" && prepare.isEnabled
            }, "The actual prepared challenge did not finish writing.")
            let challenge = try XCTUnwrap(stateFields(status.label)["Challenge"])
            let ownerPID = try observedConcurrencyPID("long-running-prepared")
            let header = String(mini.debugDescription.split(separator: "\n", maxSplits: 1).first ?? "")
            record["challenge"] = challenge; record["baselineCounter"] = 0
            record["ownerProcessID"] = ownerPID; record["ownerAccessibilityHeader"] = header
            var ownerWindowID: String?
            if engine == .nativescript {
                let label = mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Owner window: ")).firstMatch
                try require(label.exists, "The actual initial NativeScript window identity is unavailable.")
                ownerWindowID = String(label.label.dropFirst("Owner window: ".count))
                try require(ownerWindowID?.isEmpty == false, "The original owner window identity is empty.")
            }
            if let ownerWindowID { record["ownerWindowID"] = ownerWindowID }
            else { record["ownerWindowID"] = NSNull() }
            let options: [String: Any] = ["schema": 1, "token": token, "profile": "paced-35-v1"]
            let typed: [String: Any] = ["text": "שלום עולם", "count": 42, "enabled": true, "empty": NSNull(),
                                        "list": [true, 42, "שלום"] as [Any]]
            let input: [String: Any] = ["surface": "miniAppShortcutLongRunning", "challenge": challenge,
                                        "longRunning": options, "typed": typed]
            record["configuredInput"] = input
            capture(mini, "long-running-prepared")
            try checkpoint("prepared")
            let identity = try longRunningResponse("identity.json", timeout: 25, background: false)
            try require(identity["status"] as? String == "READY" && identity["appID"] as? String == appID,
                        "The original source/product/installed-generation admission failed.")
            record["installedIdentity"] = identity
            try requireSystemApp("shortcuts", identity: identity)
            shortcuts.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            shortcuts.launch()
            // Reuse the original real gallery/entity/typed-input/mode path.
            // It asserts both new-action defaults before enabling long running.
            try configureConcurrencyShortcut(["token": token, "savedShortcutName": shortcutName,
                                              "configuredInput": input], identity: identity)
            try reopenLongRunningShortcut(shortcutName)
            try addShortcutAction("Get Text from Input")
            try addShortcutAction("Show Result")
            try tap(firstButton(shortcuts, ["Done"]), "Save the actual built-in result chain.")
            try reopenLongRunningShortcut(shortcutName)
            let mode = try shortcutModeSwitch()
            let savedMode = try observedSwitchValue(mode)
            let longRunning = shortcuts.switches["Allow Long Running"].firstMatch
            try require(longRunning.waitForExistence(timeout: bounded(10)), "Saved long-running parameter is not observable.")
            let savedLongRunning = try observedSwitchValue(longRunning)
            try require(savedMode == false && savedLongRunning == true,
                        "Save/reopen did not persist background mode and Allow Long Running.")
            record["savedConfiguration"] = ["savedShortcutName": shortcutName, "reopened": true,
                "openWhenRun": savedMode, "allowLongRunning": savedLongRunning,
                "resultChainConfigured": true, "observedAt": concurrencyTimestamp()]
            capture(shortcuts, "long-running-saved-settings")
            try require(mini.state != .runningForeground, "The actual Shortcuts UI must own the launch surface.")
            try checkpoint("before-system-action")
            let requestedAt = concurrencyTimestamp()
            try tap(firstButton(shortcuts, ["Run Shortcut", "Run"]), "Run this actual saved system Shortcut once.")
            record["launch"] = ["savedShortcutName": shortcutName, "systemRunTapped": true,
                                 "requestedAt": requestedAt, "observedAt": concurrencyTimestamp()]
            try checkpoint("system-action-sent")
            let running = try longRunningResponse("running.json", timeout: 25, background: true)
            try require(running["status"] as? String == "RUNNING_OBSERVED",
                        "No real current native command, live lease and handler were jointly observed.")
            record["actualRunningAdmission"] = running
            record["initialSystemProgress"] = try longRunningSystemProgress(token: token)
            capture(shortcuts, "long-running-initial-progress")
            XCUIDevice.shared.press(.home)
            try require(wait(10) { self.shortcuts.state != .runningForeground && self.mini.state != .runningForeground },
                        "The actual Home action did not background the system action and MiniApps.")
            record["homeObservation"] = ["homePressed": true, "miniAppsForeground": false,
                                          "shortcutsForeground": false, "observedAt": concurrencyTimestamp()]
            capture(springboard, "long-running-actual-home")
            try checkpoint("home-observed")
            // The observer starts its monotonic clock only after jointly seeing
            // the real command, current lease, handler and original OS process.
            let longProof = try longRunningResponse("long-running.json", timeout: 325, background: true, home: true)
            try require(longProof["status"] as? String == "LONG_RUNNING_OBSERVED" &&
                        ((longProof["elapsedMonotonicSeconds"] as? NSNumber)?.doubleValue ?? 0) > 300,
                        "The original system action did not remain genuinely pending for more than 300 seconds.")
            record["actualLongRunning"] = longProof
            shortcuts.activate()
            try require(wait(10) { self.shortcuts.state == .runningForeground }, "The running Shortcuts UI is unavailable.")
            record["finalSystemProgress"] = try longRunningSystemProgress(token: token)
            capture(shortcuts, "long-running-after-three-hundred-seconds")
            try checkpoint("after-three-hundred-seconds")
            if cancel {
                let visibleName = shortcuts.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", shortcutName)).firstMatch
                try require(visibleName.exists && visibleName.isHittable,
                            "The running saved Shortcut must be identified before using its real Stop control.")
                let stop = firstButton(shortcuts, ["Stop Shortcut", "Stop"])
                try require(stop.exists && stop.isEnabled && stop.isHittable,
                            "The action completed or has no real system Stop control; cancellation is not proved.")
                capture(shortcuts, "long-running-before-stop")
                let stopAt = concurrencyTimestamp()
                try tap(stop, "Stop the genuinely running saved Shortcut after the observed 300-second interval.")
                record["stop"] = ["token": token, "visibleShortcutName": shortcutName,
                                  "systemStopObserved": true, "requestedAt": stopAt,
                                  "observedAt": concurrencyTimestamp()]
                try checkpoint("system-stop-sent")
                try require(wait(12) { !stop.exists || !stop.isEnabled }, "The selected system action did not stop.")
                record["systemCancelledObserved"] = true
                capture(shortcuts, "long-running-system-stopped")
            }
            let terminal = try longRunningResponse("terminal.json", timeout: 110, background: true)
            try require(terminal["status"] as? String == "TERMINAL_OBSERVED",
                        "The exact native result, lease/window release or bounded late-result check failed.")
            record["actualTerminal"] = terminal
            if !cancel {
                record["systemChainedResult"] = try longRunningChainedResult(terminal)
            }
            // Restore only the already running owner after native termination.
            mini.activate()
            try require(wait(15) {
                status.exists && self.stateFields(status.label)["Challenge"] == challenge &&
                    self.stateFields(status.label)["Counter"] == "0"
            }, "Background execution changed the original prepared owner's private state.")
            record["ownerProcessIDAfter"] = try observedConcurrencyPID("long-running-after-terminal")
            try require(record["ownerProcessIDAfter"] as? Int == ownerPID, "A replacement process cannot qualify owner survival.")
            if let ownerWindowID {
                let label = mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Owner window: ")).firstMatch
                try require(label.exists && label.label == "Owner window: " + ownerWindowID,
                            "The original prepared native owner window was replaced.")
            }
            try checkpoint("system-result-observed")
            let complete = try longRunningResponse("completion.json", timeout: 25, background: false)
            try require(complete["status"] as? String == "EXECUTED_PASS", "The final current source/identity/OS result readback failed.")
            record["observerCompletion"] = complete; record["status"] = "EXECUTED_PASS"
        } catch let skipped as XCTSkip {
            record["status"] = "BLOCKED"; record["reason"] = String(describing: skipped); throw skipped
        } catch {
            record["status"] = "FAILED"; record["reason"] = String(describing: error); throw error
        }
    }

    private func openLongRunningFixture(_ engine: Engine) throws {
        let title = engine == .expo ? "Long Running Expo" : "Long Running NativeScript"
        let archiveName = engine == .expo ? "LongRunningExpo" : "LongRunningNativeScript"
        let close = mini.buttons["hanlin-script-app-close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
        let manage = mini.buttons["hanlin-apps-add"].firstMatch
        try require(manage.waitForExistence(timeout: bounded(25)), "The shipping MiniApps catalog is unavailable.")
        let card = mini.buttons["hanlin-package-card-" + title].firstMatch
        if !card.exists {
            try tap(manage, "Open the original package importer.")
            try tap(mini.buttons["hanlin-import-script-package"].firstMatch, "Open original package import.")
            let list = mini.collectionViews["hanlin-package-import-list"].firstMatch
            try require(list.waitForExistence(timeout: bounded(15)), "The original import list is unavailable.")
            let archive = list.buttons[archiveName].firstMatch
            try reveal(archive, in: list, message: "The independent original-produced long-running archive is absent.")
            try tap(archive, "Import the exact independently authored archive.")
            let install = mini.buttons["hanlin-package-install"].firstMatch
            let importError = mini.descendants(matching: .any)["hanlin-import-error-message"].firstMatch
            let diagnostics = mini.descendants(matching: .any)["hanlin-import-diagnostics-sheet"].firstMatch
            try require(wait(120) { install.exists || importError.exists || diagnostics.exists },
                        "Original strict validation did not reach an actual outcome.")
            capture(mini, "long-running-import-preview")
            try require(!importError.exists && !diagnostics.exists && install.exists,
                        "The real compiler/importer rejected the independent fixture.")
            try tap(install, "Install through the original production preview.")
            try require(wait(45) { !install.exists || importError.exists }, "The real installer did not finish.")
            try require(!importError.exists, "The real installer reported an error.")
            try tap(mini.buttons["hanlin-package-import-done"].firstMatch, "Dismiss the completed importer.")
            try tap(mini.buttons["hanlin-apps-add-done"].firstMatch, "Return to the actual catalog.")
        }
        try reveal(card, in: mini, message: "The installed independent package is absent.")
        try tap(card, "Open the actual installed long-running package.")
        try require(mini.buttons["Prepare challenge"].firstMatch.waitForExistence(timeout: bounded(30)),
                    "The actual independent package runtime UI did not load.")
    }

    private func reopenLongRunningShortcut(_ name: String) throws {
        let saved = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        try require(saved.waitForExistence(timeout: bounded(15)), "The actual saved Shortcut is absent from the system collection.")
        saved.press(forDuration: 1.2)
        try tap(firstButton(shortcuts, ["Edit", "Edit Shortcut"]), "Reopen the saved Shortcut without executing it.")
        capture(shortcuts, "long-running-reopened")
    }

    private func longRunningSystemProgress(token: String) throws -> [String: Any] {
        let pattern = try NSRegularExpression(pattern: "LR " + NSRegularExpression.escapedPattern(for: token) + " ([0-9]+)/35 receipts")
        var observed: [String: Any]?
        try require(wait(15) {
            let elements = self.shortcuts.staticTexts.allElementsBoundByIndex + self.shortcuts.progressIndicators.allElementsBoundByIndex
            for element in elements where element.exists {
                for text in [element.label, element.value as? String ?? ""] {
                    guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                          let whole = Range(match.range(at: 0), in: text), let count = Range(match.range(at: 1), in: text),
                          let completed = Int(text[count]) else { continue }
                    observed = ["token": token, "text": String(text[whole]), "completed": completed,
                                "label": element.label, "value": element.value as? String ?? "",
                                "observedAt": self.concurrencyTimestamp()]
                    return true
                }
            }
            return false
        }, "The actual system UI did not expose this invocation's native completed-work progress; inspect its retained AX/screenshot.")
        return try XCTUnwrap(observed)
    }

    private func longRunningResponse(_ filename: String, timeout: TimeInterval, background: Bool, home: Bool = false) throws -> [String: Any] {
        let directory = try XCTUnwrap(runDirectory)
        let file = directory.appendingPathComponent(filename)
        let failure = directory.appendingPathComponent("failure.json")
        let end = Date().addingTimeInterval(bounded(timeout))
        var observations = [[String: Any]]()
        var lastSample = -Double.infinity
        while Date() < end {
            if FileManager.default.fileExists(atPath: failure.path) {
                let value = try response("failure.json", timeout: 1)
                throw ObservationFailure(description: "Actual long-running observation failed: " + (value["reason"] as? String ?? "unknown"))
            }
            if background {
                try require(mini.state != .runningForeground && mini.state != .notRunning,
                            "The background action presented or lost its original MiniApps process.")
                if home { try require(shortcuts.state != .runningForeground, "Shortcuts unexpectedly left the observed background interval.") }
            }
            let monotonic = ProcessInfo.processInfo.systemUptime
            if monotonic - lastSample >= 1 {
                observations.append(["at": concurrencyTimestamp(), "uptime": monotonic,
                    "miniAppsState": mini.state.rawValue, "shortcutsState": shortcuts.state.rawValue])
                lastSample = monotonic
            }
            if FileManager.default.fileExists(atPath: file.path) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        try writeJSON(["schema": 1, "runID": try string(record, "runID"), "response": filename,
                       "observations": observations], filename: filename + ".application-states.json")
        return try response(filename, timeout: 1)
    }

    private func longRunningChainedResult(_ terminal: [String: Any]) throws -> [String: Any] {
        let challenge = try string(record, "challenge")
        let journal = try XCTUnwrap(terminal["journal"] as? [String: Any])
        let native = try XCTUnwrap(journal["value"] as? [String: Any])
        var displayed: [String: Any]?
        try require(wait(15) {
            let texts = self.shortcuts.staticTexts.allElementsBoundByIndex.map(\.label) +
                self.shortcuts.textViews.allElementsBoundByIndex.compactMap { $0.value as? String }
            for text in texts where text.contains(challenge) {
                if let bytes = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                   value["challenge"] as? String == challenge { displayed = value; return true }
            }
            return false
        }, "The actual Get Text → Show Result chain did not display this invocation's complete result.")
        let value = try XCTUnwrap(displayed)
        try require(equalTypedJSON(value, native), "The displayed OS result changed exact JSON types or actual runtime receipts.")
        capture(shortcuts, "long-running-chained-result")
        if shortcuts.buttons["Done"].firstMatch.exists { shortcuts.buttons["Done"].firstMatch.tap() }
        return value
    }

    // Additive native-array pilot. Every save/reopen/clear uses public Shortcuts
    // controls. An unrecognized editor is retained and fails this case honestly.
    private enum NativeListKind: String {
        case text, integer, number, boolean
        var title: String {
            switch self {
            case .text: return "Text List"
            case .integer: return "Integer List"
            case .number: return "Number List"
            case .boolean: return "Boolean List"
            }
        }
        var mode: String { rawValue + "List" }
        var parameter: String {
            switch self {
            case .text: return "textItems"
            case .integer: return "integerItems"
            case .number: return "numberItems"
            case .boolean: return "booleanItems"
            }
        }
        var method: String {
            "testNativeScriptSaved" + rawValue.prefix(1).uppercased() +
                String(rawValue.dropFirst()) + "ListReopensThenClearsToEmpty"
        }
        func values(runID: String) -> [Any] {
            switch self {
            case .text: return ["שלום", "汉字", runID]
            case .integer: return [-7, 0, 42]
            case .number: return [-1.25, 0.5, 42.125]
            case .boolean: return [true, false]
            }
        }
    }

    func testNativeScriptSavedTextListReopensThenClearsToEmpty() throws {
        try nativeListShortcut(.text)
    }
    func testNativeScriptSavedIntegerListReopensThenClearsToEmpty() throws {
        try nativeListShortcut(.integer)
    }
    func testNativeScriptSavedNumberListReopensThenClearsToEmpty() throws {
        try nativeListShortcut(.number)
    }
    func testNativeScriptSavedBooleanListReopensThenClearsToEmpty() throws {
        try nativeListShortcut(.boolean)
    }

    private func nativeListShortcut(_ kind: NativeListKind) throws {
        continueAfterFailure = false
        executionTimeAllowance = 360
        deadline = Date().addingTimeInterval(360)
        let runID = UUID().uuidString.lowercased()
        let root = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("HanlinSystemSurfaceObservation", isDirectory: true)
        let directory = root.appendingPathComponent(runID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        exchange = root; runDirectory = directory
        record = ["schema": 1, "runID": runID, "engine": "nativescript", "surface": "nativeLists",
                  "fixtureAppID": "hanlin.shortcutlists.nativescript", "listKind": kind.rawValue,
                  "testMethod": kind.method, "startedAt": timestamp(), "status": "RUNNING"]
        try checkpoint("preparing")
        defer {
            capture(shortcuts, "native-lists-final-shortcuts")
            capture(mini, "native-lists-final-miniapps")
            try? writeJSON(record, filename: "case.json")
            try? checkpoint("finished")
        }
        do {
            mini.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            mini.launch()
            try openNativeListFixture()
            try checkpoint("native-list-installed")
            let identity = try response("identity.json", timeout: 30)
            try require(identity["status"] as? String == "READY", "The current fixture was not admitted.")
            try requireSystemApp("shortcuts", identity: identity)
            try createNativeListShortcut(kind, identity: identity)
            let name = "Hanlin-lists-" + kind.rawValue + "-" + String(runID.prefix(8))
            record["savedShortcutName"] = name
            let values = kind.values(runID: runID)
            var editor = try nativeListEditor(kind)
            try appendNativeListValues(kind, values: values, editor: editor)
            _ = try readNativeListRows(kind, expected: values, editor: editor)
            try closeNativeListEditor(editor)
            let mode = try shortcutModeSwitch()
            let initialBackgroundMode = try observedSwitchValue(mode)
            try require(initialBackgroundMode == false, "A new saved list action must default to background.")
            try addShortcutAction("Get Text from Input")
            try addShortcutAction("Show Result")
            record["builtInChain"] = ["Get Text from Input", "Show Result"]
            try renameShortcut(name)
            for step in 0...1 {
                // This loop shares the original 360-second case deadline.
                if step == 1 {
                    editor = try nativeListEditor(kind)
                    _ = try readNativeListRows(kind, expected: values, editor: editor)
                    try clearNativeListRows(kind, count: values.count, editor: editor)
                    _ = try readNativeListRows(kind, expected: [], editor: editor)
                    try closeNativeListEditor(editor)
                }
                try tap(firstButton(shortcuts, ["Done"]), "Save the actual native-list Shortcut.")
                capture(shortcuts, "native-lists-saved-\(step)")
                shortcuts.terminate(); mini.terminate(); shortcuts.launch()
                try reopenLongRunningShortcut(name)
                let reopenedModeControl = try shortcutModeSwitch()
                let reopenedMode = try observedSwitchValue(reopenedModeControl)
                try require(reopenedMode == false, "The saved Shortcut changed its background choice.")
                editor = try nativeListEditor(kind)
                let observed = try readNativeListRows(kind, expected: step == 0 ? values : [], editor: editor)
                record["editor"] = ["inputMode": kind.mode, "parameter": kind.parameter, "label": kind.title,
                    "savedAndReopened": true, "processRestarted": true, "openWhenRun": false,
                    "rowCount": observed.values.count, "values": observed.values, "rawRows": observed.raw]
                capture(shortcuts, "native-lists-reopened-\(step)")
                try closeNativeListEditor(editor)
                record["step"] = step
                record["systemLaunchObserved"] = false
                try checkpoint("native-list-arm")
                let armed = try response("armed-\(step).json", timeout: 30)
                try require(armed["status"] as? String == "ARMED" && armed["step"] as? Int == step,
                            "The observer did not arm this exact saved list step.")
                try require(shortcuts.state == .runningForeground && mini.state != .runningForeground,
                            "The real Shortcuts app must own the execution surface.")
                try tap(firstButton(shortcuts, ["Run Shortcut", "Run"]),
                        "Run the saved native array through the real built-in result chain.")
                record["systemLaunchObserved"] = true
                try checkpoint("native-list-sent")
                let completion = try nativeListCompletion(step)
                try require(completion["status"] as? String == "EXECUTED_PASS",
                            "The native list did not produce a correlated terminal.")
                let result = try XCTUnwrap(completion["result"] as? [String: Any])
                record["renderedResult"] = try readNativeListShownResult(result, step: step)
                try checkpoint("native-list-chain-read")
                if step == 0 {
                    let acknowledged = try response("chain-0.json", timeout: 15)
                    try require(acknowledged["status"] as? String == "CHAIN_READ",
                                "The first real built-in chain was not acknowledged.")
                    try tap(firstButton(shortcuts, ["Done", "Close"]), "Dismiss the actual first Show Result.")
                } else {
                    let final = try response("completion.json", timeout: 15)
                    try require(final["status"] as? String == "EXECUTED_PASS" &&
                                final["nativeExecutions"] as? Int == 2,
                                "Both nonempty and cleared-empty saved-list executions must pass.")
                    record["completion"] = final
                }
            }
            record["status"] = "EXECUTED_PASS"
        } catch {
            record["status"] = "FAILED"; record["error"] = String(describing: error)
            throw error
        }
    }

    private func openNativeListFixture() throws {
        let title = "Native Lists NativeScript"
        let close = mini.buttons["hanlin-script-app-close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
        let manage = mini.buttons["hanlin-apps-add"].firstMatch
        try require(manage.waitForExistence(timeout: bounded(25)), "The original MiniApps catalog is unavailable.")
        let card = mini.buttons["hanlin-package-card-" + title].firstMatch
        if !card.exists {
            try tap(manage, "Open the original package importer.")
            try tap(mini.buttons["hanlin-import-script-package"].firstMatch, "Import the actual native-list package.")
            let list = mini.collectionViews["hanlin-package-import-list"].firstMatch
            try require(list.waitForExistence(timeout: bounded(15)), "The original import list is unavailable.")
            let archive = list.buttons["NativeListsNativeScript"].firstMatch
            try reveal(archive, in: list, message: "The original-produced native-list archive is absent.")
            try tap(archive, "Read the exact independent native-list archive.")
            let install = mini.buttons["hanlin-package-install"].firstMatch
            let failure = mini.descendants(matching: .any)["hanlin-import-error-message"].firstMatch
            let diagnostics = mini.descendants(matching: .any)["hanlin-import-diagnostics-sheet"].firstMatch
            try require(wait(120) { install.exists || failure.exists || diagnostics.exists },
                        "The original strict importer did not finish.")
            capture(mini, "native-lists-import-preview")
            try require(install.exists && !failure.exists && !diagnostics.exists,
                        "The original compiler/importer rejected the native-list fixture.")
            try tap(install, "Install using the real production preview.")
            try require(wait(45) { !install.exists || failure.exists }, "The real installation did not finish.")
            try require(!failure.exists, "The original installation failed.")
            try tap(mini.buttons["hanlin-package-import-done"].firstMatch, "Dismiss the original importer.")
            try tap(mini.buttons["hanlin-apps-add-done"].firstMatch, "Return to the real catalog.")
        }
        try reveal(card, in: mini, message: "The installed native-list package is missing.")
        try tap(card, "Open the actual installed NativeScript fixture.")
        let ready = mini.descendants(matching: .any)["native-lists-ready"].firstMatch
        try require(ready.waitForExistence(timeout: bounded(30)) &&
                    (ready.label == "hanlin.shortcutlists.nativescript" ||
                     ready.value as? String == "hanlin.shortcutlists.nativescript"),
                    "The actual NativeScript factory did not expose its app identity.")
        capture(mini, "native-lists-installed")
    }

    private func createNativeListShortcut(_ kind: NativeListKind, identity: [String: Any]) throws {
        shortcuts.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        shortcuts.launch()
        try createSystemShortcut("The real system creation UI did not become available.")
        let search = try findShortcutActionSearch("Search the real indexed MiniApps actions.")
        search.typeText("Hanlin MiniApps")
        try tap(shortcuts.staticTexts["Hanlin MiniApps"].firstMatch, "Open the indexed standalone app.")
        try tap(shortcuts.staticTexts["Run MiniApp Action"].firstMatch, "Add the shipping typed action.")
        try tap(firstButton(shortcuts, ["Action", "Script Action"]), "Choose the installed native-list action.")
        try tap(shortcuts.staticTexts[try string(identity, "actionDisplayName")].firstMatch,
                "Select the exact current installed action entity.")
        if shortcuts.buttons["Show More"].firstMatch.exists { shortcuts.buttons["Show More"].firstMatch.tap() }
        try tap(shortcuts.buttons["Input Type"].firstMatch, "Choose the shipping native array mode.")
        try tap(shortcuts.staticTexts[kind.title].firstMatch, "Choose the actual " + kind.title + " enum case.")
        capture(shortcuts, "native-lists-selected-mode")
    }

    private func nativeListEditor(_ kind: NativeListKind) throws -> XCUIElement {
        let parameter = shortcuts.buttons.matching(identifier: kind.title).allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        try require(parameter.count == 1,
                    "The current native " + kind.title + " parameter must be uniquely exposed; inspect retained AX.")
        parameter[0].tap()
        var containers: [XCUIElement] = []
        try require(wait(10) {
            let candidates = self.shortcuts.sheets.allElementsBoundByIndex +
                self.shortcuts.popovers.allElementsBoundByIndex + self.shortcuts.dialogs.allElementsBoundByIndex
            containers = candidates.filter {
                $0.exists && $0.isHittable &&
                ($0.label == kind.title || $0.staticTexts[kind.title].firstMatch.exists ||
                 $0.navigationBars[kind.title].firstMatch.exists)
            }
            return containers.count == 1
        }, "No unique public native array editor was observed; JSON/scalar fallback is forbidden.")
        capture(shortcuts, "native-lists-editor-" + kind.rawValue)
        return containers[0]
    }

    private func nativeListControls(_ kind: NativeListKind, editor: XCUIElement) -> [XCUIElement] {
        if kind == .boolean { return editor.switches.allElementsBoundByIndex.filter { $0.exists } }
        return editor.textFields.allElementsBoundByIndex.filter { $0.exists }
    }

    private func appendNativeListValues(_ kind: NativeListKind, values: [Any], editor: XCUIElement) throws {
        try require(nativeListControls(kind, editor: editor).isEmpty, "The newly selected array must start empty.")
        for (index, value) in values.enumerated() {
            let adds = editor.buttons.allElementsBoundByIndex.filter {
                $0.exists && $0.isHittable && ["Add New Item", "Add new item", "Add Item"].contains($0.label)
            }
            try require(adds.count == 1, "The array editor has no unique real Add Item control.")
            adds[0].tap()
            try require(wait(5) { self.nativeListControls(kind, editor: editor).count == index + 1 },
                        "The public editor did not add exactly one actual row.")
            let control = nativeListControls(kind, editor: editor)[index]
            if kind == .boolean {
                let wanted = try XCTUnwrap(value as? Bool)
                if try observedSwitchValue(control) != wanted { try tap(control, "Set the actual new boolean row.") }
            } else {
                let before = control.value as? String ?? ""
                try require(before.isEmpty || before == control.placeholderValue,
                            "A new native list row unexpectedly has prior content.")
                try tap(control, "Enter the actual new native array item.")
                control.typeText(String(describing: value))
            }
            _ = try readNativeListRows(kind, expected: Array(values.prefix(index + 1)), editor: editor)
        }
    }

    private func readNativeListRows(_ kind: NativeListKind, expected: [Any], editor: XCUIElement)
        throws -> (values: [Any], raw: [[String: String]]) {
        let controls = nativeListControls(kind, editor: editor)
        try require(controls.count == expected.count, "The actual native editor row count differs.")
        var values: [Any] = []; var raw: [[String: String]] = []
        for control in controls {
            let value = try XCTUnwrap(control.value as? String, "The actual native row has no public value.")
            raw.append(["label": control.label, "value": value, "identifier": control.identifier])
            switch kind {
            case .text: values.append(value)
            case .integer: values.append(try XCTUnwrap(Int(value), "The native integer row is not an exact Int."))
            case .number:
                let number = try XCTUnwrap(Double(value), "The native decimal row is not a number.")
                try require(number.isFinite, "The native decimal row is non-finite."); values.append(number)
            case .boolean: values.append(try observedSwitchValue(control))
            }
        }
        try require(equalTypedJSON(values, expected), "Actual reopened native list values/order differ.")
        return (values, raw)
    }

    private func clearNativeListRows(_ kind: NativeListKind, count: Int, editor: XCUIElement) throws {
        for remaining in stride(from: count, through: 1, by: -1) {
            try require(nativeListControls(kind, editor: editor).count == remaining, "The current clear row count differs.")
            let deletes = editor.buttons.allElementsBoundByIndex.filter {
                $0.exists && $0.isHittable && ["Delete Item", "Remove Item", "Delete"].contains($0.label)
            }
            try require(deletes.count == remaining,
                        "Each actual array row must expose its own public deletion control; no blind clear.")
            deletes.last?.tap()
            try require(wait(5) { self.nativeListControls(kind, editor: editor).count == remaining - 1 },
                        "The public delete did not remove exactly one native array item.")
        }
    }

    private func closeNativeListEditor(_ editor: XCUIElement) throws {
        let done = editor.buttons.matching(identifier: "Done").allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        try require(done.count == 1, "The actual native editor has no unique Done control.")
        done[0].tap()
        try require(wait(5) { !editor.exists || !editor.isHittable }, "The real native editor did not close.")
    }

    private func nativeListCompletion(_ step: Int) throws -> [String: Any] {
        let directory = try XCTUnwrap(runDirectory)
        let filename = "completion-\(step).json"
        let end = Date().addingTimeInterval(bounded(100))
        var observations: [[String: Any]] = []
        while Date() < end && !FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path) {
            observations.append(["at": timestamp(), "miniAppsState": mini.state.rawValue,
                                 "shortcutsState": shortcuts.state.rawValue])
            try require(mini.state != .runningForeground, "The background native list presented MiniApps.")
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        record["applicationStates-\(step)"] = observations
        try require(mini.state != .runningForeground, "The terminal background list presented MiniApps.")
        return try response(filename, timeout: 1)
    }

    private func nativeListJSONEqual(_ left: Any, _ right: Any) -> Bool {
        switch (left, right) {
        case (let a as NSNumber, let b as NSNumber):
            let ab = CFGetTypeID(a) == CFBooleanGetTypeID()
            let bb = CFGetTypeID(b) == CFBooleanGetTypeID()
            if ab || bb { return ab && bb && a.boolValue == b.boolValue }
            return a.doubleValue.isFinite && b.doubleValue.isFinite && a.compare(b) == .orderedSame
        case (let a as String, let b as String): return a.utf8.elementsEqual(b.utf8)
        case (let a as [Any], let b as [Any]):
            return a.count == b.count && zip(a, b).allSatisfy { nativeListJSONEqual($0.0, $0.1) }
        case (let a as [String: Any], let b as [String: Any]):
            return Set(a.keys) == Set(b.keys) && a.allSatisfy { key, value in
                b[key].map { nativeListJSONEqual(value, $0) } ?? false
            }
        case (_ as NSNull, _ as NSNull): return true
        default: return false
        }
    }

    private func readNativeListShownResult(_ expected: [String: Any], step: Int) throws -> [String: Any] {
        let nonce = try string(expected, "nonce")
        var actual: [String: Any]?
        try require(wait(20) {
            let elements = self.shortcuts.textViews.allElementsBoundByIndex + self.shortcuts.staticTexts.allElementsBoundByIndex
            for element in elements where element.exists && element.isHittable {
                for text in [element.value as? String ?? "", element.label] where text.contains(nonce) {
                    if let data = text.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       self.nativeListJSONEqual(parsed, expected) {
                        actual = parsed; return true
                    }
                }
            }
            return false
        }, "Real Get Text from Input → Show Result did not display this exact returned JSON.")
        capture(shortcuts, "native-lists-show-result-\(step)")
        return try XCTUnwrap(actual)
    }

}
