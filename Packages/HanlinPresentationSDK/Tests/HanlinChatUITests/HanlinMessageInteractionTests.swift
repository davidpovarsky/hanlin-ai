import Foundation
import Testing
@testable import HanlinChatUI

@Suite("Shared original message preview geometry")
struct HanlinMessagePreviewMetricsTests {
    @Test func narrowAndShortHostViewportWinsOverPreferredSize() {
        let value = HanlinMessagePreviewMetrics.fitting(
            preferredWidth: 800, windowWidth: 320, windowHeight: 240)
        #expect(value?.width == 272)
        #expect(value?.height == 160)
    }

    @Test func detachedInvalidOrNonfiniteViewportDoesNotPresent() {
        #expect(HanlinMessagePreviewMetrics.fitting(
            preferredWidth: 400, windowWidth: .nan, windowHeight: 800) == nil)
        #expect(HanlinMessagePreviewMetrics.fitting(
            preferredWidth: 400, windowWidth: 48, windowHeight: 800) == nil)
        #expect(HanlinMessagePreviewMetrics.fitting(
            preferredWidth: 400, windowWidth: 800, windowHeight: 80) == nil)
        #expect(HanlinMessagePreviewMetrics.fitting(
            preferredWidth: .infinity, windowWidth: 1024, windowHeight: 1366)?.width == 480)
    }
}

#if canImport(UIKit)
@MainActor
@Suite("Shared original message action host authority")
struct HanlinMessageActionTests {
    @Test func unavailableHostServicesNeverCreateMenuEntries() {
        let empty = HanlinMessageActions()
        #expect(empty.userMenu.isEmpty)
        #expect(empty.assistantMenu().isEmpty)
        let readOnly = HanlinMessageActions(copy: {}, select: {})
        #expect(readOnly.userMenu.map(\.id) == ["copy", "select"])
        #expect(readOnly.assistantMenu().map(\.id) == ["copy", "select"])
    }

    @Test func menusRetainTheirCreatingHostCallbacks() {
        var firstCalls = 0
        var secondCalls = 0
        let first = HanlinMessageActions(copy: { firstCalls += 1 })
        let second = HanlinMessageActions(copy: { secondCalls += 1 })
        first.userMenu.first?.perform()
        #expect(firstCalls == 1)
        #expect(secondCalls == 0)
        second.assistantMenu().first?.perform()
        #expect(firstCalls == 1)
        #expect(secondCalls == 1)
    }

    @Test func currentHostStateControlsTranslationAndSourceBoundSaving() {
        let actions = HanlinMessageActions(translate: {}, savePersonal: {})
        let unavailable = actions.assistantMenu(state: .init(isTranslating: true, canSavePersonal: false))
        #expect(unavailable.map(\.isEnabled) == [false, false])
        #expect(actions.assistantMenu().allSatisfy(\.isEnabled))
        #expect(unavailable.map(\.id) == ["translate", "save-personal"])
    }
}
#endif
