// Adapted from Hanlin_Composer_MorphView_Bubble_Experiment.swift, SHA-256:
// 51bb10cdf71ee1c10cac8108f602eee4b34e78967de23dc437985aa89db9bbbb.
// The authorized ChatViewBottom host supplies live editor, action, navigation
// and session state; this component does not own those values.

import SwiftUI
import HanlinPresentationKit

public enum HanlinMorphPageID<Page: Hashable>: Hashable {
    case home
    case detail(Page)
}

public enum HanlinMorphGeometry {
    private static func finiteHeight(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }

    public static func viewportLimit(availableHeight: CGFloat) -> CGFloat {
        max(HanlinMorphStyle.minimumPageHeight, finiteHeight(availableHeight) * 0.72)
    }

    public static func selectedHeight(naturalHeight: CGFloat?, maxHeight: CGFloat) -> CGFloat? {
        guard let naturalHeight, naturalHeight.isFinite, naturalHeight > 1,
              maxHeight.isFinite, maxHeight > 1 else { return nil }
        return min(naturalHeight, maxHeight)
    }

    /// The launcher keeps its original bottom anchor. A taller input still
    /// merges with both its adjacent launcher and the panel above it.
    public static func launcherPanelGap(inputHeight: CGFloat) -> CGFloat {
        HanlinMorphStyle.panelInputSpacing
            + max(0, finiteHeight(inputHeight) - HanlinMorphStyle.launcherSize)
    }

    public static func pageBudget(availableHeight: CGFloat, accessoryHeight: CGFloat, inputHeight: CGFloat, toolbarHeight: CGFloat) -> CGFloat {
        let available = finiteHeight(availableHeight)
        // The caller accounts for visible accessory gaps once. The toolbar
        // inside the editor is already included in measured inputHeight.
        let chrome = HanlinMorphStyle.panelInset * 2 + HanlinMorphStyle.panelContentSpacing
            + HanlinMorphStyle.panelInputSpacing + HanlinMorphStyle.topInset + HanlinMorphStyle.bottomInset
        let remaining = available - finiteHeight(accessoryHeight)
            - max(HanlinMorphStyle.launcherSize, finiteHeight(inputHeight))
            - finiteHeight(toolbarHeight) - chrome
        return max(0, min(viewportLimit(availableHeight: available), remaining))
    }

    public static func accessoryBudget(availableHeight: CGFloat, inputHeight: CGFloat, toolbarHeight: CGFloat, isExpanded: Bool) -> CGFloat {
        let panelChrome: CGFloat = isExpanded
            ? HanlinMorphStyle.panelInset * 2 + HanlinMorphStyle.panelContentSpacing
                + HanlinMorphStyle.panelInputSpacing + finiteHeight(toolbarHeight) + HanlinMorphStyle.minimumPageHeight
            : 0
        let shellAndAccessoryGap = HanlinMorphStyle.topInset + HanlinMorphStyle.bottomInset + HanlinMorphStyle.hostSpacing
        return max(0, finiteHeight(availableHeight) - max(HanlinMorphStyle.launcherSize, finiteHeight(inputHeight))
                   - panelChrome - shellAndAccessoryGap)
    }

    /// The editor and its enclosing bubble share the same remaining viewport.
    /// The input's other controls are measured, so Dynamic Type and chrome changes
    /// do not rely on a guessed fixed editor-to-bubble offset.
    public static func editorBudget(availableHeight: CGFloat, accessoryHeight: CGFloat, inputHeight: CGFloat, editorHeight: CGFloat, toolbarHeight: CGFloat, isExpanded: Bool) -> CGFloat {
        let inputChrome = max(0, finiteHeight(inputHeight) - finiteHeight(editorHeight))
        let panelChrome: CGFloat = isExpanded
            ? HanlinMorphStyle.panelInset * 2 + HanlinMorphStyle.panelContentSpacing
                + HanlinMorphStyle.panelInputSpacing + finiteHeight(toolbarHeight) + HanlinMorphStyle.minimumPageHeight
            : 0
        let shellInsets = HanlinMorphStyle.topInset + HanlinMorphStyle.bottomInset
        return max(0, finiteHeight(availableHeight) - finiteHeight(accessoryHeight) - inputChrome - panelChrome - shellInsets)
    }

