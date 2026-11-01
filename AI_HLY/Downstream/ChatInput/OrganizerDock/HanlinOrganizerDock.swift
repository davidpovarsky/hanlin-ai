//
//  HanlinOrganizerDock.swift
//  AI_HLY
//
//  Source-faithful integrated OrganizerDock view ported from
//  InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift (lines 586-935).
//  Composes the back `drawer` (with top drag/tap handle and embedded General/Tools content)
//  and the front `composer` (with top resize handle, NativeMultilineTextEditor, attachments,
//  and classic toolbar) inside a single `ZStack(alignment: .bottom)`.
//

import SwiftUI

@MainActor
struct HanlinOrganizerDock<GeneralContent: View, ToolsContent: View, ComposerContent: View>: View {
    @Bindable var dockState: HanlinOrganizerDockState
    @Bindable var popupCoordinator: HanlinComposerPopupCoordinator
    let temporaryRecord: Bool
    let isResponding: Bool
    let onTapComposerBackground: () -> Void
    @ViewBuilder let generalDrawerContent: () -> GeneralContent
    @ViewBuilder let toolsDrawerContent: () -> ToolsContent
    @ViewBuilder let composerContent: () -> ComposerContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accentColor: Color {
        temporaryRecord ? .primary : .hlBluefont
    }

    private var shadowColor: Color {
        temporaryRecord ? .primary : .hlBlue
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            drawerLayer
            composerLayer
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.87),
            value: dockState.isExpanded
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.87),
            value: dockState.mode
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88),
            value: dockState.composerHeight
        )
        .onChange(of: dockState.mode) { _, newMode in
            popupCoordinator.syncFromDockModeChange(newMode)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-organizer-dock")
    }

    // MARK: - Back Layer: Drawer (ContentView.swift lines 650-692)

    private var drawerLayer: some View {
        let visibleContentHeight = max(0, dockState.panelHeight - dockState.composerHeight - 32)

        return VStack(spacing: 0) {
            // Top drawer handle bar (supports both tap and vertical drag >= 20pt, +/-34pt threshold)
            Button {
                guard !isResponding else { return }
                if reduceMotion {
                    dockState.handleDrawerHandleTap()
                } else {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.87)) {
                        dockState.handleDrawerHandleTap()
                    }
                }
            } label: {
                Capsule()
                    .fill(Color.primary.opacity(0.24))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isResponding)
            .gesture(drawerDragGesture)
            .accessibilityLabel(
                dockState.isExpanded
                ? String(localized: "Collapse organizer panel")
                : String(localized: "Expand organizer panel")
            )
            .accessibilityIdentifier("hanlin-organizer-drawer-handle")

            if dockState.isExpanded {
                Group {
                    switch dockState.mode {
                    case .general:
                        generalDrawerContent()
                    case .tools:
                        toolsDrawerContent()
                    case .collapsed:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: visibleContentHeight)
                .clipped()
                .transition(
                    .opacity.combined(with: .move(edge: .bottom))
                )
            }

            Spacer(minLength: dockState.composerHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: dockState.panelHeight, alignment: .top)
        .background(
            GlassView(style: .systemUltraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(accentColor.opacity(0.22), lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        .shadow(color: shadowColor.opacity(0.16), radius: 5, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-organizer-drawer")
    }

    private var drawerDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard !isResponding else { return }
                if reduceMotion {
                    dockState.handleDrawerDragEnded(translationHeight: value.translation.height)
                } else {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.87)) {
                        dockState.handleDrawerDragEnded(translationHeight: value.translation.height)
                    }
                }
            }
    }

    // MARK: - Front Layer: Composer (ContentView.swift lines 750-805 & 906-933)

    private var composerLayer: some View {
        VStack(spacing: 0) {
            // Separate editor resize handle (`minimumDistance: 7`, `+/-72pt` accessibility step)
            Capsule()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 32, height: 4)
                .frame(width: 82, height: 20)
                .contentShape(Rectangle())
                .padding(.top, 3)
                .gesture(composerResizeGesture)
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Text box size handle"))
                .accessibilityHint(String(localized: "Swipe up or down to adjust the message input height."))
                .accessibilityIdentifier("hanlin-composer-resize-handle")
                .accessibilityAdjustableAction { direction in
                    if reduceMotion {
                        dockState.adjustComposerHeightByAccessibility(increment: direction == .increment)
                    } else {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                            dockState.adjustComposerHeightByAccessibility(increment: direction == .increment)
                        }
                    }
                }

            composerContent()

            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .frame(minHeight: dockState.composerHeight, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .onTapGesture(perform: onTapComposerBackground)
        .background(
            GlassView(style: .systemUltraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(accentColor.opacity(0.24), lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        .shadow(color: shadowColor, radius: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-organizer-composer-shell")
    }

    private var composerResizeGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { value in
                dockState.handleComposerResizeChanged(translationHeight: value.translation.height)
            }
            .onEnded { _ in
                if reduceMotion {
                    dockState.handleComposerResizeEnded()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                        dockState.handleComposerResizeEnded()
                    }
                }
            }
    }
}
