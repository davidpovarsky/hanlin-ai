// HanlinExposureContracts.swift
// HanlinPlatformContracts
//
// Canonical exposure catalog and system-surface classification contracts.
// Classifies Apple platform surfaces by framework family, UI vs non-UI,
// generic host feasibility, dedicated extension requirement, entitlements,
// compile-time vs runtime eligibility, and implementation state.

import Foundation

// MARK: - Exposure Kind

/// System surface or exposure channel through which a Mini App can be accessed.
public struct HanlinExposureKind: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible
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

// MARK: Known Exposure Kinds

extension HanlinExposureKind {
    // Near-term primary surfaces
    public static let foregroundApp: Self = "foreground_app"
    public static let assistantTool: Self = "assistant_tool"
    public static let embeddedResult: Self = "embedded_result"
    public static let widget: Self = "widget"
    public static let liveActivity: Self = "live_activity"
    public static let controlWidget: Self = "control_widget"
    public static let appIntent: Self = "app_intent"
    public static let spotlight: Self = "spotlight"
    public static let shareExtension: Self = "share_extension"
    public static let translationUI: Self = "translation_ui"

    // Extensible secondary / system surfaces
    public static let notificationUI: Self = "notification_ui"
    public static let keyboard: Self = "keyboard"
    public static let quickLook: Self = "quick_look"
    public static let fileProvider: Self = "file_provider"
    public static let photosPicker: Self = "photos_picker"
    public static let autoFill: Self = "autofill"
    public static let callKit: Self = "callkit"
    public static let networkExtension: Self = "network_extension"
    public static let replayKit: Self = "replaykit"
    public static let audioUnit: Self = "audio_unit"
    public static let messagesSticker: Self = "messages_sticker"
    public static let safariExtension: Self = "safari_extension"
    public static let backgroundTask: Self = "background_task"
    public static let watchComplication: Self = "watch_complication"
    public static let visualIntelligence: Self = "visual_intelligence"
    public static let capture: Self = "capture"
}

// MARK: - Exposure Eligibility

/// How a Mini App can qualify for this exposure surface.
public enum HanlinExposureEligibility: String, Codable, CaseIterable, Hashable, Sendable {
    /// Can be selected/configured entirely at runtime without compile-time host changes.
    case runtimeSelectable
    /// Requires compiled Swift types, entitlements, or targets in the host app.
    case compileTimeOnly
    /// Shared compiled generic host target, with Mini App content/identity selected at runtime.
    case hybrid
}

// MARK: - Exposure Implementation State

/// Current engineering status of this surface within the Hanlin platform.
public enum HanlinExposureState: String, Codable, CaseIterable, Hashable, Sendable {
    /// Fully implemented end-to-end.
    case implemented
    /// Implemented via a generic shared host that loads runtime Mini App definitions.
    case genericHosted
    /// Supported via a compatibility adapter layer over existing platform features.
    case adapterOnly
    /// Architecture classified and contract reserved for future implementation.
    case reserved
    /// Explicitly unsupported due to platform or architectural restrictions.
    case unsupported
}

// MARK: - Exposure Classification

/// Authoritative architectural classification of an exposure surface on Apple platforms.
public struct HanlinExposureClassification: Codable, Hashable, Sendable, Identifiable {
    public var id: HanlinExposureKind { kind }

    /// The exposure kind being classified.
    public let kind: HanlinExposureKind

    /// Primary Apple framework or API family backing this surface.
    public let appleFramework: String

    /// Whether this exposure presents interactive UI to the user.
    public let isUserInterface: Bool

    /// Whether a single generic shared host can serve multiple Mini Apps at runtime.
    public let supportsGenericHost: Bool

    /// Whether Apple platform rules require a separate compiled App Extension (.appex) target.
    public let requiresDedicatedExtensionTarget: Bool

    /// Apple entitlements required to host or participate in this surface.
    public let requiredEntitlements: [String]

    /// Keys required in Info.plist (e.g. extension network access, live activity support, background modes).
    public let requiredInfoPlistKeys: [String]

    /// Compile-time versus runtime eligibility.
    public let eligibility: HanlinExposureEligibility

    /// Current implementation state in the repository.
    public let implementationState: HanlinExposureState

    /// Additional architectural or platform notes.
    public let notes: String?

