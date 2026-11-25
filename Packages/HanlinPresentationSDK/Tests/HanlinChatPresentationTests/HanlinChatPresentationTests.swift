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

    func testCompactUsesExistingSheetForEveryConfiguredPolicy() {
        for modes: Set<HanlinChatPresentationMode> in [[.sheet], [.inspector], [.sheet, .inspector]] {
            for initial in HanlinChatPresentationMode.allCases {
                let policy = HanlinChatPresentationPolicy(modes: modes, initialMode: initial)
                var state = HanlinChatPresentationState(policy: policy, isInspectorAvailable: false)
                XCTAssertEqual(state.effectivePolicy.modes, [.sheet])
                XCTAssertEqual(state.effectivePolicy.initialMode, .sheet)
                XCTAssertNil(state.effectivePolicy.alternative(to: .sheet))
                state.open()
                XCTAssertEqual(state.mode, .sheet)
                state.request(.inspector)
                XCTAssertEqual(state.mode, .sheet)
                state.close()
                state.finishDismissal(.sheet)
                if modes.contains(.inspector) {
                    state.open(.inspector)
                    XCTAssertEqual(state.mode, .sheet)
                    state.close()
                    state.finishDismissal(.sheet)
                }
                state.updateInspectorAvailability(true)
                XCTAssertEqual(state.effectivePolicy, policy)
                state.open()
                XCTAssertEqual(state.mode, policy.initialMode)
            }
        }
    }

    func testLiveInspectorNarrowsThroughExistingHandoff() {
        var state = HanlinChatPresentationState()
        state.open(.inspector)
        state.updateInspectorAvailability(false)
        XCTAssertEqual(state.phase, .dismissing(.inspector, next: .sheet))
        XCTAssertFalse(state.showsLauncher)
        XCTAssertFalse(state.launcherIsVisible(usesZoom: true))
        state.finishDismissal(.sheet)
        XCTAssertTrue(state.isTransitioning)
        state.finishDismissal(.inspector)
        XCTAssertEqual(state.mode, .sheet)
        XCTAssertNil(state.effectivePolicy.alternative(to: .sheet))
        state.updateInspectorAvailability(true)
        XCTAssertEqual(state.mode, .sheet)
        XCTAssertEqual(state.effectivePolicy.alternative(to: .sheet), .inspector)
    }

    func testPendingInspectorIsRedirectedAndCloseDoesNotReopen() {
        var state = HanlinChatPresentationState()
        state.open(.sheet)
        state.request(.inspector)
        state.updateInspectorAvailability(false)
        XCTAssertEqual(state.phase, .dismissing(.sheet, next: .sheet))
        state.finishDismissal(.sheet)
        XCTAssertEqual(state.mode, .sheet)
        state.close()
        state.updateInspectorAvailability(true)
        state.finishDismissal(.sheet)
        XCTAssertTrue(state.showsLauncher)
    }

    func testInspectorOnlyPolicyRestoresWhenRegular() {
        var state = HanlinChatPresentationState(policy: .init(modes: [.inspector]), isInspectorAvailable: false)
        state.open()
        XCTAssertEqual(state.mode, .sheet)
        state.updateInspectorAvailability(true)
        XCTAssertEqual(state.phase, .dismissing(.sheet, next: .inspector))
        state.finishDismissal(.sheet)
        XCTAssertEqual(state.mode, .inspector)
        XCTAssertNil(state.effectivePolicy.alternative(to: .inspector))
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
