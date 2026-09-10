// HanlinPresentationContracts.swift
// HanlinPlatformContracts
//
// Canonical presentation seam between content providers and host surfaces.
// This contract describes presentation intent/hints from Mini Apps and tools.
// It does NOT contain renderer implementation, SwiftUI views, chat styling,
// or hard host-imposed dimension limits.

import Foundation

// MARK: - Embedded Result Presentation

/// Describes how a Mini App or tool result should be presented in an embedded
/// surface such as a chat transcript, inline result area, or notification.
///
/// This is a request/hint from the content provider. The host surface has final
/// authority over actual dimensions, layout constraints, and expansion behavior.
public struct HanlinEmbeddedPresentationDescriptor: Codable, Hashable, Sendable {
    /// Identifier of the runtime handler/provider that renders the embedded content.
    /// The host resolves this to the appropriate renderer for the content's runtime family.
    public let handler: String?

    /// Sizing preference requested by the content provider.
    public let sizing: HanlinEmbeddedSizingPreference

    /// Optional expansion behavior. When nil, the host may not offer expansion.
    public let expansion: HanlinExpansionDescriptor?

    public init(
        handler: String? = nil,
        sizing: HanlinEmbeddedSizingPreference = .init(),
        expansion: HanlinExpansionDescriptor? = nil
    ) {
        self.handler = handler
        self.sizing = sizing
        self.expansion = expansion
    }
}

/// Sizing preference for embedded presentation. This is a request, never
/// authority over the host. The host enforces its own maximum dimensions.
public struct HanlinEmbeddedSizingPreference: Codable, Hashable, Sendable {
    /// A semantic size preset. The host interprets these contextually.
    public let preset: HanlinEmbeddedSizePreset

    /// Optional preferred width in points. The host may ignore or clamp this.
    public let preferredWidth: Double?

    /// Optional preferred height in points. The host may ignore or clamp this.
    public let preferredHeight: Double?

    public init(
        preset: HanlinEmbeddedSizePreset = .automatic,
        preferredWidth: Double? = nil,
        preferredHeight: Double? = nil
    ) {
        self.preset = preset
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
    }
}

/// Semantic size presets for embedded content. The host maps these to actual
/// dimensions based on the embedding surface and device context.
public enum HanlinEmbeddedSizePreset: String, Codable, CaseIterable, Hashable, Sendable {
    /// Host determines the most appropriate size.
    case automatic
    /// Minimal footprint — single line or very small area.
    case compact
    /// Standard result size — a few lines of content.
    case regular
    /// Larger embedded area — charts, tables, multi-section results.
    case large
}

// MARK: - Expansion

/// Describes how embedded content may expand to a richer presentation.
public struct HanlinExpansionDescriptor: Codable, Hashable, Sendable {
    /// The expansion modes the content provider supports, in preference order.
    /// The host selects the first mode it can honor.
    public let supportedModes: [HanlinExpansionMode]

    /// Optional separate handler/provider for the expanded presentation.
    /// When nil, the host reuses the embedded handler if appropriate.
    public let expandedHandler: String?

    public init(
        supportedModes: [HanlinExpansionMode] = [.sheet],
        expandedHandler: String? = nil
    ) {
        self.supportedModes = supportedModes
        self.expandedHandler = expandedHandler
    }
}

/// How embedded content can expand. These generalize the existing
/// `HanlinPresentationIntent` cases for use by embedded surfaces.
/// The host enforces platform policy (e.g. iPhone may not support `.window`).
public enum HanlinExpansionMode: String, Codable, CaseIterable, Hashable, Sendable {
    /// Expand into a sheet presentation (maps to largeSheet intent).
    case sheet
    /// Expand to full screen.
    case fullScreen
    /// Open in a separate window (iPadOS/macOS/visionOS).
    case window
}

// MARK: - Tool Execution Presentation

/// Describes how a tool's in-progress execution should appear in the
/// chat transcript or embedding surface. This is distinct from the
/// tool's final result presentation.
///
/// Execution UI is compact activity/progress content inside the transcript.
/// It must NOT imply sheet/full-screen/window expansion.
public struct HanlinToolExecutionPresentationDescriptor: Codable, Hashable, Sendable {
    /// A Hanlin system execution presentation family, or a custom family.
    /// When nil, the host uses a generic system default.
    public let familyID: HanlinExecutionPresentationFamilyID?

    /// Optional custom execution UI handler/provider.
    /// Used when `familyID` is `.custom` or the content provider wants to
    /// render its own compact execution visualization.
    public let customHandler: String?

    public init(
        familyID: HanlinExecutionPresentationFamilyID? = nil,
        customHandler: String? = nil
    ) {
        self.familyID = familyID
        self.customHandler = customHandler
    }
}

/// Extensible identifier for tool execution presentation families.
/// Uses `RawRepresentable<String>` so new families can be added without
/// schema-breaking changes. Known system constants are provided.
public struct HanlinExecutionPresentationFamilyID: RawRepresentable, Codable, Hashable,
    Sendable, ExpressibleByStringLiteral, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String { rawValue }
}

// MARK: Known Execution Presentation Families

extension HanlinExecutionPresentationFamilyID {
    /// Generic system default — spinner/label.
    public static let generic: Self = "generic"
    /// Web search activity.
    public static let webSearch: Self = "web-search"
    /// Source/reference search.
    public static let sourceSearch: Self = "source-search"
    /// Map/location activity.
    public static let map: Self = "map"
    /// Shell/system command execution.
    public static let command: Self = "command"
    /// File operation (read/write/move/delete).
    public static let fileOperation: Self = "file-operation"
    /// Code execution/evaluation.
    public static let codeExecution: Self = "code-execution"
    /// Image generation/processing.
    public static let imageGeneration: Self = "image-generation"
    /// Custom Mini App-provided execution UI.
    public static let custom: Self = "custom"
}

// MARK: - Convenience: Expansion Mode ↔ Presentation Intent Bridge

extension HanlinExpansionMode {
    /// Maps an expansion mode to the corresponding full-app presentation intent.
    public var presentationIntent: HanlinPresentationIntent {
        switch self {
        case .sheet: .largeSheet
        case .fullScreen: .fullScreen
        case .window: .newWindow
        }
    }

    /// Creates an expansion mode from a full-app presentation intent.
    public init?(presentationIntent: HanlinPresentationIntent) {
        switch presentationIntent {
        case .fullScreen: self = .fullScreen
        case .largeSheet: self = .sheet
        case .newWindow: self = .window
        }
    }
}
