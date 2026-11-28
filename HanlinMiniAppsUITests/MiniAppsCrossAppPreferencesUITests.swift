import XCTest

@MainActor
final class MiniAppsCrossAppPreferencesUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    override func tearDownWithError() throws {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shared MiniApps preferences"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        app.terminate()
    }
    func testSharedNewWindowPreferencePersistsAfterProcessRestart() {
        openPreferences()
        let toggle = app.switches["miniapps-new-window"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let before = toggle.value as? String
        tapNativeSwitch(in: toggle)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        let expected = toggle.value as? String
        app.terminate()
        app.launch()
        openPreferences()
        let reopened = app.switches["miniapps-new-window"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        XCTAssertEqual(reopened.value as? String, expected)
        tapNativeSwitch(in: reopened)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", before ?? ""), object: reopened)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }
    func testAppleStyleEditorAddsFavoriteWithNativeEditControls() {
        openPreferences()
        let edit = app.buttons["miniapps-editor-edit"]
        let close = app.buttons["miniapps-editor-dismiss"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        XCTAssertLessThan(close.frame.midX, edit.frame.midX, "English Apps uses leading dismissal and trailing Edit.")
        edit.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.navigationBars.buttons.matching(identifier: "miniapps-editor-edit").count, 1,
                       "Editing must retain one native EditButton in its Done state, regardless of system language or symbol rendering.")
        XCTAssertEqual(app.buttons.matching(identifier: "miniapps-editor-dismiss").count, 0,
                       "The separate sheet-dismissal action must be absent during editing.")
        let add = app.buttons["Add to Favorites: Text Studio"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Favorites"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Text Studio"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Apps editor with one Done"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        edit.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.buttons["miniapps-preferences"].waitForExistence(timeout: 10),
                      "The editor's own dismissal action must close the actual preferences sheet.")
    }
    func testPreferencesUsesEnglishAndHebrewNativeToolbarLayouts() {
        // Package title/row/dismissal strings come from the real en/he resources.
        // Native EditButton may render a symbol: never guess its translated label.
        let variants: [(language: String, locale: String, title: String,
                        newWindow: String, dismissal: String, isRTL: Bool,
                        catalogTitle: String, catalogEdit: String, catalogDone: String)] = [
            ("en", "en_US", "Apps", "Open shared MiniApps in a new window", "Done", false,
             "Mini Apps", "Edit", "Done"),
            ("he", "he_IL", "אפליקציות", "פתיחת מיני־אפליקציות משותפות בחלון חדש", "סיום", true,
             "יישומים קטנים", "עריכה", "סיום")
        ]
        for (index, variant) in variants.enumerated() {
            if index > 0 {
                app.terminate()
                app.launchArguments = ["-AppleLanguages", "(\(variant.language))",
                                       "-AppleLocale", variant.locale]
                app.launch()
            }
            let catalogToolbar = app.navigationBars[variant.catalogTitle]
            XCTAssertTrue(catalogToolbar.waitForExistence(timeout: 15),
                          "The original catalog must resolve its title from the shared locale resources.")
            let catalogEdit = app.buttons["hanlin-apps-edit"]
            XCTAssertTrue(catalogEdit.waitForExistence(timeout: 10))
            XCTAssertEqual(catalogEdit.label, variant.catalogEdit)
            catalogEdit.tap()
            XCTAssertEqual(catalogEdit.label, variant.catalogDone,
                           "The original catalog's editing confirmation must use the active language.")
            catalogEdit.tap()
            XCTAssertEqual(catalogEdit.label, variant.catalogEdit)
            let catalog = XCTAttachment(screenshot: app.screenshot())
            catalog.name = "MiniApps \(variant.language) localized original catalog"
            catalog.lifetime = .keepAlways
            self.add(catalog)
            openPreferences()
            let edit = app.buttons["miniapps-editor-edit"]
            let close = app.buttons["miniapps-editor-dismiss"]
            XCTAssertTrue(edit.waitForExistence(timeout: 15))
            XCTAssertTrue(close.waitForExistence(timeout: 15))
            let toolbar = app.navigationBars.containing(.button, identifier: "miniapps-editor-edit").firstMatch
            XCTAssertTrue(toolbar.waitForExistence(timeout: 10))
            XCTAssertTrue(toolbar.staticTexts[variant.title].waitForExistence(timeout: 10),
                          "The actual preferences sheet must show its package-localized title.")
            let newWindow = app.switches["miniapps-new-window"]
            XCTAssertTrue(newWindow.waitForExistence(timeout: 10))
            XCTAssertEqual(newWindow.label, variant.newWindow)
            XCTAssertEqual(close.label, variant.dismissal)
            XCTAssertTrue(close.isHittable)
            XCTAssertTrue(edit.isHittable)
            if variant.isRTL {
                XCTAssertGreaterThan(close.frame.midX, edit.frame.midX,
                                     "Hebrew must place leading dismissal on the right and trailing Edit on the left.")
            } else {
                XCTAssertLessThan(close.frame.midX, edit.frame.midX,
                                  "English must place leading dismissal on the left and trailing Edit on the right.")
            }
            let normal = XCTAttachment(screenshot: app.screenshot())
            normal.name = "MiniApps \(variant.language) native toolbar"
            normal.lifetime = .keepAlways
            self.add(normal)
            edit.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 10))
            XCTAssertEqual(toolbar.buttons.count, 1,
                           "Editing must expose exactly one native toolbar confirmation.")
            XCTAssertEqual(toolbar.buttons.matching(identifier: "miniapps-editor-edit").count, 1)
            XCTAssertEqual(app.buttons.matching(identifier: "miniapps-editor-dismiss").count, 0)
            let editing = XCTAttachment(screenshot: app.screenshot())
            editing.name = "MiniApps \(variant.language) one native confirmation"
            editing.lifetime = .keepAlways
            self.add(editing)
            edit.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            close.tap()
            XCTAssertTrue(app.buttons["miniapps-preferences"].waitForExistence(timeout: 10),
                          "The localized editor must dismiss its actual sheet.")
        }
    }

    private func tapNativeSwitch(in row: XCUIElement) {
        // SwiftUI exposes a labeled switch row and its actual UISwitch as a
        // nested switch. The row's center is its label, not the control thumb.
        let control = row.switches.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertTrue(control.isHittable)
        control.tap()
    }

    private func openPreferences() {
        let button = app.buttons["miniapps-preferences"]
        XCTAssertTrue(button.waitForExistence(timeout: 40))
        button.tap()
    }
}


