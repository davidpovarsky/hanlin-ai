import XCTest

/// Two separately imported packages must keep their own modules, resources,
/// document callbacks and data while sharing the actual NativeScript runtime.
@MainActor
final class MiniAppsNativeScriptPackageWindowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private var openedRequests: [NativeScriptWindowUIInteractions.Request] = []
    private var nativeProcessID: String?
    private static var installedPackages: Set<String> = []
    private let requests = [
        "alpha": "1e23b001-6a2c-4c0f-b001-202611240011",
        "beta": "1e23b002-6a2c-4c0f-b002-202611240012",
        "gamma": "1e23b003-6a2c-4c0f-b003-202611240013",
        "delta": "1e23b004-6a2c-4c0f-b004-202611240014",
    ]
    private let packages = [
        (name: "Hanlin NativeScript Package Alpha E2E", archive: "package-window-alpha"),
        (name: "Hanlin NativeScript Package Beta E2E", archive: "package-window-beta"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
    }

    override func tearDown() async throws {
        await MainActor.run {
            if (testRun?.totalFailureCount ?? 0) > 0 {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "native-package-window-failure"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "native-package-window-accessibility"
                tree.lifetime = .keepAlways
                add(tree)
                NativeScriptWindowUIInteractions.closeFailedRequestWindows(in: app, requests: openedRequests)
            }
            app.terminate()
        }
    }

    func testDifferentPackagesKeepModulesResourcesAndCallbacksWhenCompletingInReverseOrder() throws {
        installPackagesIfNeeded()
        let alpha = try open("alpha")
        editAndPrepare(alpha, name: "alpha", increments: 1)
        capture("native-package-alpha-prepared")

        let beta = try open("beta")
        editAndPrepare(beta, name: "beta", increments: 2)
        capture("native-package-beta-prepared-with-alpha-live")
        complete(beta)
        capture("native-package-beta-completed-before-alpha")
        closeCompleted(beta)

        let survivingAlpha = try focus("alpha")
        assertValue(survivingAlpha.textViews["hanlin-ns-window-input"], equals: "alpha-edited")
        assertLabel(survivingAlpha.staticTexts["hanlin-ns-window-counter"], equals: "1")
        assertLabel(survivingAlpha.staticTexts["hanlin-ns-window-status"], equals: "Prepared")
        survivingAlpha.buttons["hanlin-ns-window-increment"].tap()
        assertLabel(survivingAlpha.staticTexts["hanlin-ns-window-counter"], equals: "2")
        // The actual Return action performs a later dynamic import and a fresh
        // data read, then invokes the callback prepared before beta loaded.
        // Independent bridge verification requires alpha's captured counter=1.
        complete(survivingAlpha)
        capture("native-package-alpha-completed-after-beta-closed")
        closeCompleted(survivingAlpha)
        assertClosedRequestsStayClosedAfterColdRelaunch()
    }

    func testCancellingOnePackageKeepsOtherPackageAndItsPreparedCallbackAlive() throws {
        installPackagesIfNeeded()
        let gamma = try open("gamma")
        editAndPrepare(gamma, name: "gamma", increments: 1)
        let delta = try open("delta")
        editAndPrepare(delta, name: "delta", increments: 1)
        capture("native-package-beta-prepared-with-alpha-cancellable")

        let cancellingGamma = try focus("gamma")
        cancellingGamma.buttons["miniapps.external.cancel"].tap()
        XCTAssertTrue(cancellingGamma.staticTexts["Cancelled"].waitForExistence(timeout: 20))
        capture("native-package-alpha-cancelled-beta-live")
        closeCompleted(cancellingGamma)

        let survivingDelta = try focus("delta")
        assertValue(survivingDelta.textViews["hanlin-ns-window-input"], equals: "delta-edited")
        assertLabel(survivingDelta.staticTexts["hanlin-ns-window-counter"], equals: "1")
        assertLabel(survivingDelta.staticTexts["hanlin-ns-window-status"], equals: "Prepared")
        survivingDelta.buttons["hanlin-ns-window-increment"].tap()
        assertLabel(survivingDelta.staticTexts["hanlin-ns-window-counter"], equals: "2")
        complete(survivingDelta)
        capture("native-package-beta-completed-after-alpha-cancelled")
        closeCompleted(survivingDelta)
        assertClosedRequestsStayClosedAfterColdRelaunch()
    }

    private func open(_ name: String) throws -> XCUIElement {
        let window = try focus(name)
        assertLabel(window.staticTexts["hanlin-ns-window-status"], equals: "Ready", timeout: 90)
        assertValue(window.textViews["hanlin-ns-window-input"], equals: name)
        assertLabel(window.staticTexts["hanlin-ns-window-counter"], equals: "0")
        return window
    }

    private func focus(_ name: String) throws -> XCUIElement {
        let id = try XCTUnwrap(requests[name])
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "hanlinminiapps://x-callback-url/run?request=" + id)))
        let window = app.windows.containing(
            .navigationBar, identifier: "NativeScript package " + name
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 60),
                      "Each incoming package request must own its actual iPad scene.")
        if !openedRequests.contains(where: { $0.id == id }) {
            openedRequests.append(.init(id: id, title: "NativeScript package " + name))
        }
        try NativeScriptWindowUIInteractions.assertSameProcess(
            in: app, expected: &nativeProcessID, requestID: id
        )
        assertLabel(window.staticTexts["hanlin-ns-window-request"],
                    equals: try XCTUnwrap(UUID(uuidString: id)).uuidString, timeout: 90)
        let package = (name == "alpha" || name == "gamma") ? "alpha" : "beta"
        assertLabel(window.staticTexts["hanlin-ns-window-package"],
                    equals: "hanlin.nativescript.package-" + package)
        return window
    }

    private func editAndPrepare(_ window: XCUIElement, name: String, increments: Int) {
        for _ in 0..<increments { window.buttons["hanlin-ns-window-increment"].tap() }
        assertLabel(window.staticTexts["hanlin-ns-window-counter"], equals: String(increments))
        let input = window.textViews["hanlin-ns-window-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertTrue(input.isHittable)
        NativeScriptWindowUIInteractions.replaceContents(of: input, with: name + "-edited", app: app)
        assertValue(input, equals: name + "-edited")
        let prepare = window.buttons["hanlin-ns-window-prepare-return"]
        XCTAssertTrue(prepare.isHittable)
        prepare.tap()
        assertLabel(window.staticTexts["hanlin-ns-window-status"], equals: "Prepared", timeout: 30)
    }

    private func complete(_ window: XCUIElement) {
        let button = window.buttons["hanlin-ns-window-return"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(window.staticTexts["Result saved"].waitForExistence(timeout: 30),
                      "The original Host must persist the real package's result.")
        XCTAssertFalse(window.staticTexts["Cancelled"].exists)
    }

    private func closeCompleted(_ window: XCUIElement) {
        let button = window.buttons["miniapps.external.cancel"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        XCTAssertTrue(window.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["hanlin-apps-add"].firstMatch.waitForExistence(timeout: 20))
    }

    private func assertClosedRequestsStayClosedAfterColdRelaunch() {
        // A catalog in a background scene is not evidence that the completed
        // request's actual iPad window has been closed. The original 08ef run
        // restored a cancelled scene after its title disappeared before exit.
        let catalog = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(catalog.waitForExistence(timeout: 20))
        XCTAssertTrue(catalog.isHittable, "The native catalog must be usable before termination.")
        for request in openedRequests {
            XCTAssertTrue(app.windows.containing(.navigationBar, identifier: request.title)
                .firstMatch.waitForNonExistence(timeout: 15))
        }
        capture("native-package-catalog-before-cold-relaunch")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        app.launch()
        XCTAssertTrue(catalog.waitForExistence(timeout: 30))
        XCTAssertTrue(catalog.isHittable, "Cold launch must restore a usable catalog.")
        XCTAssertEqual(app.state, .runningForeground)
        for request in openedRequests {
            XCTAssertFalse(app.windows.containing(.navigationBar, identifier: request.title).firstMatch.exists,
                           "Explicitly closed request \(request.id) must not restore its terminal scene.")
        }
        capture("native-package-catalog-after-cold-relaunch")
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "native-package-cold-relaunch-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func assertLabel(_ element: XCUIElement, equals value: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", value), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
    }

    private func assertValue(_ element: XCUIElement, equals value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }

    private func installPackagesIfNeeded() {
        for package in packages {
            if Self.installedPackages.contains(package.name) { continue }
            let card = app.buttons["hanlin-package-card-" + package.name].firstMatch
            if card.exists {
                Self.installedPackages.insert(package.name)
                continue
            }
            let addApp = app.buttons["hanlin-apps-add"].firstMatch
            XCTAssertTrue(addApp.waitForExistence(timeout: 40))
            addApp.tap()
            let importPackage = app.buttons["hanlin-import-script-package"].firstMatch
            XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
            importPackage.tap()
            let list = app.collectionViews["hanlin-package-import-list"].firstMatch
            XCTAssertTrue(list.waitForExistence(timeout: 15))
            let archive = app.buttons[package.archive].firstMatch
            for _ in 0..<10 {
                if archive.exists && archive.isHittable { break }
                list.swipeUp()
            }
            XCTAssertTrue(archive.exists && archive.isHittable)
            archive.tap()
            let install = app.buttons["hanlin-package-install"].firstMatch
            XCTAssertTrue(install.waitForExistence(timeout: 30))
            XCTAssertTrue(install.isEnabled)
            install.tap()
            XCTAssertTrue(install.waitForNonExistence(timeout: 60))
            let done = app.buttons["hanlin-package-import-done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 15))
            done.tap()
            let closeAdd = app.buttons["hanlin-apps-add-done"].firstMatch
            XCTAssertTrue(closeAdd.waitForExistence(timeout: 15))
            closeAdd.tap()
            for _ in 0..<10 {
                if card.exists { break }
                app.swipeUp()
            }
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            Self.installedPackages.insert(package.name)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
