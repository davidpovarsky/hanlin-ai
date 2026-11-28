// HanlinMiniAppContracts.swift
// HanlinPlatformContracts
//
// Canonical Mini App registration and discovery protocols.
// These provide a unified source of truth for Mini App identity, metadata,
// tools, capabilities, and exposure across all runtime families (native Swift,
// Scripting, NativeScript) without depending on app-only technologies.

import Foundation

// MARK: - Canonical Mini App Registration

/// Package-safe protocol for Mini App identity and metadata.
///
/// This is the canonical contract that all Mini App runtime families converge on.
/// It provides the data needed for discovery, catalog registration, and cross-family
/// interoperability without depending on SwiftUI, SwiftData, UIKit, or app-only services.
///
/// Native Swift Mini Apps implement this in `HanlinPlatformContracts`-compatible code.
/// Scripting and NativeScript apps produce conforming data through their manifest
/// decoders and import pipelines.
public protocol HanlinMiniAppRegistration: Sendable {
    /// The canonical root identity for this Mini App.
    var appID: HanlinAppID { get }

    /// Builds the canonical app descriptor for this Mini App.
    ///
    /// The descriptor is the single source of truth for identity, version,
    /// entry points, tools, capabilities, and presentation metadata.
    /// It can be validated, serialized, and shared across process boundaries.
    func appDescriptor() throws -> HanlinAppDescriptor

    /// The exposure surfaces supported by this Mini App.
    /// Defaults to the distinct exposures mapped from entry points in `appDescriptor()`.
    var supportedExposures: [HanlinExposureKind] { get }
}

extension HanlinMiniAppRegistration {
    public var supportedExposures: [HanlinExposureKind] {
        (try? appDescriptor())?.supportedExposures ?? []
    }
}

// MARK: - Canonical Mini App Discovery

/// Protocol for discovering registered Mini Apps across all runtime families.
///
/// A single discovery service can aggregate native Swift built-ins, installed
/// Scripting packages, and prepared NativeScript packages into one canonical
/// catalog. This replaces the need for separate registry/discovery mechanisms
/// per runtime family.
public protocol HanlinMiniAppDiscovery: Sendable {
    /// Returns all currently known Mini App registrations.
    func registrations() async throws -> [any HanlinMiniAppRegistration]

    /// Returns the registration for a specific app, if available.
    func registration(for appID: HanlinAppID) async throws -> (any HanlinMiniAppRegistration)?

    /// Returns a snapshot of the current Mini App catalog.
    func catalogSnapshot(
        revision: HanlinCatalogRevision
    ) async throws -> HanlinCatalogSnapshot
}

// MARK: - Static Native Mini App Registration

/// Convenience for native Swift Mini Apps that can produce their descriptor
/// at initialization time (no async work or I/O needed).
///
/// Most built-in native Mini Apps (Sefaria, Wikipedia, TextStudio) conform
/// to this since their identity and metadata are compile-time constants.
public protocol HanlinStaticMiniAppRegistration: HanlinMiniAppRegistration {
    /// The pre-built descriptor. Conformers typically store this as a `let`.
    var descriptor: HanlinAppDescriptor { get }
}

extension HanlinStaticMiniAppRegistration {
    public func appDescriptor() throws -> HanlinAppDescriptor { descriptor }
}

// MARK: - Package-Safe Execution Environment

/// Minimal execution environment contract for package-safe Mini App code.
///
/// This replaces the app-only `NativeAppContext` for code that needs to run
/// in package targets, extensions, or other non-app-main contexts. It provides
/// locale, identity, and session reference without importing SwiftUI, SwiftData,
/// or main-app services.
///
/// App-side code bridges this to the richer `NativeAppContext` through a thin
/// adapter when full app services are needed.
public struct HanlinMiniAppEnvironment: Sendable {
    /// The app identity this environment belongs to.
    public let appID: HanlinAppID

    /// Current user locale for localization decisions.
    public let locale: Locale

    /// Optional session identifier for tracking.
    public let sessionID: HanlinAppSessionID?

    /// The origin of this execution (user, assistant, automation, etc.).
    public let origin: HanlinExecutionOrigin

    public init(
        appID: HanlinAppID,
        locale: Locale = .current,
        sessionID: HanlinAppSessionID? = nil,
        origin: HanlinExecutionOrigin = .nativeModule
    ) {
        self.appID = appID
        self.locale = locale
        self.sessionID = sessionID
        self.origin = origin
    }

    /// Convenience: whether the current locale prefers right-to-left layout.
    public var isRTL: Bool {
        Locale.Language(identifier: locale.identifier).characterDirection == .rightToLeft
    }
}

// MARK: - Composite Discovery

/// Aggregates multiple Mini App discovery providers (e.g. built-in native discovery,
/// installed script package discovery, etc.) into one unified catalog snapshot.
public struct HanlinCompositeMiniAppDiscovery: HanlinMiniAppDiscovery, Sendable {
    private let providers: [any HanlinMiniAppDiscovery]

    public init(providers: [any HanlinMiniAppDiscovery]) {
        self.providers = providers
    }

    public func registrations() async throws -> [any HanlinMiniAppRegistration] {
        var seenIDs = Set<HanlinAppID>()
        var combined: [any HanlinMiniAppRegistration] = []
        for provider in providers {
            let regs = try await provider.registrations()
            for reg in regs {
                if seenIDs.insert(reg.appID).inserted {
                    combined.append(reg)
                }
            }
        }
        return combined
    }

    public func registration(for appID: HanlinAppID) async throws -> (any HanlinMiniAppRegistration)? {
        for provider in providers {
            if let found = try await provider.registration(for: appID) {
                return found
            }
        }
        return nil
    }

    public func catalogSnapshot(
        revision: HanlinCatalogRevision = .init(1)
    ) async throws -> HanlinCatalogSnapshot {
        let regs = try await registrations()
        let descriptors = try regs.map { try $0.appDescriptor() }
        return HanlinCatalogSnapshot(
            revision: revision,
            generatedAt: .now,
            apps: descriptors
        )
    }
}
