import XCTest
@testable import HanlinChatPresentation

final class HanlinChatPresentationTests: XCTestCase {
    func testSingleModePolicies() {
        var sheet = HanlinChatPresentationState(policy: .init(modes: [.sheet], initialMode: .inspector))
        sheet.open()
        XCTAssertEqual(sheet.mode, .sheet)
        sheet.request(.inspector)
        XCTAssertEqual(sheet.mode, .sheet)
        XCTAssertNil(sheet.policy.alternative(to: .sheet))
        var inspector = HanlinChatPresentationState(policy: .init(modes: [.inspector]))
        inspector.open()
        XCTAssertEqual(inspector.mode, .inspector)
        XCTAssertNil(inspector.policy.alternative(to: .inspector))
    }

    func testBidirectionalHandoffWaitsForDismissal() {
        var state = HanlinChatPresentationState()
        state.open()
        state.request(.inspector)
        XCTAssertEqual(state.phase, .dismissing(.sheet, next: .inspector))
        XCTAssertFalse(state.isShowing(.sheet))
        XCTAssertFalse(state.isShowing(.inspector))
        state.finishDismissal(.inspector)
        XCTAssertTrue(state.isTransitioning)
        state.finishDismissal(.sheet)
        XCTAssertEqual(state.mode, .inspector)
        state.request(.sheet)
        XCTAssertEqual(state.phase, .dismissing(.inspector, next: .sheet))
        state.finishDismissal(.inspector)
        XCTAssertEqual(state.mode, .sheet)
        state.finishDismissal(.inspector)
        XCTAssertEqual(state.mode, .sheet)
    }

    func testCancellationAndNativeDismissal() {
        var state = HanlinChatPresentationState()
        state.open()
        state.request(.inspector)
        state.close()
        state.finishDismissal(.sheet)
        XCTAssertEqual(state.phase, .closed)
        state.open(.inspector)
        state.systemDismissed(.inspector)
        state.finishDismissal(.inspector)
        XCTAssertEqual(state.phase, .closed)
    }

    func testLauncherVisibilityAcrossAllModesAndHandoffs() {
        for initial in HanlinChatPresentationMode.allCases {
            var state = HanlinChatPresentationState(policy: .init(initialMode: initial))
            XCTAssertTrue(state.showsLauncher)
            state.open()
            XCTAssertFalse(state.showsLauncher)
            let other: HanlinChatPresentationMode = initial == .sheet ? .inspector : .sheet
            state.request(other)
            XCTAssertFalse(state.showsLauncher)
            state.finishDismissal(other)
            XCTAssertFalse(state.showsLauncher)
            state.finishDismissal(initial)
            XCTAssertEqual(state.mode, other)
            XCTAssertFalse(state.showsLauncher)
            state.close()
            XCTAssertFalse(state.showsLauncher)
            state.finishDismissal(other)
            XCTAssertTrue(state.showsLauncher)
        }
    }

    func testLauncherVisibilityAfterNativeDismissal() {
        for mode in HanlinChatPresentationMode.allCases {
            var state = HanlinChatPresentationState(policy: .init(modes: [mode]))
            state.open()
            XCTAssertFalse(state.showsLauncher)
            state.systemDismissed(mode)
            XCTAssertFalse(state.showsLauncher)
            state.finishDismissal(mode)
            XCTAssertTrue(state.showsLauncher)
        }
    }

    func testZoomVisualSourceReturnsOnlyForFinalSheetDismissal() {
        var state = HanlinChatPresentationState()
        XCTAssertTrue(state.launcherIsVisible(usesZoom: true))
        state.open(.sheet)
        XCTAssertFalse(state.launcherIsVisible(usesZoom: true))
        state.request(.inspector)
        XCTAssertFalse(state.launcherIsVisible(usesZoom: true))
        state.finishDismissal(.sheet)
        XCTAssertFalse(state.launcherIsVisible(usesZoom: true))
        state.request(.sheet)
        XCTAssertFalse(state.launcherIsVisible(usesZoom: true))
        state.finishDismissal(.inspector)
        state.close()
        XCTAssertTrue(state.launcherIsVisible(usesZoom: true))
        XCTAssertFalse(state.launcherIsVisible(usesZoom: false))
        XCTAssertFalse(state.showsLauncher)
        state.finishDismissal(.sheet)
        XCTAssertTrue(state.showsLauncher)
        XCTAssertTrue(state.launcherIsVisible(usesZoom: true))
    }

    func testEmptyPolicyAndActiveReconfiguration() {
        var state = HanlinChatPresentationState(policy: .init(modes: [], initialMode: .inspector))
        XCTAssertEqual(state.policy.initialMode, .sheet)
        state.open()
        XCTAssertFalse(state.configure(.init(modes: [.inspector])))
        state.close()
        state.finishDismissal(.sheet)
        XCTAssertTrue(state.configure(.init(modes: [.inspector])))
        state.open()
        XCTAssertEqual(state.mode, .inspector)
    }
}