    /// Grow the existing native editor within the keyboard-adjusted budget.
    /// Even a short draft fills the expanded surface; longer text scrolls there.
    public static func expandedEditorHeight(availableHeight: CGFloat, editorBudget: CGFloat) -> CGFloat {
        let budget = finiteHeight(editorBudget)
        let desired = max(HanlinMorphStyle.expandedEditorMinimumHeight,
                          finiteHeight(availableHeight) * HanlinMorphStyle.expandedEditorFraction)
        return min(budget, desired)
    }

    public static func isBackSwipe(horizontal: CGFloat, vertical: CGFloat) -> Bool {
        horizontal < -65 && abs(horizontal) > abs(vertical) * 1.2
    }
}

/// Reference shell with caller-supplied, live content. This view owns no draft,
/// model, attachment or action state.
@MainActor
public struct HanlinMorphComposer<Page: Hashable, Home: View, Detail: View, Input: View>: View {
    @Binding var isExpanded: Bool
    @Binding var activePage: Page?
    let availableHeight: CGFloat
    let accessoryHeight: CGFloat
    let title: (Page?) -> String
    let subtitle: (Page?) -> String
    let backIdentifier: (Page) -> String
    let onOpen: () -> Void
    let onBackgroundTap: () -> Void
    let onInputHeightChange: (CGFloat) -> Void
    let onToolbarHeightChange: (CGFloat) -> Void
    var isEnabled: Bool = true
    @ViewBuilder let home: () -> Home
    @ViewBuilder let detail: (Page) -> Detail
    @ViewBuilder let input: () -> Input

