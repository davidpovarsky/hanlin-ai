//
//  HanlinModelPickerPopover.swift
//  AI_HLY
//
//  Compact anchored model picker with one native size transition into a
//  searchable provider-grouped catalog. UIKit owns the presentation geometry.
//

import SwiftUI
import SwiftData
#if canImport(HanlinAgentCore)
import HanlinAgentCore
#endif

@MainActor
struct HanlinModelPickerPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var coordinator: HanlinComposerPopupCoordinator
    let models: [AllModels]
    @Binding var selectedModelIndex: Int
    let onSelectModel: (Int) -> Void
    let temporaryRecord: Bool
    let ifToolUse: Bool
    let ifThink: Bool
    let ifAudio: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText: String = ""
    @State private var appleOnDeviceAvailable = false
    @Environment(\.scenePhase) private var scenePhase

    private var accentColor: Color {
        temporaryRecord ? .primary : .hlBluefont
    }

    // SDK owns registration and identity; this view only projects visibility.
    private static var nativeCatalogID: UUID? {
        #if canImport(HanlinAgentCore)
        HanlinAppleModelCatalogAdapter.catalogID
        #else
        nil
        #endif
    }

    private static func nativeModelIsAvailable() -> Bool {
        #if canImport(HanlinAgentCore)
        HanlinAppleOnDeviceProvider.availability == .available
        #else
        false
        #endif
    }

    /// Return original array indices so saved useModel selections never shift.
    static func visibleModelIndices(_ models: [AllModels], nativeID: UUID?, nativeAvailable: Bool) -> [Int] {
        var includedNative = false
        return models.indices.filter { index in
            let model = models[index]
            guard !model.isHidden else { return false }
            guard let nativeID, model.id == nativeID else { return true }
            guard nativeAvailable, !includedNative else { return false }
            includedNative = true
            return true
        }.sorted { (models[$0].position ?? 0) < (models[$1].position ?? 0) }
    }

    private var visibleIndices: [Int] {
        Self.visibleModelIndices(models, nativeID: Self.nativeCatalogID, nativeAvailable: appleOnDeviceAvailable)
    }

    /// Preserve featured/current rows and expose the one available local row.
    static func compactFeaturedIndices(_ models: [AllModels], selectedModelIndex: Int,
                                       nativeID: UUID?, nativeAvailable: Bool) -> [Int] {
        let visible = visibleModelIndices(models, nativeID: nativeID, nativeAvailable: nativeAvailable)
        var result = Array(visible.prefix(4))
        if visible.contains(selectedModelIndex), !result.contains(selectedModelIndex) {
            result.insert(selectedModelIndex, at: 0)
            result = Array(result.prefix(4))
        }
        if let native = visible.first(where: { models[$0].id == nativeID }), !result.contains(native) {
            result.append(native)
        }
        return result
    }

    private var compactFeaturedIndices: [Int] {
        Self.compactFeaturedIndices(models, selectedModelIndex: selectedModelIndex,
                                    nativeID: Self.nativeCatalogID, nativeAvailable: appleOnDeviceAvailable)
    }

    private var filteredAllIndices: [Int] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visibleIndices }
        let lower = trimmed.lowercased()
        return visibleIndices.filter { idx in
            let m = models[idx]
            let display = m.presentationName.lowercased()
            let rawName = (m.name ?? "").lowercased()
            let company = (m.company ?? "").lowercased()
            let pinyin = (m.displayName ?? "").toPinyin().lowercased()
            return display.contains(lower) || rawName.contains(lower) || company.contains(lower) || pinyin.contains(lower)
        }
    }

    private struct ProviderGroup: Identifiable {
        let provider: String
        let indices: [Int]
        var id: String { provider }
    }

    private var providerGroups: [ProviderGroup] {
        var order: [String] = []
        var grouped: [String: [Int]] = [:]
        for idx in filteredAllIndices {
            let provider = (models[safe: idx]?.company ?? "OTHER").uppercased()
            if grouped[provider] == nil {
                order.append(provider)
                grouped[provider] = []
            }
            grouped[provider]?.append(idx)
        }
        return order.map { ProviderGroup(provider: $0, indices: grouped[$0] ?? []) }
    }

    var body: some View {
        // The route and the native size change together. A second matched
        // surface/scale transition produced the visible double entrance.
        Group {
            if coordinator.modelNavigationPath.isEmpty {
                compactRootPage
            } else {
                allModelsDestinationPage
            }
        }
        // Fill the native hosting controller's actual bounds. Do not animate a
        // second fixed SwiftUI frame independently of the popover's native mask.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onChange(of: coordinator.modelNavigationPath) { _, newPath in
            if !newPath.isEmpty {
                coordinator.modelDestinationDisappeared = false
                if !coordinator.modelFrameExpanded {
                    coordinator.modelFrameExpanded = true
                }
            } else {
                coordinator.handleModelNavPathChange(reduceMotion: reduceMotion)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-model-picker-popover")
        .onAppear { appleOnDeviceAvailable = Self.nativeModelIsAvailable() }
        .onChange(of: coordinator.isModelPresented) { _, isPresented in
            if isPresented { appleOnDeviceAvailable = Self.nativeModelIsAvailable() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appleOnDeviceAvailable = Self.nativeModelIsAvailable() }
        }
        .task { await ModelRefreshService.refreshOpenRouterMetadata(in: modelContext) }
    }

    // MARK: - Stage 1: Compact Root Page

    private var compactRootPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(String(localized: "Select Model"), systemImage: "cpu")
                    .font(HanlinTypography.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                if models.indices.contains(selectedModelIndex),
                   let current = models[safe: selectedModelIndex] {
                    Text(current.company ?? "")
                        .font(HanlinTypography.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.1), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if visibleIndices.isEmpty {
                ContentUnavailableView(
                    String(localized: "No models available"),
                    systemImage: "sparkles",
                    description: Text(String(localized: "Please configure models in Settings"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(compactFeaturedIndices, id: \.self) { index in
                            if let model = models[safe: index] {
                                modelRowButton(model: model, index: index, compact: true)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                Divider()
                    .padding(.horizontal, HanlinControlMetrics.pageInset)
                    .padding(.vertical, 4)

                // One action changes the page and preferred size together.
                Button {
                    searchText = ""
                    coordinator.pushModelSubroute(.allModels, reduceMotion: reduceMotion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(HanlinTypography.subheadline.weight(.medium))
                            .foregroundStyle(accentColor)
                            .frame(width: HanlinControlMetrics.iconSize, height: HanlinControlMetrics.iconSize)
                            .background(accentColor.opacity(0.12), in: Circle())

                        Text(String(format: String(localized: "All Models (%lld)"), visibleIndices.count))
                            .font(HanlinTypography.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.forward")
                            .font(HanlinTypography.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, HanlinControlMetrics.pageInset)
                    .padding(.vertical, 9)
                    .contentShape(.rect(cornerRadius: HanlinControlMetrics.rowCornerRadius))
                }
                .buttonStyle(.plain)
                .background(accentColor.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: HanlinControlMetrics.rowCornerRadius))
                .disabled(coordinator.isModelAnimatingExpand)
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .accessibilityIdentifier("hanlin-model-picker-all-models-button")
            }
        }
    }

    // MARK: - Stage 2: Expanded All Models Page (Provider Sections)

    private var allModelsDestinationPage: some View {
        let groups = providerGroups
        let resultCount = groups.reduce(0) { $0 + $1.indices.count }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HanlinControlMetrics.rowSpacing) {
                Button {
                    coordinator.popModelSubroute(reduceMotion: reduceMotion)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(HanlinTypography.subheadline.weight(.semibold))
                        Text(String(localized: "Back"))
                            .font(HanlinTypography.subheadline.weight(.medium))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hanlin-model-picker-back-button")

                Spacer()

                Text(String(format: String(localized: "All Models (%lld)"), resultCount))
                    .font(HanlinTypography.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
                Color.clear.frame(width: 48, height: 24)
            }
            .padding(.horizontal, HanlinControlMetrics.pageInset)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HanlinSearchField(
                text: $searchText,
                prompt: String(localized: "Search models"),
                accessibilityIdentifier: "hanlin-model-picker-search",
                tint: accentColor
            )
            .padding(.horizontal, HanlinControlMetrics.pageInset)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.provider)
                                .font(HanlinTypography.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 2)

                            ForEach(group.indices, id: \.self) { index in
                                if let model = models[safe: index] {
                                    modelRowButton(model: model, index: index, compact: false)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-model-picker-all-models-page")
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRowButton(model: AllModels, index: Int, compact: Bool) -> some View {
        let isSelected = (index == selectedModelIndex)
        Button {
            if model.id == Self.nativeCatalogID {
                let available = Self.nativeModelIsAvailable()
                appleOnDeviceAvailable = available
                guard available else { return }
            }
            onSelectModel(index)
            coordinator.close(.model)
        } label: {
            HStack(spacing: 10) {
                modelIconView(for: model)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.presentationName)
                        .font(HanlinTypography.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? accentColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    capabilityBadgesRow(for: model)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(HanlinTypography.subheadline)
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 7 : 8)
            .background(
                RoundedRectangle(cornerRadius: HanlinControlMetrics.rowCornerRadius, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(.rect(cornerRadius: HanlinControlMetrics.rowCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hanlin-model-picker-option-\(index)")
    }

    @ViewBuilder
    private func modelIconView(for model: AllModels) -> some View {
        if model.id == Self.nativeCatalogID {
            Image(systemName: "apple.intelligence")
                .font(HanlinTypography.title3)
                .foregroundStyle(accentColor)
        } else if model.identity == "model" {
            Image(getCompanyIcon(for: model.company ?? "Unknown"))
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: model.icon ?? "circle.dotted.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(accentColor)
        }
    }

    @ViewBuilder
    private func capabilityBadgesRow(for model: AllModels) -> some View {
        HStack(spacing: 4) {
            if model.supportsToolUse {
                badgePill(String(localized: "Tools"), color: ifToolUse ? .hlBrown : .secondary)
            }
            if model.supportsMultimodal {
                badgePill(String(localized: "Vision"), color: .hlTeal)
            }
            if model.supportsReasoning {
                badgePill(String(localized: "Thinking"), color: ifThink ? .hlPurple : .secondary)
            }
            if model.hasVerifiedImageOutput {
                badgePill(String(localized: "Image"), color: .hlGreen)
            }
            if model.supportsVoiceGen {
                badgePill(String(localized: "Voice"), color: ifAudio ? .hlPink : .secondary)
            }
            if model.company?.uppercased() == "LOCAL" {
                badgePill(String(localized: "On-Device"), color: .hlOrange)
            }
            if model.catalogPriceTier == 0 {
                badgePill(String(localized: "Free"), color: .green)
            } else if model.catalogPriceTier < 0 {
                badgePill(String(localized: "Price unknown"), color: .secondary)
            }
        }
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(HanlinTypography.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, HanlinControlMetrics.badgeHorizontalInset)
            .padding(.vertical, HanlinControlMetrics.badgeVerticalInset)
            .background(color.opacity(0.12), in: Capsule())
    }
}
