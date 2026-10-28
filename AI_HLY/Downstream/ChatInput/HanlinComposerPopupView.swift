//
//  HanlinComposerPopupView.swift
//  AI_HLY
//
//  Native anchored popovers for:
//  1) General `+` Menu (`HanlinComposerGeneralActionsView`)
//  2) Direct 1-Tap Tools / Skills / MCP / Runtime Menu (`HanlinComposerToolsRootView`)
//  Both use the InteriorOrganizerV3_3 two-phase size expansion + zoom transition
//  and preserve Hanlin's original delicate blue glass visual identity.
//

import SwiftUI
import SwiftData
import HanlinPlatformContracts
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 1. General `+` Popover

@MainActor
struct HanlinComposerGeneralActionsView: View {
    @Bindable var coordinator: HanlinComposerPopupCoordinator
    let capability: HanlinComposerActionBridge.ModelCapabilitySnapshot
    let temporaryRecord: Bool
    let isResponding: Bool
    let canObserve: Bool

    // Attachments & prompts
    @Binding var selectedImages: [UIImage]
    @Binding var selectedDocumentURLs: [URL]
    @Binding var selectedPrompts: [PromptRepo]
    let availablePrompts: [PromptRepo]
    let onOpenCamera: () -> Void
    let onOpenPhotoLibrary: () -> Void
    let onOpenDocumentPicker: () -> Void

    // Mode toggles
    @Binding var ifSearch: Bool
    @Binding var ifKnowledge: Bool
    @Binding var ifThink: Bool
    @Binding var thinkingLength: Int
    @Binding var ifPlanning: Bool
    @Binding var ifAudio: Bool
    @Binding var selectedImageSize: String
    @Binding var imageReversePrompt: String

    // Availability checks & alerts
    let checkSearchAvailability: () -> Bool
    let checkEmbeddingAvailability: () -> Bool
    @Binding var showSearchAlert: Bool
    @Binding var showKnowledgeAlert: Bool
    let onOpenEmbeddingSettings: () -> Void

    // Parameters
    @Binding var temperature: Double
    @Binding var topP: Double
    @Binding var maxTokens: Int
    @Binding var maxMessagesNum: Int
    let onSaveParameters: () -> Void

    // Composer actions
    let onExpandEditor: () -> Void
    let onSendObserve: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomNamespace

    private let compactSize = CGSize(width: 318, height: 420)
    private let expandedSize = CGSize(width: 348, height: 488)

    private var currentSize: CGSize {
        let target = coordinator.generalFrameExpanded ? expandedSize : compactSize
        return coordinator.responsiveSize(target: target)
    }

    private var accentColor: Color {
        temporaryRecord ? .primary : .hlBluefont
    }

