import CoreFoundation
import Foundation
import XCTest

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

    private func placeMatrixWidget(selecting instanceName: String) throws {
        // This reuses the original SpringBoard gallery/configuration path.
        // A fresh matching native fallback event later proves the actual family.
        XCUIDevice.shared.press(.home)
        let screen = springboard.frame
        var selectedIcon: XCUIElement?
        for _ in 0..<5 {
            selectedIcon = springboard.icons.matching(NSPredicate(format: "label == %@", "Hanlin MiniApps"))
                .allElementsBoundByIndex.first { icon in
                    let frame = icon.frame
                    return icon.isHittable && frame.minX >= screen.minX && frame.maxX <= screen.maxX &&
                        frame.minY >= screen.minY && frame.maxY < screen.maxY - 140
                }
            if selectedIcon != nil { break }
            springboard.swipeLeft()
        }
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
        let choose = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Choose' OR label == 'Widget instance'")).firstMatch
        try tap(choose, "Open the original installed-instance entity query.")
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

    private func runShortcut(_ engine: Engine, identity: [String: Any]) throws {
        try requireSystemApp("shortcuts", identity: identity)
        shortcuts.launch()
        capture(shortcuts, "shortcuts-start")
        try tap(firstButton(shortcuts, ["Create Shortcut", "Add"]), "Create one actual system Shortcut.")
        if shortcuts.buttons["Add Action"].firstMatch.exists { shortcuts.buttons["Add Action"].firstMatch.tap() }
        let search = shortcuts.searchFields.firstMatch
        try tap(search, "Search the real Shortcuts action gallery.")
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
        try tap(firstButton(shortcuts, ["Create Shortcut", "Add"]), "Create an actual new system Shortcut.")
        if shortcuts.buttons["Add Action"].firstMatch.exists { shortcuts.buttons["Add Action"].firstMatch.tap() }
        let search = shortcuts.searchFields.firstMatch
        try tap(search, "Search the functioning Shortcuts gallery.")
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
        if !shortcuts.searchFields.firstMatch.exists {
            try tap(firstButton(shortcuts, ["Add Action", "Search Actions"]), "Open the system action search.")
        }
        let search = shortcuts.searchFields.firstMatch
        try tap(search, "Search for the original built-in " + title + " action.")
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
        try tap(firstButton(shortcuts, ["Create Shortcut", "Add"]), "Create one actual saved concurrency Shortcut.")
        if shortcuts.buttons["Add Action"].firstMatch.exists { shortcuts.buttons["Add Action"].firstMatch.tap() }
        let search = shortcuts.searchFields.firstMatch
        try tap(search, "Find the actual MiniApps system action.")
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
            try tap(mini.navigationBars.buttons["Developer Studio"].firstMatch, "Return to the shipping Studio root.")
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

}
