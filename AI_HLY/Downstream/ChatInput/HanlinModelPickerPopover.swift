//
//  HanlinModelPickerPopover.swift
//  AI_HLY
//
//  Compact anchored model picker popover with InteriorOrganizerV3_3 two-stage
//  size expansion and zoom navigation into searchable "All Models", styled in
//  Hanlin's original delicate blue glass aesthetic.
//

import SwiftUI

@MainActor
struct HanlinModelPickerPopover: View {
    @Bindable var coordinator: HanlinComposerPopupCoordinator
    let models: [AllModels]
    @Binding var selectedModelIndex: Int
    let onSelectModel: (Int) -> Void
    let temporaryRecord: Bool
    let ifToolUse: Bool
    let ifThink: Bool
    let ifAudio: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomNamespace
    @State private var searchText: String = ""

    private let compactSize = CGSize(width: 286, height: 324)
    private let expandedSize = CGSize(width: 344, height: 472)

    private var currentSize: CGSize {
        let target = coordinator.modelFrameExpanded ? expandedSize : compactSize
        return coordinator.responsiveSize(target: target)
    }

    private var accentColor: Color {
        temporaryRecord ? .primary : .hlBluefont
    }

    private var visibleIndices: [Int] {
        models.indices
            .filter { !models[$0].isHidden }
            .sorted { (models[$0].position ?? 0) < (models[$1].position ?? 0) }
    }

    /// Top 4 favorite/recent models plus the currently selected model if it isn't in the first 4.
    private var compactFeaturedIndices: [Int] {
        var result = Array(visibleIndices.prefix(4))
        if models.indices.contains(selectedModelIndex),
           !models[selectedModelIndex].isHidden,
           !result.contains(selectedModelIndex) {
            result.insert(selectedModelIndex, at: 0)
            result = Array(result.prefix(4))
        }
        return result
    }

    private var filteredAllIndices: [Int] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visibleIndices }
        let lower = trimmed.lowercased()
        return visibleIndices.filter { idx in
            let m = models[idx]
            let display = (m.displayName ?? m.name ?? "").lowercased()
            let rawName = (m.name ?? "").lowercased()
            let company = (m.company ?? "").lowercased()
            let pinyin = (m.displayName ?? "").toPinyin().lowercased()
            return display.contains(lower) || rawName.contains(lower) || company.contains(lower) || pinyin.contains(lower)
        }
    }

    var body: some View {
        NavigationStack(path: $coordinator.modelNavigationPath) {
            compactRootPage
                .navigationDestination(for: ComposerModelSubroute.self) { route in
                    switch route {
                    case .allModels:
                        allModelsDestinationPage
                            .navigationTransition(.zoom(sourceID: "hanlin-model-picker-all-models-row", in: zoomNamespace))
                            .onAppear {
                                coordinator.modelDestinationDisappeared = false
                            }
                            .onDisappear {
                                coordinator.markModelDestinationDisappeared(reduceMotion: reduceMotion)
                            }
                    }
                }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .background(
            GlassView(style: .systemUltraThinMaterial)
        )
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentColor.opacity(0.22), lineWidth: 0.8)
        )
        .onChange(of: coordinator.modelNavigationPath) { _, _ in
            coordinator.handleModelNavPathChange(reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-model-picker-popover")
    }

    // MARK: - Stage 1: Compact Root Page

    private var compactRootPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(String(localized: "Select Model"), systemImage: "cpu")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                Spacer()
                if models.indices.contains(selectedModelIndex),
                   let current = models[safe: selectedModelIndex] {
                    Text(current.company ?? "")
                        .font(.caption2.weight(.medium))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                Button {
                    coordinator.pushModelSubroute(.allModels, reduceMotion: reduceMotion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(accentColor)
                            .frame(width: 24, height: 24)
                            .background(accentColor.opacity(0.12), in: Circle())

                        Text(String(format: String(localized: "All Models (%lld)"), visibleIndices.count))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .matchedTransitionSource(id: "hanlin-model-picker-all-models-row", in: zoomNamespace)
                .accessibilityIdentifier("hanlin-model-picker-all-models-button")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Stage 2: Expanded All Models Page

    private var allModelsDestinationPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if !coordinator.modelNavigationPath.isEmpty {
                        coordinator.modelNavigationPath.removeLast()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "Back"))
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hanlin-model-picker-back-button")

                Spacer()

                Text(String(format: String(localized: "All Models (%lld)"), filteredAllIndices.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
                Color.clear.frame(width: 48, height: 24)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search models"), text: $searchText)
                    .font(.footnote)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("hanlin-model-picker-search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 4) {
                    ForEach(filteredAllIndices, id: \.self) { index in
                        if let model = models[safe: index] {
                            modelRowButton(model: model, index: index, compact: false)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-model-picker-all-models-page")
    }

    // MARK: - Model Row

    @ViewBuilder
    private func modelRowButton(model: AllModels, index: Int, compact: Bool) -> some View {
        let isSelected = (index == selectedModelIndex)
        Button {
            onSelectModel(index)
            coordinator.closeAll()
        } label: {
            HStack(spacing: 10) {
                modelIconView(for: model)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName ?? model.name ?? "Unknown")
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? accentColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    capabilityBadgesRow(for: model)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 7 : 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hanlin-model-picker-option-\(index)")
    }

    @ViewBuilder
    private func modelIconView(for model: AllModels) -> some View {
        if model.identity == "model" {
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
            if model.supportsImageGen {
                badgePill(String(localized: "Image"), color: .hlGreen)
            }
            if model.supportsVoiceGen {
                badgePill(String(localized: "Voice"), color: ifAudio ? .hlPink : .secondary)
            }
            if model.company?.uppercased() == "LOCAL" {
                badgePill(String(localized: "On-Device"), color: .hlOrange)
            }
            if model.price == 0 {
                badgePill(String(localized: "Free"), color: .green)
            }
        }
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.12), in: Capsule())
    }
}
