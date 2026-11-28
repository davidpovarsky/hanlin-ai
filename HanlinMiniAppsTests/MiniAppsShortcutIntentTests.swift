import AppIntents
import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinWidgetUI
import Testing
import UniformTypeIdentifiers
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

    @Test func nativeListInputUsesOnlyTheSelectedParameter() throws {
        var intent = HanlinRunMiniAppShortcutIntent()
        intent.input = "not JSON; ignored for native lists"
        intent.textItems = ["שלום", "", "{\"key\":1}"]
        intent.integerItems = [9_007_199_254_740_993, -7]
        intent.numberItems = [1.25, -0.0]
        intent.booleanItems = [false, true]

        intent.inputType = .textList
        #expect(try intent.decodedInputValue() == .array([.string("שלום"), .string(""), .string("{\"key\":1}")]))
        intent.inputType = .integerList
        #expect(try intent.decodedInputValue() == .array([.integer(9_007_199_254_740_993), .integer(-7)]))
        intent.inputType = .booleanList
        #expect(try intent.decodedInputValue() == .array([.bool(false), .bool(true)]))
        intent.inputType = .numberList
        let value = try intent.decodedInputValue()
        guard case .array(let numbers) = value, numbers.count == 2,
              case .number(let first) = numbers[0], case .number(let second) = numbers[1] else {
            Issue.record("Expected the selected native Double list"); return
        }
        #expect(first == 1.25 && second.bitPattern == (-0.0 as Double).bitPattern)
        intent.numberItems = [.infinity]
        #expect(throws: HanlinContractError.self) { try intent.decodedInputValue() }
    }

    @Test func absentAndExplicitlyEmptyNativeListsKeepLegacyDefaults() throws {
        var intent = HanlinRunMiniAppShortcutIntent()
        #expect(intent.inputType == .text && intent.input == "" && !intent.allowLongRunning)
        #expect(intent.jsonFile == nil)
        #expect(intent.textItems == nil && intent.integerItems == nil && intent.numberItems == nil && intent.booleanItems == nil)
        #expect(MiniAppsShortcutInputType(rawValue: "text") == .text)
        #expect(MiniAppsShortcutInputType(rawValue: "json") == .json)
        #expect(MiniAppsShortcutInputType(rawValue: "jsonFile") == .jsonFile)
        for type in [MiniAppsShortcutInputType.textList, .integerList, .numberList, .booleanList] {
            intent.inputType = type
            #expect(try intent.decodedInputValue() == .array([]))
        }
        intent.textItems = []; intent.integerItems = []; intent.numberItems = []; intent.booleanItems = []
        for type in [MiniAppsShortcutInputType.textList, .integerList, .numberList, .booleanList] {
            intent.inputType = type
            #expect(try intent.decodedInputValue() == .array([]))
        }
    }

    @Test func legacyInputBranchesKeepTextJSONAndFileSemantics() throws {
        var intent = HanlinRunMiniAppShortcutIntent()
        intent.input = "{}"
        intent.numberItems = [.infinity] // Unselected native inputs cannot reject legacy text.
        #expect(try intent.decodedInputValue() == .string("{}"))
        intent.inputType = .json
        intent.input = #"{"עברית":[true,7,null,{"nested":[]}]}"#
        let expected = HanlinValue.object(["עברית": .array([.bool(true), .integer(7), .null, .object(["nested": .array([])])])])
        #expect(try intent.decodedInputValue() == expected)
        intent.inputType = .jsonFile
        #expect(throws: MiniAppsShortcutError.self) { try intent.decodedInputValue() }
        intent.jsonFile = IntentFile(data: Data([0xff]), filename: "invalid.json", type: .json)
        #expect(throws: MiniAppsShortcutError.self) { try intent.decodedInputValue() }
        intent.jsonFile = IntentFile(data: Data(intent.input.utf8), filename: "input.json", type: .json)
        #expect(try intent.decodedInputValue() == expected)
    }

    @Test(arguments: ["en", "he", "zh-Hans"])
    func nativeListLabelsLoadActualHostTranslations(language: String) throws {
        let keys = ["Text List", "Integer List", "Number List", "Boolean List"]
        let expected = [
            "en": keys,
            "he": ["רשימת טקסט", "רשימת מספרים שלמים", "רשימת מספרים עשרוניים", "רשימת ערכי אמת ושקר"],
            "zh-Hans": ["文本列表", "整数列表", "数值列表", "布尔值列表"]
        ]
        let localeURL = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let bundle = try #require(Bundle(url: localeURL))
        let values = try #require(expected[language])
        for (key, value) in zip(keys, values) {
            #expect(bundle.localizedString(forKey: key, value: nil, table: "HanlinAppIntents") == value)
        }
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