    @Namespace private var glassNamespace
    @State private var swipeOffset: CGFloat = 0
    @State private var measuredInputHeight: CGFloat = 52
    @State private var measuredToolbarHeight: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isExpanded: Binding<Bool>,
        activePage: Binding<Page?>,
        availableHeight: CGFloat,
        accessoryHeight: CGFloat,
        title: @escaping (Page?) -> String,
        subtitle: @escaping (Page?) -> String,
        backIdentifier: @escaping (Page) -> String,
        onOpen: @escaping () -> Void,
        onBackgroundTap: @escaping () -> Void,
        onInputHeightChange: @escaping (CGFloat) -> Void,
        onToolbarHeightChange: @escaping (CGFloat) -> Void,
        isEnabled: Bool = true,
        @ViewBuilder home: @escaping () -> Home,
        @ViewBuilder detail: @escaping (Page) -> Detail,
        @ViewBuilder input: @escaping () -> Input
    ) {
        self._isExpanded = isExpanded
        self._activePage = activePage
        self.availableHeight = availableHeight
        self.accessoryHeight = accessoryHeight
        self.title = title
        self.subtitle = subtitle
        self.backIdentifier = backIdentifier
        self.onOpen = onOpen
        self.onBackgroundTap = onBackgroundTap
        self.onInputHeightChange = onInputHeightChange
        self.onToolbarHeightChange = onToolbarHeightChange
        self.isEnabled = isEnabled
        self.home = home
        self.detail = detail
        self.input = input
    }

    private let blue = HanlinMorphStyle.blue
    private let azure = HanlinMorphStyle.azure

    private var pageID: HanlinMorphPageID<Page> {
        activePage.map(HanlinMorphPageID.detail) ?? .home
    }

    public var body: some View {
        GlassEffectContainer(spacing: HanlinMorphStyle.glassMergeDistance) {
            VStack(spacing: HanlinMorphStyle.panelInputSpacing) {
                if isExpanded {
                    panel
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom))
                        ))
                }
                HStack(alignment: .bottom, spacing: HanlinMorphStyle.launcherInputSpacing) {
                    Button {
                        let opening = !isExpanded
                        withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.79)) {
                            isExpanded.toggle()
                            if !isExpanded { activePage = nil; swipeOffset = 0 }
                        }
                        if opening { onOpen() }
                    } label: {
                        Image(systemName: "plus")
                            .font(HanlinTypography.fixed(size: 21, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 45 : 0))
                            .frame(width: HanlinMorphStyle.launcherSize, height: HanlinMorphStyle.launcherSize)
                            .contentShape(Circle())
                            .accessibilityIdentifier("composer-plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEnabled)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .glassEffectID("composer-launcher", in: glassNamespace)
                    .overlay { Circle().strokeBorder(blue.opacity(0.30), lineWidth: 0.8).allowsHitTesting(false) }
                    .accessibilityLabel(isExpanded ? String(localized: "Close action center") : String(localized: "Open action center"))
                    .accessibilityIdentifier("hanlin-composer-general-menu")

                    // The host supplies the actual editor and send/stop controls.
                    input()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: HanlinMorphStyle.launcherSize)
                        .layoutPriority(1)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard height.isFinite, height > 1, abs(height - measuredInputHeight) > 1 else { return }
                            measuredInputHeight = height
                            onInputHeightChange(height)
                        }
                        .background {
                            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onBackgroundTap)
                        }
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: HanlinMorphStyle.inputCornerRadius, style: .continuous))
                        .glassEffectID("composer-input", in: glassNamespace)
                        .overlay {
                            RoundedRectangle(cornerRadius: HanlinMorphStyle.inputCornerRadius, style: .continuous)
                                .strokeBorder(blue.opacity(0.30), lineWidth: 0.8)
                                .allowsHitTesting(false)
                        }
                }
            }
        }
        .padding(.horizontal, HanlinMorphStyle.horizontalInset)
        .padding(.top, HanlinMorphStyle.topInset)
        .padding(.bottom, HanlinMorphStyle.bottomInset)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: HanlinMorphStyle.panelContentSpacing) {
            toolbar
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard height.isFinite, height > 1, abs(height - measuredToolbarHeight) > 1 else { return }
                    measuredToolbarHeight = height
                    onToolbarHeightChange(height)
                }
            HanlinMorphMeasuredPages(id: pageID, maxHeight: HanlinMorphGeometry.pageBudget(
                availableHeight: availableHeight,
                accessoryHeight: accessoryHeight,
                inputHeight: measuredInputHeight,
                toolbarHeight: measuredToolbarHeight
            )) {
                VStack(alignment: .leading, spacing: 14) {
                    if dynamicTypeSize.isAccessibilitySize { toolbarText }
                    home()
                }
                .tag(HanlinMorphPageID<Page>.home)
                if let page = activePage {
                    VStack(alignment: .leading, spacing: 14) {
                        if dynamicTypeSize.isAccessibilitySize { toolbarText }
                        detail(page)
                    }
                    .offset(x: swipeOffset)
                    .tag(HanlinMorphPageID<Page>.detail(page))
                }
            }
            .overlay(alignment: .leading) {
                if activePage != nil {
                    Color.clear.frame(width: 24).contentShape(Rectangle())
                        .highPriorityGesture(edgeBackGesture)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HanlinMorphStyle.panelInset)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: HanlinMorphStyle.panelCornerRadius, style: .continuous))
        .glassEffectID("composer-panel", in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
        .overlay {
            RoundedRectangle(cornerRadius: HanlinMorphStyle.panelCornerRadius, style: .continuous)
                .strokeBorder(blue.opacity(0.26), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        // Keep the panel addressable without replacing the native toolbar and
        // page controls' own identifiers in the accessibility hierarchy.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("morphing-action-panel")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if activePage != nil {
                Button(action: goBack) {
                    Image(systemName: "chevron.right")
                        .font(HanlinTypography.subheadline.weight(.semibold))
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(azure)
                .accessibilityLabel(String(localized: "Back"))
                .accessibilityIdentifier(activePage.map(backIdentifier) ?? "composer-toolbar-back")
                .id(activePage)
            } else {
                Image(systemName: "square.grid.3x2.fill").foregroundStyle(azure)
            }
            // Accessibility text participates in the page's native scrolling.
            // A fixed multi-line heading must not consume its entire viewport.
            if !dynamicTypeSize.isAccessibilitySize { toolbarText }
            Spacer(minLength: 0)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                    isExpanded = false
                    activePage = nil
                    swipeOffset = 0
                }
            } label: {
                Image(systemName: "chevron.down").font(HanlinTypography.subheadline.weight(.medium))
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(azure)
            .accessibilityLabel(String(localized: "Close action center"))
            .accessibilityIdentifier("composer-toolbar-close")
        }
        .padding(.horizontal, 3)
    }

    private var toolbarText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(activePage)).font(HanlinTypography.headline.weight(.semibold))
            Text(subtitle(activePage)).font(HanlinTypography.caption).foregroundStyle(.secondary)
        }
        .contentTransition(.identity)
        .transaction { $0.animation = nil }
    }

    private func goBack() {
        swipeOffset = 0
        activePage = nil
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                if dx < 0 && abs(dx) > abs(value.translation.height) * 1.2 {
                    swipeOffset = max(-180, dx)
                }
            }
            .onEnded { value in
                if HanlinMorphGeometry.isBackSwipe(horizontal: value.translation.width, vertical: value.translation.height) {
                    goBack()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.84)) {
                        swipeOffset = 0
                    }
                }
            }
    }
}