/// Additional real native interactions; the original 25-method selection is unchanged.
@MainActor
final class MiniAppsPreferencesInteractionUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private let addPrefix = "Add to Favorites: "

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            executionTimeAllowance = 360
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            attachState("Final native preferences interaction state")
            app.terminate()
        }
    }

    func testNativeFavoriteDragRemovalAndVisibilityPersistAfterColdRelaunch() {
        openPreferences()
        let edit = app.buttons["miniapps-editor-edit"]
        edit.tap()
        waitForEditorSave(edit)

        let firstTitle = "Text Studio"
        let firstAdd = app.buttons[addPrefix + firstTitle]
        XCTAssertTrue(firstAdd.waitForExistence(timeout: 15),
                      "This follow-up requires its own fresh app preferences.")
        firstAdd.tap()
        XCTAssertTrue(firstAdd.waitForNonExistence(timeout: 15))
        waitForEditorSave(edit)

        // Select a second real published catalog entry from the visible native UI.
        let candidates = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", addPrefix)
        ).allElementsBoundByIndex
        let candidate = candidates.first { element in
            let title = String(element.label.dropFirst(addPrefix.count))
            return title != firstTitle && element.isHittable
                && app.cells.containing(.staticText, identifier: title).count == 1
        }
        XCTAssertNotNil(candidate, "The actual catalog must expose another unambiguous MiniApp.")
        guard let secondCandidate = candidate else { return }
        let secondTitle = String(secondCandidate.label.dropFirst(addPrefix.count))
        XCTAssertFalse(secondTitle.isEmpty)
        let secondAdd = app.buttons[addPrefix + secondTitle]
        XCTAssertEqual(app.buttons.matching(identifier: addPrefix + secondTitle).count, 1)
        secondAdd.tap()
        XCTAssertTrue(secondAdd.waitForNonExistence(timeout: 15))
        waitForEditorSave(edit)

        let firstRow = uniqueRow(firstTitle)
        let secondRow = uniqueRow(secondTitle)
        XCTAssertLessThan(firstRow.frame.midY, secondRow.frame.midY)
        attachState("Actual native reorder controls before drag")
        let reorderControls = secondRow.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[cd] %@", "Reorder")
        )
        XCTAssertEqual(reorderControls.count, 1,
                       "Use the original native reorder control, not a model or direct preference write.")
        let reorder = reorderControls.element(boundBy: 0)
        XCTAssertTrue(reorder.isHittable)
        reorder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0,
                   thenDragTo: firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        waitForEditorSave(edit)
        XCTAssertLessThan(uniqueRow(secondTitle).frame.midY, uniqueRow(firstTitle).frame.midY,
                          "A real drag must change the visible favorite order.")
        attachState("Native favorites reordered by drag")
        leavePreferences(edit: edit)

        coldReopenPreferences()
        XCTAssertLessThan(uniqueRow(secondTitle).frame.midY, uniqueRow(firstTitle).frame.midY,
                          "The dragged order must survive process termination and reopening.")
        let reopenedEdit = app.buttons["miniapps-editor-edit"]
        reopenedEdit.tap()
        waitForEditorSave(reopenedEdit)
        let removingRow = uniqueRow(secondTitle)
        attachState("Actual native favorite removal controls")
        let deleteControls = removingRow.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[cd] %@", "Delete")
        )
        XCTAssertEqual(deleteControls.count, 1)
        XCTAssertTrue(deleteControls.element(boundBy: 0).isHittable)
        deleteControls.element(boundBy: 0).tap()
        let confirmation = removingRow.buttons["Delete"]
        if confirmation.waitForExistence(timeout: 3) {
            XCTAssertTrue(confirmation.isHittable)
            confirmation.tap()
        }
        let returnedSuggestion = app.buttons[addPrefix + secondTitle]
        XCTAssertTrue(returnedSuggestion.waitForExistence(timeout: 15),
                      "Removing the favorite must return the same real MiniApp to Suggestions.")
        waitForEditorSave(reopenedEdit)

        let visibilityControls = uniqueRow(secondTitle).switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "miniapps-visible-")
        )
        XCTAssertEqual(visibilityControls.count, 1)
        let visibility = visibilityControls.element(boundBy: 0)
        let visibilityID = visibility.identifier
        XCTAssertFalse(visibilityID.isEmpty)
        XCTAssertEqual(visibility.value as? String, "1")
        tapNativeSwitch(in: visibility)
        expectValue("0", on: visibility)
        waitForEditorSave(reopenedEdit)
        attachState("Removed favorite hidden through the actual native switch")
        reopenedEdit.tap()
        XCTAssertTrue(app.buttons["miniapps-editor-dismiss"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.cells.containing(.staticText, identifier: secondTitle).count, 0,
                       "The hidden suggestion must disappear from the nonediting list.")
        app.buttons["miniapps-editor-dismiss"].tap()

        coldReopenPreferences()
        XCTAssertEqual(app.cells.containing(.staticText, identifier: secondTitle).count, 0)
        let persistedEdit = app.buttons["miniapps-editor-edit"]
        persistedEdit.tap()
        waitForEditorSave(persistedEdit)
        XCTAssertTrue(app.buttons[addPrefix + secondTitle].waitForExistence(timeout: 15),
                      "Removal from Favorites must persist across the second cold launch.")
        let persistedVisibility = app.switches[visibilityID]
        XCTAssertTrue(persistedVisibility.waitForExistence(timeout: 10))
        XCTAssertEqual(persistedVisibility.value as? String, "0",
                       "The exact MiniApp's hidden state must persist across a cold launch.")
        attachState("Cold reopened removal and hidden preference")
        tapNativeSwitch(in: persistedVisibility)
        expectValue("1", on: persistedVisibility)
        waitForEditorSave(persistedEdit)
        persistedEdit.tap()
        XCTAssertTrue(uniqueRow(secondTitle).waitForExistence(timeout: 10),
                      "Restoring visibility must restore the actual suggestion.")
        app.buttons["miniapps-editor-dismiss"].tap()
        XCTAssertTrue(app.buttons["miniapps-preferences"].waitForExistence(timeout: 10))
    }

    private func uniqueRow(_ title: String) -> XCUIElement {
        let rows = app.cells.containing(.staticText, identifier: title)
        XCTAssertEqual(rows.count, 1, "Exactly one actual native row must represent \(title).")
        return rows.element(boundBy: 0)
    }

    private func openPreferences() {
        let button = app.buttons["miniapps-preferences"]
        XCTAssertTrue(button.waitForExistence(timeout: 40))
        button.tap()
        XCTAssertTrue(app.buttons["miniapps-editor-edit"].waitForExistence(timeout: 15))
    }

    private func coldReopenPreferences() {
        app.terminate()
        app.launch()
        openPreferences()
    }

    private func waitForEditorSave(_ edit: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),
                                              object: edit)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
    }

    private func expectValue(_ value: String, on element: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value),
                                                 object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }

    private func tapNativeSwitch(in row: XCUIElement) {
        let control = row.switches.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertTrue(control.isHittable)
        control.tap()
    }

    private func leavePreferences(edit: XCUIElement) {
        edit.tap()
        let close = app.buttons["miniapps-editor-dismiss"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.buttons["miniapps-preferences"].waitForExistence(timeout: 10))
    }

    private func attachState(_ name: String) {
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = name + " AX"; ax.lifetime = .keepAlways
        add(ax)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
