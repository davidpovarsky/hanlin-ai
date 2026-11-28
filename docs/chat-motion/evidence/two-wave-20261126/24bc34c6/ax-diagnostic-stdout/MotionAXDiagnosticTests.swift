import XCTest
import Foundation

@MainActor
final class MotionAXDiagnosticTests: XCTestCase {
    func testCaptureRetainedDisclosureAccessibility() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-motion", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["proof-thinking"].waitForExistence(timeout: 10))
        func wait(_ state: String) {
            XCTAssertEqual(XCTWaiter.wait(for: [
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", state),
                    object: app.staticTexts["proof-geometry-state"])
            ], timeout: 5), .completed)
        }
        func capture(_ state: String) throws {
            let summary = app.staticTexts["proof-summary"]
            let text = "geometry=\(app.staticTexts["proof-geometry-state"].label)\nsummaryExists=\(summary.exists)\n" +
                "summaryFrame=\(summary.exists ? String(describing: summary.frame) : "absent")\n\n" + app.debugDescription
            print("MOTION_AX_BEGIN \(state)\n\(text)\nMOTION_AX_END \(state)")
            let directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("MotionAXDiagnostic24bc", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let textURL = directory.appendingPathComponent("\(state)-accessibility.txt")
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            let imageURL = directory.appendingPathComponent("\(state)-screen.png")
            try app.screenshot().pngRepresentation.write(to: imageURL, options: .atomic)
            print("MOTION_AX_FILES \(state) \(directory.path)")
        }
        wait("collapsed")
        app.buttons["proof-thinking"].tap()
        wait("expanded")
        try capture("expanded")
        app.buttons["proof-thinking"].tap()
        wait("collapsed")
        try capture("collapsed")
    }
}