    var body: some View {
        NavigationStack(path: $coordinator.generalNavigationPath) {
            generalRootPage
                .navigationDestination(for: ComposerGeneralSubroute.self) { route in
                    Group {
                        switch route {
                        case .prompts:
                            promptsSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-general-prompts-row", in: zoomNamespace))
                        case .parameters:
                            parametersSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-general-parameters-row", in: zoomNamespace))
                        case .imageSize:
                            imageSizeSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-general-imagesize-row", in: zoomNamespace))
                        }
                    }
                    .onAppear {
                        coordinator.generalDestinationDisappeared = false
                    }
                    .onDisappear {
                        coordinator.markGeneralDestinationDisappeared(reduceMotion: reduceMotion)
                    }
                }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .background(GlassView(style: .systemUltraThinMaterial))
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentColor.opacity(0.22), lineWidth: 0.8)
        )
        .onChange(of: coordinator.generalNavigationPath) { _, _ in
            coordinator.handleGeneralNavPathChange(reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-composer-general-popover")
    }

    // MARK: - Root Page

    private var generalRootPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label(String(localized: "Add & Modes"), systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Spacer()
                    if capability.isLocal {
                        Label(String(localized: "Local Model"), systemImage: "bolt.horizontal.icloud.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.hlOrange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.hlOrange.opacity(0.14), in: Capsule())
                            .accessibilityIdentifier("hanlin-general-local-status-badge")
                    }
                }
                .padding(.horizontal, 4)

                // 1. Attachments Grid (Camera, Photos, Files)
                HStack(spacing: 8) {
                    if !capability.isLocal {
                        attachmentTile(
                            title: String(localized: "Camera"),
                            systemImage: "camera.fill",
                            identifier: "hanlin-general-camera",
                            disabled: isResponding || selectedImages.count >= 5
                        ) {
                            coordinator.closeAll()
                            onOpenCamera()
                        }

                        attachmentTile(
                            title: String(localized: "Photos"),
                            systemImage: "photo.fill.on.rectangle.fill",
                            identifier: "hanlin-general-photos",
                            disabled: isResponding || selectedImages.count >= 5
                        ) {
                            coordinator.closeAll()
                            onOpenPhotoLibrary()
                        }
                    }

                    attachmentTile(
                        title: String(localized: "Files"),
                        systemImage: "doc.fill",
                        identifier: "hanlin-general-files",
                        disabled: isResponding || selectedDocumentURLs.count >= 5
                    ) {
                        coordinator.closeAll()
                        onOpenDocumentPicker()
                    }
                }

                if !capability.supportsMultimodal && !capability.isLocal {
                    Text(String(localized: "Tip: The current model is not a native vision model; attached images will use visual assistance descriptions."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                #if targetEnvironment(simulator)
                if AgentRuntimeUIAcceptanceProvider.isEnabled {
                    HStack(spacing: 8) {
                        Button {
                            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
                            let sampleImage = renderer.image { ctx in
                                UIColor.systemBlue.setFill()
                                ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                            }
                            selectedImages.append(sampleImage)
                            coordinator.closeAll()
                        } label: {
                            Label("Sample Image", systemImage: "photo.badge.plus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hanlin-attach-sample-image")

                        Button {
                            let tmpURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("sample-attachment.txt")
                            try? "Sample attachment document content for UI acceptance.".write(
                                to: tmpURL,
                                atomically: true,
                                encoding: .utf8
                            )
                            selectedDocumentURLs.append(tmpURL)
                            coordinator.closeAll()
                        } label: {
                            Label("Sample Document", systemImage: "doc.badge.plus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hanlin-attach-sample-document")
                    }
                }
                #endif

                Divider()

                // 2. Conversation Modes
                VStack(spacing: 4) {
                    if capability.supportsSearch {
                        modeToggleRow(
                            title: String(localized: "Online Search"),
                            subtitle: String(localized: "Search the web and latest reference material in real time"),
                            systemImage: "globe",
                            tint: .hlAzure,
                            isOn: Binding(
                                get: { ifSearch },
                                set: { newValue in
                                    if !newValue {
                                        ifSearch = false
                                    } else if checkSearchAvailability() {
                                        ifSearch = true
                                    } else {
                                        showSearchAlert = true
                                    }
                                }
                            ),
                            identifier: "hanlin-general-toggle-search"
                        )

                        HStack(spacing: 6) {
                            modeToggleRow(
                                title: String(localized: "Knowledge Bag"),
                                subtitle: String(localized: "Search local vectorized knowledge base"),
                                systemImage: "backpack.fill",
                                tint: accentColor,
                                isOn: Binding(
                                    get: { ifKnowledge },
                                    set: { newValue in
                                        if !newValue {
                                            ifKnowledge = false
                                        } else if checkEmbeddingAvailability() {
                                            ifKnowledge = true
                                        } else {
                                            showKnowledgeAlert = true
                                        }
                                    }
                                ),
                                identifier: "hanlin-general-toggle-knowledge"
                            )

                            Button {
                                coordinator.closeAll()
                                onOpenEmbeddingSettings()
                            } label: {
                                Image(systemName: "slider.horizontal.2.square")
                                    .font(.footnote)
                                    .foregroundStyle(accentColor)
                                    .padding(7)
                                    .background(accentColor.opacity(0.1), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("hanlin-general-embedding-settings")
                        }
                    }

                    if capability.supportsReasoning {
                        VStack(alignment: .leading, spacing: 6) {
                            modeToggleRow(
                                title: String(localized: "Deep Thinking"),
                                subtitle: capability.supportReasoningChange ? String(localized: "Reason through complex problems and show reasoning summary") : String(localized: "The current model enables reasoning by default"),
                                systemImage: "sparkles",
                                tint: .hlPurple,
                                isOn: Binding(
                                    get: { ifThink },
                                    set: { newValue in
                                        if capability.supportReasoningChange {
                                            ifThink = newValue
                                        }
                                    }
                                ),
                                disabled: !capability.supportReasoningChange,
                                identifier: "hanlin-general-toggle-thinking"
                            )

                            if ifThink {
                                Picker(String(localized: "Thinking Depth"), selection: $thinkingLength) {
                                    Text(String(localized: "Default")).tag(0)
                                    Text(String(localized: "Brief")).tag(1)
                                    Text(String(localized: "Medium")).tag(2)
                                    Text(String(localized: "Deep")).tag(3)
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                                .accessibilityIdentifier("hanlin-general-thinking-length-picker")
                            }
                        }
                    } else if !capability.isLocal {
                        modeToggleRow(
                            title: String(localized: "Planning & Execution"),
                            subtitle: String(localized: "Plan tasks step by step before generating answers"),
                            systemImage: "list.bullet.clipboard.fill",
                            tint: .hlIndigo,
                            isOn: $ifPlanning,
                            identifier: "hanlin-general-toggle-planning"
                        )
                    }

                    if capability.supportsVoiceGen {
                        modeToggleRow(
                            title: String(localized: "Voice Generation"),
                            subtitle: String(localized: "Synthesize natural speech for assistant responses"),
                            systemImage: "waveform",
                            tint: .hlPink,
                            isOn: $ifAudio,
                            identifier: "hanlin-general-toggle-audio"
                        )
                    }

                    if capability.supportsImageGen {
                        Button {
                            coordinator.pushGeneralSubroute(.imageSize, reduceMotion: reduceMotion)
                        } label: {
                            navigationRowLabel(
                                title: String(localized: "Image Aspect Ratio & Negative Prompts"),
                                subtitle: String(format: String(localized: "Current aspect ratio: %@"), selectedImageSize),
                                systemImage: "paintbrush.pointed.fill",
                                tint: .hlGreen
                            )
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: "hanlin-general-imagesize-row", in: zoomNamespace)
                        .accessibilityIdentifier("hanlin-general-imagesize-button")
                    }
                }

                Divider()

                // 3. Prompts, Parameters, Long Editor, Observe, and Quick Switch to Tools
                VStack(spacing: 4) {
                    Button {
                        coordinator.pushGeneralSubroute(.prompts, reduceMotion: reduceMotion)
                    } label: {
                        navigationRowLabel(
                            title: String(localized: "Prompt Templates"),
                            subtitle: availablePrompts.isEmpty ? String(localized: "No unselected templates") : String(format: String(localized: "%lld templates available"), availablePrompts.count),
                            systemImage: "text.book.closed.fill",
                            tint: accentColor
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "hanlin-general-prompts-row", in: zoomNamespace)
                    .accessibilityIdentifier("hanlin-general-prompts-button")

                    Button {
                        coordinator.pushGeneralSubroute(.parameters, reduceMotion: reduceMotion)
                    } label: {
                        navigationRowLabel(
                            title: String(localized: "Model Parameters"),
                            subtitle: String(format: "Temp %.1f · Top-P %.1f · %d tokens", temperature, topP, maxTokens),
                            systemImage: "slider.horizontal.3",
                            tint: accentColor
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "hanlin-general-parameters-row", in: zoomNamespace)
                    .accessibilityIdentifier("hanlin-general-parameters-button")

                    Button {
                        coordinator.switchFromGeneralToTools()
                    } label: {
                        navigationRowLabel(
                            title: String(localized: "Tools, Skills & MCP"),
                            subtitle: String(localized: "Manage native tools, agent skills, MCP and runtimes"),
                            systemImage: "wrench.and.screwdriver.fill",
                            tint: .hlBrown
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-general-open-tools-button")

                    Button {
                        coordinator.closeAll()
                        onExpandEditor()
                    } label: {
                        navigationRowLabel(
                            title: String(localized: "Expand Long Text Editor"),
                            subtitle: String(localized: "Full screen editing for multi-paragraph prompts"),
                            systemImage: "arrow.up.left.and.arrow.down.right",
                            tint: accentColor,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-general-expand-editor")

                    if canObserve && !isResponding {
                        Button {
                            coordinator.closeAll()
                            onSendObserve()
                        } label: {
                            navigationRowLabel(
                                title: String(localized: "Observe & Continue"),
                                subtitle: String(localized: "Let the assistant continue the current topic without new input"),
                                systemImage: "eye.fill",
                                tint: accentColor,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hanlin-general-observe-action")
                    }
                }
            }
            .padding(12)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Subpages

    private var promptsSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(localized: "Select Prompt Template")) {
                if !coordinator.generalNavigationPath.isEmpty {
                    coordinator.generalNavigationPath.removeLast()
                }
            }

            if availablePrompts.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Prompts Available"),
                    systemImage: "text.book.closed",
                    description: Text(String(localized: "All prompts have been added, or you can create new ones in Prompt Library."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(availablePrompts, id: \.id) { item in
                            Button {
                                if !selectedPrompts.contains(where: { $0.id == item.id }) {
                                    selectedPrompts.append(item)
                                }
                                coordinator.closeAll()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "text.quote")
                                        .foregroundStyle(accentColor)
                                        .frame(width: 24, height: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? String(localized: "Untitled Prompt"))
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let content = item.content, !content.isEmpty {
                                            Text(content)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(accentColor)
                                }
                                .padding(10)
                                .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var parametersSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(localized: "Model Parameters")) {
                if !coordinator.generalNavigationPath.isEmpty {
                    coordinator.generalNavigationPath.removeLast()
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Creativity (Temperature)"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(accentColor)
                        }
                        Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                            .tint(accentColor)
                            .onChange(of: temperature) { _, _ in onSaveParameters() }
                            .accessibilityIdentifier("hanlin-param-temperature-slider")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Sampling Range (Top-P)"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.2f", topP))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(accentColor)
                        }
                        Slider(value: $topP, in: 0.1...1.0, step: 0.05)
                            .tint(accentColor)
                            .onChange(of: topP) { _, _ in onSaveParameters() }
                            .accessibilityIdentifier("hanlin-param-topp-slider")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Max Output Length (Max Tokens)"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(maxTokens)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(accentColor)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(maxTokens) },
                                set: { maxTokens = Int($0) }
                            ),
                            in: 512...16384,
                            step: 512
                        )
                        .tint(accentColor)
                        .onChange(of: maxTokens) { _, _ in onSaveParameters() }
                        .accessibilityIdentifier("hanlin-param-maxtokens-slider")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Context Memory Turns (Max History)"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(maxMessagesNum)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(accentColor)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(maxMessagesNum) },
                                set: { maxMessagesNum = Int($0) }
                            ),
                            in: 1...50,
                            step: 1
                        )
                        .tint(accentColor)
                        .onChange(of: maxMessagesNum) { _, _ in onSaveParameters() }
                        .accessibilityIdentifier("hanlin-param-maxmessages-slider")
                    }
                }
                .padding(14)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-general-parameters-page")
    }

    private var imageSizeSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(localized: "Image Generation Settings")) {
                if !coordinator.generalNavigationPath.isEmpty {
                    coordinator.generalNavigationPath.removeLast()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Select Aspect Ratio"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach([
                    ("square", String(localized: "Square (1:1)"), "square"),
                    ("landscape", String(localized: "Landscape (4:3 / 16:9)"), "rectangle"),
                    ("portrait", String(localized: "Portrait (3:4 / 9:16)"), "rectangle.portrait")
                ], id: \.0) { value, label, icon in
                    Button {
                        selectedImageSize = value
                    } label: {
                        HStack {
                            Image(systemName: icon)
                                .foregroundStyle(selectedImageSize == value ? accentColor : .secondary)
                            Text(label)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedImageSize == value {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accentColor)
                            }
                        }
                        .padding(10)
                        .background(
                            (selectedImageSize == value ? accentColor.opacity(0.12) : Color(.secondarySystemFill)),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                TextField(String(localized: "Negative Prompt (Optional)"), text: $imageReversePrompt)
                    .font(.footnote)
                    .padding(10)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
            Spacer()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Helper Subviews

    private func attachmentTile(
        title: String,
        systemImage: String,
        identifier: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(disabled ? .secondary : accentColor)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (disabled ? Color.secondary.opacity(0.08) : accentColor.opacity(0.1)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }

    private func modeToggleRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isOn: Binding<Bool>,
        disabled: Bool = false,
        identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isOn.wrappedValue ? tint : .secondary)
                    .frame(width: 26, height: 26)
                    .background((isOn.wrappedValue ? tint : Color.secondary).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tint(tint)
        .disabled(disabled || isResponding)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .accessibilityIdentifier(identifier)
    }

    private func navigationRowLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(.rect(cornerRadius: 10))
    }

    private func subpageHeader(title: String, onBack: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
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
            .accessibilityIdentifier("hanlin-general-subpage-back")

            Spacer()

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer()
            Color.clear.frame(width: 48, height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - 2. Direct 1-Tap Tools / Skills / MCP / Runtime Popover

@MainActor
struct HanlinComposerToolsRootView: View {
    @Bindable var coordinator: HanlinComposerPopupCoordinator
    let chatID: UUID
    let temporaryRecord: Bool
    let capability: HanlinComposerActionBridge.ModelCapabilitySnapshot
    @Binding var ifToolUse: Bool
    let onMCPSelectionChanged: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoomNamespace

    @State private var mcpProvider = MCPRuntimeProvider.shared
    @State private var selectedMCPServerIDs: Set<UUID> = []
    @State private var toolGroups: [NativeAssistantToolGroup] = []
    @State private var allSkills: [HanlinSkillDescriptor] = []
    @State private var disabledSkillIDs: Set<String> = []
    @State private var skillSearchText: String = ""
    @State private var runtimeSnapshots: [RuntimeSnapshot] = []

    private let compactSize = CGSize(width: 326, height: 396)
    private let expandedSize = CGSize(width: 360, height: 496)

    private var currentSize: CGSize {
        let target = coordinator.toolsFrameExpanded ? expandedSize : compactSize
        return coordinator.responsiveSize(target: target)
    }

    private var accentColor: Color {
        temporaryRecord ? .primary : .hlBluefont
    }

    var body: some View {
        NavigationStack(path: $coordinator.toolsNavigationPath) {
            toolsRootPage
                .navigationDestination(for: ComposerToolsSubroute.self) { route in
                    Group {
                        switch route {
                        case .toolsCatalog:
                            toolsCatalogSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-tools-subroute-catalog", in: zoomNamespace))
                        case .skillsCenter:
                            skillsSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-tools-subroute-skills", in: zoomNamespace))
                        case .mcpServers:
                            mcpServersSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-tools-subroute-mcp", in: zoomNamespace))
                        case .runtimeCenter:
                            runtimeSubpage
                                .navigationTransition(.zoom(sourceID: "hanlin-tools-subroute-runtime", in: zoomNamespace))
                        }
                    }
                    .onAppear {
                        coordinator.toolsDestinationDisappeared = false
                    }
                    .onDisappear {
                        coordinator.markToolsDestinationDisappeared(reduceMotion: reduceMotion)
                    }
                }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .background(GlassView(style: .systemUltraThinMaterial))
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accentColor.opacity(0.22), lineWidth: 0.8)
        )
        .onChange(of: coordinator.toolsNavigationPath) { _, _ in
            coordinator.handleToolsNavPathChange(reduceMotion: reduceMotion)
        }
        .task {
            await refreshLiveState()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-composer-tools-popover")
    }

    // MARK: - Root Page

    private var toolsRootPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(String(localized: "Tools, Skills & MCP"), systemImage: "wrench.and.screwdriver.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Spacer()
                    if capability.supportsToolUse {
                        Text(ifToolUse ? String(localized: "Enabled") : String(localized: "Paused"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ifToolUse ? .hlBrown : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((ifToolUse ? Color.hlBrown : Color.secondary).opacity(0.14), in: Capsule())
                    }
                }
                .padding(.horizontal, 4)

                // Master Tool Calling Toggle or Informative Unsupported Banner
                if capability.supportsToolUse {
                    Toggle(isOn: $ifToolUse) {
                        HStack(spacing: 10) {
                            Image(systemName: "hammer.fill")
                                .font(.subheadline)
                                .foregroundStyle(ifToolUse ? .hlBrown : .secondary)
                                .frame(width: 28, height: 28)
                                .background((ifToolUse ? Color.hlBrown : Color.secondary).opacity(0.14), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Allow tool usage in this chat"))
                                    .font(.subheadline.weight(.medium))
                                Text(String(localized: "When enabled, the model can call built-in tools, skills, and MCP servers as needed"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.hlBrown)
                    .padding(8)
                    .background(Color(.secondarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("hanlin-tool-use-toggle")
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                        Text(String(format: String(localized: "The current model \"%@\" does not support tool calling. You can still browse and manage skills, MCP, and runtimes."), capability.displayName))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("hanlin-tools-model-unsupported-banner")
                }

                Divider()

                // 4 Domain Navigation Cards with V3.3 Two-Stage Zoom
                VStack(spacing: 6) {
                    // 1. Native Tools Catalog
                    Button {
                        coordinator.pushToolsSubroute(.toolsCatalog, reduceMotion: reduceMotion)
                    } label: {
                        domainCard(
                            title: String(localized: "Built-in Tools & Permissions (Tools)"),
                            subtitle: String(format: String(localized: "%lld tools enabled · %lld tool groups"), enabledToolsCount, toolGroups.count),
                            systemImage: "hammer.circle.fill",
                            tint: .hlBrown
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "hanlin-tools-subroute-catalog", in: zoomNamespace)
                    .accessibilityIdentifier("hanlin-tools-open-catalog")

                    // 2. Agent Skills
                    Button {
                        coordinator.pushToolsSubroute(.skillsCenter, reduceMotion: reduceMotion)
                    } label: {
                        domainCard(
                            title: String(localized: "Agent Skills (Skills)"),
                            subtitle: String(format: String(localized: "%lld/%lld skills enabled · SKILL.md supported"), enabledSkillsCount, allSkills.count),
                            systemImage: "sparkles.rectangle.stack.fill",
                            tint: accentColor
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "hanlin-tools-subroute-skills", in: zoomNamespace)
                    .accessibilityIdentifier("hanlin-tools-open-skills")

                    // 3. MCP Servers
                    Button {
                        coordinator.pushToolsSubroute(.mcpServers, reduceMotion: reduceMotion)
                    } label: {
                        domainCard(
                            title: String(localized: "MCP Servers (MCP)"),
                            subtitle: mcpStatusSummaryText,
                            systemImage: "server.rack",
                            tint: .hlTeal
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "hanlin-tools-subroute-mcp", in: zoomNamespace)
                    .accessibilityIdentifier("hanlin-tools-open-mcp")

                    // 4. Runtimes
                    Button {
                        coordinator.pushToolsSubroute(.runtimeCenter, reduceMotion: reduceMotion)
                    } label: {
                        domainCard(
                            title: String(localized: "Local Runtimes (Runtimes)"),
                            subtitle: runtimeStatusSummaryText,
                            systemImage: "terminal.fill",
                            tint: .hlIndigo
                        )
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: "hanlin-tools-subroute-runtime", in: zoomNamespace)
                    .accessibilityIdentifier("hanlin-tools-open-runtime")
                }
            }
            .padding(12)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Subpage 1: Native Tools Catalog

    private var toolsCatalogSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(localized: "Built-in Tools & Permissions"))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(toolGroups) { group in
                        let groupOn = NativeToolCatalog.shared.isGroupEnabled(group)
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { groupOn },
                                set: { enabled in
                                    NativeToolCatalog.shared.setGroupEnabled(enabled, for: group)
                                    toolGroups = NativeToolCatalog.shared.settingsGroups()
                                }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: group.systemImage)
                                        .foregroundStyle(accentColor)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(group.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(String(format: String(localized: "%lld capabilities"), group.toolEntries.count))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tint(accentColor)

                            if groupOn {
                                ForEach(group.toolEntries) { entry in
                                    Toggle(isOn: Binding(
                                        get: { NativeToolCatalog.shared.isEnabled(entry) },
                                        set: { enabled in
                                            NativeToolCatalog.shared.setEnabled(enabled, for: entry)
                                            toolGroups = NativeToolCatalog.shared.settingsGroups()
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(entry.title)
                                                .font(.caption.weight(.medium))
                                            Text(entry.name)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .tint(accentColor)
                                    .padding(.leading, 26)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tools-catalog-page")
    }

    // MARK: - Subpage 2: Agent Skills

    private var skillsSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(format: String(localized: "Agent Skills (%lld/%lld)"), enabledSkillsCount, allSkills.count))

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search skill name or ID..."), text: $skillSearchText)
                    .font(.footnote)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("hanlin-tools-skills-search")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredSkills) { skill in
                        let isEnabled = !disabledSkillIDs.contains(skill.id.rawValue)
                        Toggle(isOn: Binding(
                            get: { isEnabled },
                            set: { newValue in
                                SkillStore.shared.setSkillEnabled(id: skill.id, enabled: newValue)
                                refreshSkillsState()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(skill.title.preferredValue())
                                        .font(.subheadline.weight(.medium))
                                    Text(skill.id.rawValue)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Text(skill.summary.preferredValue())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .tint(accentColor)
                        .padding(9)
                        .background(Color(.secondarySystemFill).opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("hanlin-skill-toggle-\(skill.id.rawValue)")
                    }

                    NavigationLink {
                        SkillCenterView()
                    } label: {
                        HStack {
                            Label(String(localized: "Open Skills Center (Import / New / Edit)"), systemImage: "arrow.up.forward.app")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-tools-open-full-skill-center")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tools-skills-page")
    }

    // MARK: - Subpage 3: MCP Servers

    private var mcpServersSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(localized: "MCP Servers"))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    // Master MCP switch
                    Toggle(isOn: Binding(
                        get: { mcpProvider.configuration.isEnabled },
                        set: { value in
                            Task {
                                await mcpProvider.setEnabled(value)
                                await refreshLiveState()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(String(localized: "Enable MCP Globally (global_mcp_enabled)"))
                                .font(.subheadline.weight(.medium))
                            Text(mcpProvider.configuration.isEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.hlTeal)
                    .padding(10)
                    .background(Color(.secondarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("hanlin-mcp-global-toggle")

                    if mcpProvider.servers.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "No MCP servers installed (server_installed: false)"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "You can ask the assistant to install servers via chat, or configure them in Settings below."))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(.secondarySystemFill).opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("hanlin-tools-mcp-empty")
                    } else {
                        ForEach(mcpProvider.servers) { server in
                            let isSelectedForChat = selectedMCPServerIDs.contains(server.id)
                            let status = mcpProvider.statuses[server.id]
                            let isRunning = (status?.state == .running)
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(
                                    get: { isSelectedForChat },
                                    set: { enabled in
                                        let previous = selectedMCPServerIDs
                                        var next = selectedMCPServerIDs
                                        if enabled { next.insert(server.id) } else { next.remove(server.id) }
                                        Task {
                                            await mcpProvider.setSelection(next, chatID: chatID, temporary: temporaryRecord)
                                            let confirmed = await mcpProvider.selection(chatID: chatID, temporary: temporaryRecord)
                                            await MainActor.run {
                                                if confirmed.contains(server.id) == enabled {
                                                    selectedMCPServerIDs = confirmed
                                                    onMCPSelectionChanged(confirmed.count)
                                                } else {
                                                    selectedMCPServerIDs = previous
                                                    onMCPSelectionChanged(previous.count)
                                                }
                                            }
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.displayName)
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(server.packageName) @ \(server.resolvedVersion)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tint(.hlTeal)

                                HStack(spacing: 6) {
                                    statusPill(String(localized: "Installed"), active: true)
                                    statusPill(String(localized: "Enabled"), active: server.isGloballyEnabled)
                                    statusPill(String(localized: "Chat"), active: isSelectedForChat)
                                    statusPill(String(localized: "Running"), active: isRunning)
                                    Spacer()
                                    Button(isRunning ? String(localized: "Restart") : String(localized: "Start")) {
                                        Task {
                                            if isRunning {
                                                await mcpProvider.restart(server)
                                            } else {
                                                await mcpProvider.start(server)
                                            }
                                            await refreshLiveState()
                                        }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(accentColor)
                                }
                            }
                            .padding(10)
                            .background(Color(.secondarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("hanlin-mcp-server-row-\(server.slug)")
                        }
                    }

                    NavigationLink {
                        MCPServersSettingsView()
                    } label: {
                        HStack {
                            Label(String(localized: "Open MCP Server Settings & Installation"), systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-tools-open-full-mcp-settings")
                }
                .padding(12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tools-mcp-page")
    }

    // MARK: - Subpage 4: Runtimes

    private var runtimeSubpage: some View {
        VStack(alignment: .leading, spacing: 0) {
            subpageHeader(title: String(localized: "Local Runtimes"))

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(runtimeSnapshots, id: \.kind) { snap in
                        let isReady = (snap.state == .ready || snap.state == .executing)
                        HStack(spacing: 10) {
                            Circle()
                                .fill(isReady ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snap.kind.rawValue)
                                    .font(.subheadline.weight(.medium))
                                Text(snap.version ?? "On-demand")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(isReady ? String(localized: "Stop") : String(localized: "Start")) {
                                Task {
                                    if isReady {
                                        _ = try? await AppRuntimeCore.shared.stop(snap.kind)
                                    } else {
                                        _ = try? await AppRuntimeCore.shared.start(snap.kind)
                                    }
                                    runtimeSnapshots = await AppRuntimeCore.shared.snapshots()
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.12), in: Capsule())
                        }
                        .padding(10)
                        .background(Color(.secondarySystemFill).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    NavigationLink {
                        RuntimeCenterView()
                    } label: {
                        HStack {
                            Label(String(localized: "Open Runtime & Package Manager"), systemImage: "terminal")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-tools-open-full-runtime-center")
                }
                .padding(12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tools-runtime-page")
    }

    // MARK: - Live State Helpers

    private var enabledToolsCount: Int {
        NativeToolCatalog.shared.allEntries().filter {
            NativeToolCatalog.shared.isEffectivelyEnabled($0)
        }.count
    }

    private var enabledSkillsCount: Int {
        allSkills.filter { !disabledSkillIDs.contains($0.id.rawValue) }.count
    }

    private var filteredSkills: [HanlinSkillDescriptor] {
        let q = skillSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allSkills }
        return allSkills.filter {
            $0.id.rawValue.lowercased().contains(q)
                || $0.title.preferredValue().lowercased().contains(q)
                || $0.summary.preferredValue().lowercased().contains(q)
        }
    }

    private var mcpStatusSummaryText: String {
        guard mcpProvider.configuration.isEnabled else {
            return String(localized: "Globally Disabled · Tap to Configure")
        }
        let installedCount = mcpProvider.servers.count
        let runningCount = mcpProvider.servers.filter { mcpProvider.statuses[$0.id]?.state == .running }.count
        return String(format: String(localized: "Installed %lld · Selected in chat %lld · Running %lld"), installedCount, selectedMCPServerIDs.count, runningCount)
    }

    private var runtimeStatusSummaryText: String {
        let readyCount = runtimeSnapshots.filter { $0.state == .ready || $0.state == .executing }.count
        return String(format: String(localized: "Node / TS / Python / JSC / Shell · Ready %lld/%lld"), readyCount, max(runtimeSnapshots.count, 5))
    }

    private func refreshLiveState() async {
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        toolGroups = NativeToolCatalog.shared.settingsGroups()
        refreshSkillsState()
        await mcpProvider.loadIfNeeded(startHost: false)
        selectedMCPServerIDs = await mcpProvider.selection(chatID: chatID, temporary: temporaryRecord)
        onMCPSelectionChanged(selectedMCPServerIDs.count)
        runtimeSnapshots = await AppRuntimeCore.shared.snapshots()
    }

    private func refreshSkillsState() {
        let disabledSet = Set(SkillStore.shared.disabledSkillIDs().map(\.rawValue))
        disabledSkillIDs = disabledSet
        let activeCatalog = HanlinSkillCatalog.shared.allSkills()
        let customStored = SkillStore.shared.allCustomSkillDescriptors()
        var mergedByID: [String: HanlinSkillDescriptor] = [:]
        for s in activeCatalog { mergedByID[s.id.rawValue] = s }
        for s in customStored where mergedByID[s.id.rawValue] == nil {
            mergedByID[s.id.rawValue] = s
        }
        allSkills = mergedByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func domainCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemFill).opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(.rect(cornerRadius: 14))
    }

    private func statusPill(_ label: String, active: Bool) -> some View {
        Text("\(label): \(active ? "✓" : "–")")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(active ? Color.hlTeal : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background((active ? Color.hlTeal : Color.secondary).opacity(0.12), in: Capsule())
    }

    private func subpageHeader(title: String) -> some View {
        HStack(spacing: 8) {
            Button {
                if !coordinator.toolsNavigationPath.isEmpty {
                    coordinator.toolsNavigationPath.removeLast()
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
            .accessibilityIdentifier("hanlin-tools-subpage-back")

            Spacer()

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer()
            Color.clear.frame(width: 48, height: 24)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}
