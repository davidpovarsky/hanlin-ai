import CoreGraphics
import HanlinPresentationKit
import Testing
@testable import AI_Hanlin

@Suite("Morph composer reference geometry")
struct HanlinMorphComposerTests {
    @Test("A single layout reserves the native controls inside the input glass")
    func unifiedInputAndPanelLayout() {
        let layout = HanlinMorphGeometry.layout(availableHeight: 400, accessoryNaturalHeight: 0,
            capabilitiesHeight: 0, naturalEditorHeight: 38, toolbarHeight: 44,
            isPanelExpanded: true, isEditorExpanded: true)
        #expect(layout.editorHeight == 127)
        #expect(layout.inputHeight == 191)
        #expect(layout.inputHeight - layout.editorHeight == HanlinMorphStyle.inputChromeHeight)
        #expect(HanlinMorphGeometry.pageBudget(availableHeight: 400,
            accessoryHeight: layout.hostOverhead, inputHeight: layout.inputHeight,
            toolbarHeight: 44) == 80)
    }

    @Test("Attachments cannot displace the controls or the open panel's minimum page")
    func unifiedAccessoryBudget() {
        let layout = HanlinMorphGeometry.layout(availableHeight: 400, accessoryNaturalHeight: 1000,
            capabilitiesHeight: 42, naturalEditorHeight: 38, toolbarHeight: 44,
            isPanelExpanded: true, isEditorExpanded: false)
        #expect(layout.editorHeight == 38)
        #expect(layout.inputHeight == 102)
        #expect(layout.accessoryHeight == 35)
        #expect(layout.hostOverhead == 89)
        #expect(HanlinMorphGeometry.pageBudget(availableHeight: 400,
            accessoryHeight: layout.hostOverhead, inputHeight: layout.inputHeight,
            toolbarHeight: 44) == 80)
    }

    @Test("Keyboard resize uses the host viewport once and restores the same local layout")
    func keyboardViewportRoundTrip() {
        func layout(_ height: CGFloat) -> HanlinMorphGeometry.Layout {
            HanlinMorphGeometry.layout(availableHeight: height, accessoryNaturalHeight: 62,
                capabilitiesHeight: 0, naturalEditorHeight: 160, toolbarHeight: 44,
                isPanelExpanded: true, isEditorExpanded: true)
        }
        let original = layout(800)
        let keyboard = layout(400)
        #expect(keyboard.inputHeight < original.inputHeight)
        #expect(keyboard.inputHeight - keyboard.editorHeight == original.inputHeight - original.editorHeight)
        #expect(layout(800) == original)
        #expect(keyboard.editorHeight >= HanlinMorphStyle.editorMinimumHeight)
    }

    @Test("Natural page height is bounded by the reference viewport")
    func heightAndOverflow() {
        let limit = HanlinMorphGeometry.viewportLimit(availableHeight: 500)
        #expect(limit == 360)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 180, maxHeight: limit) == 180)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 600, maxHeight: limit) == limit)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: nil, maxHeight: limit) == nil)
        #expect(HanlinMorphGeometry.viewportLimit(availableHeight: 20) == 80)
    }

    @Test("Page budget accounts for keyboard-adjusted space, editor, accessories and toolbar")
    func remainingViewportBudget() {
        let ordinary = HanlinMorphGeometry.pageBudget(availableHeight: 800, accessoryHeight: 0, inputHeight: 120, toolbarHeight: 44)
        let expanded = HanlinMorphGeometry.pageBudget(availableHeight: 800, accessoryHeight: 130, inputHeight: 260, toolbarHeight: 44)
        let keyboard = HanlinMorphGeometry.pageBudget(availableHeight: 400, accessoryHeight: 130, inputHeight: 260, toolbarHeight: 60)
        #expect(ordinary == 551)
        #expect(expanded == 281)
        #expect(keyboard == 0)
        #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 900, maxHeight: expanded) == expanded)
        #expect(HanlinMorphGeometry.accessoryBudget(availableHeight: 400, inputHeight: 260, toolbarHeight: 60, isExpanded: true) == 0)
        #expect(HanlinMorphGeometry.accessoryBudget(availableHeight: 800, inputHeight: 260, toolbarHeight: 44, isExpanded: true) == 325)
    }

    @Test("Editor budget shares the bubble viewport with measured controls, attachments and expanded panel")
    func editorAndShellShareViewport() {
        let roomy = HanlinMorphGeometry.editorBudget(availableHeight: 800, accessoryHeight: 60, inputHeight: 260, editorHeight: 180, toolbarHeight: 44, isExpanded: false)
        #expect(roomy == 634)
        #expect(roomy > 226, "A large font may grow past the old fixed composer cap")
        let keyboard = HanlinMorphGeometry.editorBudget(availableHeight: 400, accessoryHeight: 52, inputHeight: 104, editorHeight: 57, toolbarHeight: 44, isExpanded: true)
        #expect(keyboard == 92)
        // 183 = panel padding/gaps + 44pt header + the source's 80pt
        // minimum page viewport. The quick bar's 52pt is counted once.
        #expect(keyboard + (104 - 57) + 52 + 183 + 26 == 400)
        #expect(HanlinMorphGeometry.editorBudget(availableHeight: 100, accessoryHeight: 100, inputHeight: 300, editorHeight: 200, toolbarHeight: 60, isExpanded: true) == 0)
    }

    @Test("Bottom launcher remains adjacent to the editor as its internal controls grow")
    func originalLauncherConnection() {
        #expect(HanlinMorphGeometry.launcherPanelGap(inputHeight: 52) == 13)
        #expect(HanlinMorphGeometry.launcherPanelGap(inputHeight: 52) < 32)
        #expect(HanlinMorphGeometry.launcherPanelGap(inputHeight: 70) < 32)
        // With the owner-requested controls inside the field, the input
        // remains the glass bridge from the panel to the original bottom launcher.
        #expect(HanlinMorphGeometry.launcherPanelGap(inputHeight: 150) == 111)
        #expect(HanlinMorphGeometry.launcherPanelGap(inputHeight: 150) > 32)
        #expect(HanlinMorphStyle.launcherInputSpacing < HanlinMorphStyle.glassMergeDistance)
        #expect(HanlinMorphStyle.panelInputSpacing < HanlinMorphStyle.glassMergeDistance)
    }

    @Test("Native page viewport never adopts zero or non-finite geometry")
    func rejectsInvalidNativeBounds() {
        let invalidHeights: [CGFloat] = [0, 1, -1, .infinity, -.infinity, .nan]
        for invalid in invalidHeights {
            #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: invalid, maxHeight: 400) == nil)
            #expect(HanlinMorphGeometry.selectedHeight(naturalHeight: 300, maxHeight: invalid) == nil)
        }
        #expect(HanlinMorphGeometry.viewportLimit(availableHeight: .nan) == 80)
        #expect(HanlinMorphGeometry.pageBudget(availableHeight: .infinity, accessoryHeight: 0, inputHeight: 52, toolbarHeight: 44) == 0)
    }

    @Test("Keyboard-sized viewport reserves content before giving space to attachments")
    func attachmentsCannotConsumeTheOpenPage() {
        for available in [CGFloat(300), 400, 800] {
            let quickBar: CGFloat = 52
            let accessory = HanlinMorphGeometry.accessoryBudget(availableHeight: available - quickBar,
                                                               inputHeight: 52, toolbarHeight: 44, isExpanded: true)
            let external = quickBar + (accessory > 1 ? accessory + 6 : 0)
            let page = HanlinMorphGeometry.pageBudget(availableHeight: available, accessoryHeight: external,
                                                     inputHeight: 52, toolbarHeight: 44)
            #expect(page >= 67)
            if accessory > 1 { #expect(page == 80) }
            #expect(external + 52 + 44 + 85 + page <= available)
        }
    }

    @Test("The source back gesture requires a predominantly horizontal leftward drag")
    func backSwipeThreshold() {
        #expect(HanlinMorphGeometry.isBackSwipe(horizontal: -66, vertical: 10))
        #expect(!HanlinMorphGeometry.isBackSwipe(horizontal: -65, vertical: 10))
        #expect(!HanlinMorphGeometry.isBackSwipe(horizontal: 100, vertical: 0))
        #expect(!HanlinMorphGeometry.isBackSwipe(horizontal: -100, vertical: 90))
    }

    @Test("Home and detail tags remain distinct across page changes")
    func pageIdentity() {
        let home = HanlinMorphPageID<String>.home
        let first = HanlinMorphPageID.detail("tools")
        let second = HanlinMorphPageID.detail("skills")
        #expect(home != first)
        #expect(first != second)
        #expect(first == HanlinMorphPageID.detail("tools"))
    }

    @MainActor
    @Test("Inner navigation returns through live coordinator without closing the bubble")
    func coordinatorNavigationPreservesOpenState() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.open(.general)
        #expect(coordinator.morphRoute == nil)
        coordinator.pushGeneralSubroute(.prompts, reduceMotion: true)
        #expect(coordinator.morphRoute == .general(.prompts))
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == nil)
        #expect(coordinator.activePopup == .general)

        coordinator.switchFromGeneralToTools()
        #expect(coordinator.morphRoute == .tools(nil))
        coordinator.pushToolsSubroute(.skillsCenter, reduceMotion: true)
        #expect(coordinator.morphRoute == .tools(.skillsCenter))
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == .tools(nil))
        #expect(coordinator.activePopup == .tools)
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == nil)
        #expect(coordinator.activePopup == .general)
    }

    @MainActor
    @Test("Each capability settings route stays in the same open bubble")
    func capabilityRoutesReturnToOpenHome() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.open(.general)
        for route in [ComposerGeneralSubroute.search, .thinking, .creative, .miniApps] {
            coordinator.pushGeneralSubroute(route, reduceMotion: true)
            #expect(coordinator.morphRoute == .general(route))
            #expect(coordinator.activePopup == .general)
            coordinator.returnFromMorphPage()
            #expect(coordinator.morphRoute == nil)
            #expect(coordinator.activePopup == .general)
        }
        coordinator.switchFromGeneralToTools()
        coordinator.pushToolsSubroute(.mcpServers, reduceMotion: true)
        #expect(coordinator.morphRoute == .tools(.mcpServers))
        coordinator.returnFromMorphPage()
        #expect(coordinator.morphRoute == .tools(nil))
        #expect(coordinator.activePopup == .tools)
    }

    @Test("Expanded editor stays within the keyboard-adjusted remaining budget")
    func expandedEditorFitsRemainingViewport() {
        #expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: 900, editorBudget: 650) == 630)
        #expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: 400, editorBudget: 169) == 169)
        #expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: 200, editorBudget: 50) == 50)
        #expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: 0, editorBudget: 0) == 0)
        #expect(HanlinMorphGeometry.expandedEditorHeight(availableHeight: .nan, editorBudget: .infinity) == 0)
    }

    @MainActor
    @Test("Model presentation and editor focus preserve the exact open action page")
    func modelAndFocusKeepDrawerOpen() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.open(.tools)
        coordinator.pushToolsSubroute(.skillsCenter, reduceMotion: true)
        coordinator.open(.model)
        #expect(coordinator.isModelPresented)
        #expect(coordinator.activePopup == .tools)
        #expect(coordinator.morphRoute == .tools(.skillsCenter))
        coordinator.dockState.handleInputFocusChange(true, preserveExpandedDrawer: true)
        #expect(coordinator.dockState.mode == .tools)
        coordinator.close(.model)
        #expect(!coordinator.isModelPresented)
        #expect(coordinator.morphRoute == .tools(.skillsCenter))
        coordinator.open(.tools)
        #expect(coordinator.morphRoute == .tools(.skillsCenter), "An already-open tools control must not close or reset its page")

        coordinator.switchFromToolsToGeneral()
        coordinator.pushGeneralSubroute(.miniApps, reduceMotion: true)
        coordinator.binding(for: .model).wrappedValue = true
        coordinator.binding(for: .model).wrappedValue = false
        #expect(coordinator.morphRoute == .general(.miniApps))
        #expect(coordinator.dockState.mode == .general)
    }
}