/// The reference's tagged-child measurement: only the outer viewport animates;
/// page content switches immediately and keeps its natural size.
private struct HanlinMorphMeasuredPages<ID: Hashable, Content: View>: View {
    let id: ID
    let maxHeight: CGFloat
    let content: Content
    @State private var measuredHeights: [ID: CGFloat] = [:]
    @State private var animatedHeight: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(id: ID, maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.id = id
        self.maxHeight = maxHeight
        self.content = content()
    }

    private var naturalHeight: CGFloat? { measuredHeights[id] }
    private var selectedHeight: CGFloat? {
        HanlinMorphGeometry.selectedHeight(naturalHeight: naturalHeight, maxHeight: maxHeight)
    }

    @ViewBuilder
    var body: some View {
        // Window/keyboard changes can briefly leave no space for a page.
        // Do not attach a HostingScrollView with zero or non-finite bounds.
        if maxHeight.isFinite, maxHeight > 1 {
            measuredScrollView
        }
    }

    private var measuredScrollView: some View {
        ScrollView(.vertical, showsIndicators: (naturalHeight ?? 0) > maxHeight) {
            ZStack(alignment: .topLeading) {
                ForEach(subviews: content) { child in
                    let childID = child.containerValues.tag(for: ID.self)
                    child
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { value in
                            guard let childID, value.isFinite, value > 1 else { return }
                            if abs(value - (measuredHeights[childID] ?? 0)) > 0.5 {
                                measuredHeights[childID] = value
                            }
                        }
                        .opacity(childID == id ? 1 : 0)
                        .allowsHitTesting(childID == id)
                        .accessibilityHidden(childID != id)
                        .transaction(value: id) { $0.animation = nil }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: naturalHeight, alignment: .top)
        }
        .accessibilityIdentifier("hanlin-composer-page-scroll")
        .frame(height: HanlinMorphGeometry.selectedHeight(naturalHeight: animatedHeight, maxHeight: maxHeight) ?? maxHeight,
               alignment: .top)
        .clipped()
        .onChange(of: selectedHeight) { _, target in adoptHeight(target) }
        .onChange(of: id) { _, _ in adoptHeight(selectedHeight) }
        .onChange(of: maxHeight) { _, _ in adoptHeight(selectedHeight) }
        .onAppear { adoptHeight(selectedHeight) }
    }

    private func adoptHeight(_ target: CGFloat?) {
        guard let target, target.isFinite, target > 1 else { return }
        if let previous = animatedHeight {
            guard abs(target - previous) > 0.5 else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.54, dampingFraction: 0.84)) {
                animatedHeight = target
            }
        } else {
            animatedHeight = target
        }
    }
}
