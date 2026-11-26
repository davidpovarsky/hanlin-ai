import AppIntents
import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinWidgetUI
import Testing
@testable import HanlinMiniApps

@MainActor
@Suite("Standalone Shortcuts mode, receipt and localization")
struct MiniAppsShortcutIntentTests {
    @Test(arguments: ["en", "he", "zh-Hans"])
    func newAndLegacyIntentTitlesLoadTheirActualHostTranslations(language: String) throws {
        let newTitles = ["en": "Run MiniApp Action", "he": "הפעלת פעולה של מיני־אפליקציה", "zh-Hans": "运行迷你应用操作"]
        let oldTitles = ["en": "Run Script Action", "he": "הפעלת פעולת סקריפט", "zh-Hans": "运行脚本操作"]
        var current = HanlinRunMiniAppShortcutIntent.title
        var original = HanlinRunScriptActionIntent.title
        current.locale = Locale(identifier: language)
        original.locale = Locale(identifier: language)
        #expect(current.table == "HanlinAppIntents" && original.table == "HanlinAppIntents")
        #expect(String(localized: current) == newTitles[language])
        #expect(String(localized: original) == oldTitles[language])
        let localeURL = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let bundle = try #require(Bundle(url: localeURL))
        #expect(bundle.localizedString(forKey: "Run MiniApp Action", value: nil, table: "HanlinAppIntents") == newTitles[language])
        let intent = HanlinRunMiniAppShortcutIntent()
        #expect(intent.inputType == .text && intent.input == "" && !intent.allowLongRunning)
        #expect(HanlinRunScriptActionIntent.openAppWhenRun)
    }

    @Test func closedAndCancelledProgressCannotAffectAnotherInvocation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shortcut-progress-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let first = try command(), second = try command()
        _ = try #require(try store.enqueueAndClaim(first))
        _ = try #require(try store.enqueueAndClaim(second))
        let firstProgress = Progress(totalUnitCount: 10), secondProgress = Progress(totalUnitCount: 20)
        let old = try MiniAppsShortcutProgressReporter(progress: firstProgress, commandID: first.id, store: store)
        let current = try MiniAppsShortcutProgressReporter(progress: secondProgress, commandID: second.id, store: store)
        _ = try old.receive("miniapps.shortcutProgress", payload: #"{"completedUnitCount":3,"totalUnitCount":10}"#)
        old.close()
        #expect(throws: CancellationError.self) {
            _ = try old.receive("miniapps.shortcutProgress", payload: #"{"completedUnitCount":9,"totalUnitCount":10}"#)
        }
        #expect(firstProgress.completedUnitCount == 3 && secondProgress.completedUnitCount == 0)
        _ = try current.receive("miniapps.shortcutProgress", payload: #"{"completedUnitCount":4,"totalUnitCount":20}"#)
        _ = try store.requestCancellation(second.id)
        #expect(throws: CancellationError.self) {
            _ = try current.receive("miniapps.shortcutProgress", payload: #"{"completedUnitCount":20,"totalUnitCount":20}"#)
        }
        #expect(firstProgress.completedUnitCount == 3 && secondProgress.completedUnitCount == 4)
    }

    @Test func onlyTheMatchingTerminalReceiptSuppliesTheShortcutValue() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shortcut-result-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root), input = try command()
        let claim = try #require(try store.enqueueAndClaim(input))
        let value = HanlinValue.object(["עברית": .array([.bool(true), .integer(7), .null])])
        #expect(throws: HanlinInvocationDispatchError.self) {
            _ = try MiniAppsShortcutExecution.result(store.receipt(for: input.id), for: input.id)
        }
        try store.complete(claim, status: .succeeded, value: value)
        let receipt = try #require(try store.receipt(for: input.id))
        #expect(try MiniAppsShortcutExecution.result(receipt, for: input.id) == value)
        #expect(throws: HanlinInvocationQueueError.missingCommand) {
            _ = try MiniAppsShortcutExecution.result(receipt, for: UUID())
        }
        #expect(try store.receipt(for: input.id) == receipt)
    }

    @Test func successfulForegroundActionWithoutASurfaceSettlesWithoutCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shortcut-no-surface-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root.appending(path: "Extensions"))
        let initialization = HanlinScriptingPlatform.Initialization(
            registerExpoDefines: {}, makeExtensionStore: { store }, enqueuePublication: { $0() })
        let owner = HanlinScriptingPlatform(rootOverride: root, initialization: initialization,
            registersForegroundContinuation: false)
        let child = HanlinScriptingPlatform(rootOverride: root, initialization: initialization,
            registersForegroundContinuation: false)
        let input = try command(foreground: true)
        defer { owner.dismissShortcutPresentation(input.id, executionFinished: true) }
        let value = HanlinValue.object(["result": .string("NO_SURFACE_SUCCESS")])
        let result = try await HanlinInvocationExecutor(store: store).execute(input) { owned in
            try await owner.admitShortcutPresentation(child, command: owned, store: store)
            let running = try #require(try store.receipt(for: owned.id))
            await owner.settleShortcutPresentation(running)
            #expect(try store.receipt(for: owned.id)?.cancellationRequested == false)
            return value
        }
        let receipt = try #require(result)
        #expect(receipt.status == .succeeded && receipt.value == value && !receipt.cancellationRequested)
        #expect(owner.shortcutPresentation?.id == input.id && !child.presentsForegroundAction)
        owner.settleShortcutPresentation(receipt)
        #expect(owner.shortcutPresentation == nil && child.activeApplicationID == nil)
        #expect(try store.receipt(for: input.id) == receipt)
    }

    private func command(foreground: Bool = false) throws -> HanlinScriptResumeCommand {
        .init(invocation: .init(identity: .init(
            installedPackageID: try .init(validating: "installed.shortcut"), packageID: try .init(validating: "test.shortcut"),
            generation: 1, entrypointID: "app.intent"), entityID: "probe",
            continueInForeground: foreground,
            delivery: .init(appID: try .init(validating: "test.shortcut"), source: .shortcuts,
                            expiresAt: .now.addingTimeInterval(600), canPresentUI: foreground)))
    }
}