    public init(
        kind: HanlinExposureKind,
        appleFramework: String,
        isUserInterface: Bool,
        supportsGenericHost: Bool,
        requiresDedicatedExtensionTarget: Bool,
        requiredEntitlements: [String] = [],
        requiredInfoPlistKeys: [String] = [],
        eligibility: HanlinExposureEligibility,
        implementationState: HanlinExposureState,
        notes: String? = nil
    ) {
        self.kind = kind
        self.appleFramework = appleFramework
        self.isUserInterface = isUserInterface
        self.supportsGenericHost = supportsGenericHost
        self.requiresDedicatedExtensionTarget = requiresDedicatedExtensionTarget
        self.requiredEntitlements = requiredEntitlements
        self.requiredInfoPlistKeys = requiredInfoPlistKeys
        self.eligibility = eligibility
        self.implementationState = implementationState
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case kind, appleFramework, isUserInterface, supportsGenericHost
        case requiresDedicatedExtensionTarget, requiredEntitlements, requiredInfoPlistKeys
        case eligibility, implementationState, notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(HanlinExposureKind.self, forKey: .kind)
        appleFramework = try container.decode(String.self, forKey: .appleFramework)
        isUserInterface = try container.decode(Bool.self, forKey: .isUserInterface)
        supportsGenericHost = try container.decode(Bool.self, forKey: .supportsGenericHost)
        requiresDedicatedExtensionTarget = try container.decode(Bool.self, forKey: .requiresDedicatedExtensionTarget)
        requiredEntitlements = try container.decodeIfPresent([String].self, forKey: .requiredEntitlements) ?? []
        requiredInfoPlistKeys = try container.decodeIfPresent([String].self, forKey: .requiredInfoPlistKeys) ?? []
        eligibility = try container.decode(HanlinExposureEligibility.self, forKey: .eligibility)
        implementationState = try container.decode(HanlinExposureState.self, forKey: .implementationState)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

// MARK: - Canonical Exposure Catalog

/// Built-in authoritative registry of classifications for all recognized exposure kinds.
public enum HanlinExposureCatalog {
    /// All standard classifications defined by the platform.
    public static let standardClassifications: [HanlinExposureClassification] = [
        // 1. Foreground/internal app UI
        HanlinExposureClassification(
            kind: .foregroundApp,
            appleFramework: "SwiftUI / UIKit",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            eligibility: .runtimeSelectable,
            implementationState: .implemented,
            notes: "Main application window / container hosts native views, ScriptUI trees, or NativeScript view controllers."
        ),
        // 2. Assistant tool
        HanlinExposureClassification(
            kind: .assistantTool,
            appleFramework: "Foundation / JSONSchema",
            isUserInterface: false,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            eligibility: .runtimeSelectable,
            implementationState: .implemented,
            notes: "Dynamic tool dispatch via HanlinLogicalToolID with JSON schema validation."
        ),
        // 3. Embedded chat/result UI
        HanlinExposureClassification(
            kind: .embeddedResult,
            appleFramework: "SwiftUI (transcript embedded)",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            requiredInfoPlistKeys: [],
            eligibility: .runtimeSelectable,
            implementationState: .adapterOnly,
            notes: "Canonical seam defined; legacy chat card adapters exist. Dedicated generic chat transcript UI is under active development on the parallel presentation branch."
        ),
        // 4. WidgetKit
        HanlinExposureClassification(
            kind: .widget,
            appleFramework: "WidgetKit",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            requiredInfoPlistKeys: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "WidgetKit surface reserved; requires a dedicated Widget extension target to host Mini App widgets."
        ),
        // 5. Live Activities
        HanlinExposureClassification(
            kind: .liveActivity,
            appleFramework: "ActivityKit / WidgetKit",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            requiredInfoPlistKeys: ["NSSupportsLiveActivities"],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "ActivityKit surface reserved; requires a compiled extension target supporting ActivityAttributes and NSSupportsLiveActivities."
        ),
        // 6. Controls
        HanlinExposureClassification(
            kind: .controlWidget,
            appleFramework: "WidgetKit (Controls)",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            requiredInfoPlistKeys: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "ControlWidget templates hosted in widget extension invoking AppIntents; reserved until dedicated Control target/type is compiled."
        ),
        // 7. App Intents
        HanlinExposureClassification(
            kind: .appIntent,
            appleFramework: "AppIntents",
            isUserInterface: false,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            requiredInfoPlistKeys: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "AppIntents system integration reserved; in-session runtime registration primitives exist in HanlinScriptingApplicationRuntime, but system AppIntent host bridging is not wired today."
        ),
        // 8. Spotlight
        HanlinExposureClassification(
            kind: .spotlight,
            appleFramework: "CoreSpotlight",
            isUserInterface: false,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            requiredInfoPlistKeys: [],
            eligibility: .runtimeSelectable,
            implementationState: .reserved,
            notes: "CoreSpotlight search indexing reserved; no in-process or extension search indexing adapter is wired today."
        ),
        // 9. Share Extension
        HanlinExposureClassification(
            kind: .shareExtension,
            appleFramework: "ShareSheet",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            requiredInfoPlistKeys: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "Share extension surface reserved; requires a dedicated Share extension target to receive and forward shared items."
        ),
        // 10. Translation UI Provider
        HanlinExposureClassification(
            kind: .translationUI,
            appleFramework: "Translation",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [
                "com.apple.developer.translation-app"
            ],
            requiredInfoPlistKeys: [
                "com.apple.developer.translation-ui-provider.network-access"
            ],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "System translation extension surface. Network access requires Apple provider network key in Info.plist; reserved until dedicated extension target is compiled."
        ),
        // 11. Notification UI
        HanlinExposureClassification(
            kind: .notificationUI,
            appleFramework: "UserNotificationsUI",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "Custom rich notification interface."
        ),
        // 12. Keyboard
        HanlinExposureClassification(
            kind: .keyboard,
            appleFramework: "UIKit (Custom Keyboard)",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "Third-party custom keyboard extension."
        ),
        // 13. Quick Look
        HanlinExposureClassification(
            kind: .quickLook,
            appleFramework: "QuickLook",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "Custom file preview generation."
        ),
        // 14. File Provider
        HanlinExposureClassification(
            kind: .fileProvider,
            appleFramework: "FileProvider",
            isUserInterface: false,
            supportsGenericHost: false,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .compileTimeOnly,
            implementationState: .reserved,
            notes: "Virtual file system provider."
        ),
        // 15. Photos Picker
        HanlinExposureClassification(
            kind: .photosPicker,
            appleFramework: "PhotosUI",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            eligibility: .runtimeSelectable,
            implementationState: .reserved,
            notes: "Photo browsing and editing integration."
        ),
        // 16. AutoFill
        HanlinExposureClassification(
            kind: .autoFill,
            appleFramework: "AuthenticationServices",
            isUserInterface: true,
            supportsGenericHost: false,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: ["com.apple.developer.authentication-services.autofill-credential-provider"],
            eligibility: .compileTimeOnly,
            implementationState: .reserved,
            notes: "Credential and password provider."
        ),
        // 17. CallKit
        HanlinExposureClassification(
            kind: .callKit,
            appleFramework: "CallKit",
            isUserInterface: true,
            supportsGenericHost: false,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            eligibility: .compileTimeOnly,
            implementationState: .reserved,
            notes: "System telephony and VoIP call integration."
        ),
        // 18. Network Extension
        HanlinExposureClassification(
            kind: .networkExtension,
            appleFramework: "NetworkExtension",
            isUserInterface: false,
            supportsGenericHost: false,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: ["com.apple.developer.networking.networkextension"],
            eligibility: .compileTimeOnly,
            implementationState: .unsupported,
            notes: "VPN / packet filtering requires system-level network entitlements and dedicated daemons."
        ),
        // 19. ReplayKit
        HanlinExposureClassification(
            kind: .replayKit,
            appleFramework: "ReplayKit",
            isUserInterface: true,
            supportsGenericHost: false,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .compileTimeOnly,
            implementationState: .reserved,
            notes: "Screen recording and broadcasting."
        ),
        // 20. Audio Unit
        HanlinExposureClassification(
            kind: .audioUnit,
            appleFramework: "AudioToolbox / CoreAudio",
            isUserInterface: true,
            supportsGenericHost: false,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .compileTimeOnly,
            implementationState: .unsupported,
            notes: "Real-time DSP processing requires C/C++ audio thread semantics; unsupported for interpreted scripts."
        ),
        // 21. Messages Sticker
        HanlinExposureClassification(
            kind: .messagesSticker,
            appleFramework: "Messages",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "iMessage sticker pack and app extension."
        ),
        // 22. Safari Extension
        HanlinExposureClassification(
            kind: .safariExtension,
            appleFramework: "SafariServices",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "Safari Web Extension containing manifest and background scripts."
        ),
        // 23. Background Task
        HanlinExposureClassification(
            kind: .backgroundTask,
            appleFramework: "BackgroundTasks",
            isUserInterface: false,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            eligibility: .runtimeSelectable,
            implementationState: .reserved,
            notes: "Background task scheduling reserved; no BGTaskScheduler handler is wired in the main application today."
        ),
        // 24. Watch Complication
        HanlinExposureClassification(
            kind: .watchComplication,
            appleFramework: "WidgetKit (watchOS)",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: true,
            requiredEntitlements: [],
            eligibility: .hybrid,
            implementationState: .reserved,
            notes: "watchOS accessory widget complications."
        ),
        // 25. Visual Intelligence
        HanlinExposureClassification(
            kind: .visualIntelligence,
            appleFramework: "Vision / CoreML",
            isUserInterface: true,
            supportsGenericHost: true,
            requiresDedicatedExtensionTarget: false,
            requiredEntitlements: [],
            eligibility: .runtimeSelectable,
            implementationState: .reserved,
            notes: "System camera search and visual entity recognition integration."
        )
    ]

    private static let byKind: [HanlinExposureKind: HanlinExposureClassification] = {
        Dictionary(uniqueKeysWithValues: standardClassifications.map { ($0.kind, $0) })
    }()

    /// Looks up the authoritative classification for an exposure kind.
    public static func classification(for kind: HanlinExposureKind) -> HanlinExposureClassification? {
        byKind[kind]
    }
}
