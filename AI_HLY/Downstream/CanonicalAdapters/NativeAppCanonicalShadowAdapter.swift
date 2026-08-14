import Foundation
import HanlinPlatformContracts

struct HanlinShadowFinding: Hashable, Sendable {
    enum Severity: String, Hashable, Sendable {
        case information
        case warning
    }

    let severity: Severity
    let path: String
    let message: String
}

struct NativeAppCanonicalShadowProjection: Sendable {
    let descriptor: HanlinAppDescriptor
    let findings: [HanlinShadowFinding]
}

/// Projects the live NativeAppPlatform registry into portable descriptors.
///
/// Legacy sources: `NativeAppRegistry`, `NativeAppManifest`, and
/// `NativeCapabilityRequest`. Canonical targets: `HanlinCatalogSnapshot` and
/// `HanlinAppSessionDescriptor`. UI modules, closures, keywords, gradient end
/// colors, chat-card providers, and task handles never cross the boundary;
/// omissions are returned as findings. Invalid identities fail. Delete this
/// adapter when native modules publish canonical descriptors and sessions.
@MainActor
enum NativeAppCanonicalShadowAdapter {
    static func projectRegistry(
        hostVersion: HanlinPackageVersion,
        revision: HanlinCatalogRevision = .init(0),
        descriptorRevision: HanlinDescriptorRevision
    ) throws -> (HanlinCatalogSnapshot, [HanlinShadowFinding]) {
        let modules = NativeAppRegistry.shared.allModules()
        var findings: [HanlinShadowFinding] = []
        let descriptors = try modules.map { module in
            let projection = try project(
                manifest: module.manifest,
                capabilities: module.capabilities(context: NativeAppContext()),
                hostVersion: hostVersion,
                descriptorRevision: descriptorRevision
            )
            findings.append(contentsOf: projection.findings)
            return projection.descriptor
        }
        return (
            HanlinCatalogSnapshot(
                revision: revision,
                generatedAt: .now,
                apps: descriptors
            ),
            findings
        )
    }

    static func project(
        manifest: NativeAppManifest,
        capabilities: [NativeCapabilityRequest],
        hostVersion: HanlinPackageVersion,
        descriptorRevision: HanlinDescriptorRevision
    ) throws -> NativeAppCanonicalShadowProjection {
        let appID = try HanlinAppID(validating: manifest.id)
        let moduleID = try HanlinModuleID(validating: manifest.id)
        var findings: [HanlinShadowFinding] = []
        let entryPoints = manifest.entryPoints
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { entryPoint in
            switch entryPoint {
            case .fullApp:
                return HanlinEntryPointDescriptor(
                    kind: .app,
                    handler: manifest.id,
                    allowedContexts: [.mainApplication]
                )
            case .assistantTool:
                return HanlinEntryPointDescriptor(
                    kind: .assistantTool,
                    handler: manifest.id,
                    allowedContexts: [.mainApplication]
                )
            case .widget:
                return HanlinEntryPointDescriptor(
                    kind: .widget,
                    handler: manifest.id,
                    allowedContexts: [.widget]
                )
            case .liveActivity:
                return HanlinEntryPointDescriptor(
                    kind: .liveActivity,
                    handler: manifest.id,
                    allowedContexts: [.liveActivity]
                )
            case .shortcut:
                return HanlinEntryPointDescriptor(
                    kind: .appIntentBridge,
                    handler: manifest.id,
                    allowedContexts: [.appIntent]
                )
            case .chatCard, .shareExtension, .spotlight:
                findings.append(.init(
                    severity: .warning,
                    path: "apps/\(manifest.id)/entryPoints/\(entryPoint.rawValue)",
                    message: "No canonical entry-point kind exists; live behavior remains authoritative."
                ))
                return nil
            }
        }
        let declarations = try capabilities.map(project)
        if !manifest.keywords.isEmpty {
            findings.append(.init(
                severity: .information,
                path: "apps/\(manifest.id)/keywords",
                message: "Search keywords remain NativeAppPlatform metadata and are not represented canonically yet."
            ))
        }
        findings.append(.init(
            severity: .information,
            path: "apps/\(manifest.id)/appearance",
            message: "Only the leading accent color projects; gradient and foreground colors remain native metadata."
        ))

        let descriptor = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: descriptorRevision,
            id: appID,
            name: try localized(manifest.title),
            summary: try localized(manifest.subtitle),
            description: try localized(manifest.description),
            version: hostVersion,
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: manifest.systemImage),
            appearance: .init(accentHex: "#\(manifest.appearance.startHex)"),
            category: project(manifest.category),
            implementation: .native(moduleID: moduleID),
            entryPoints: entryPoints,
            capabilities: declarations,
            authors: [HanlinAuthor(name: "Hanlin")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: false,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )
        try descriptor.validate()
        return .init(descriptor: descriptor, findings: findings)
    }

    static func project(session: NativeAppSession) throws -> HanlinAppSessionDescriptor {
        HanlinAppSessionDescriptor(
            id: try HanlinAppSessionID(validating: session.id.uuidString.lowercased()),
            appID: try HanlinAppID(validating: session.appID),
            presentation: project(session.presentationStyle),
            state: session.isClosed ? .closed : .active,
            createdAt: session.createdAt,
            stateChangedAt: session.createdAt,
            activeChildOperationCount: nil
        )
    }

    private static func project(
        _ request: NativeCapabilityRequest
    ) throws -> HanlinCapabilityDeclaration {
        let capabilityRawValue: String = switch request.capability {
        case .network: "network.fetch"
        case .pasteboardRead: "pasteboard.read"
        case .pasteboardWrite: "pasteboard.write"
        case .contactsRead: "contacts.read"
        case .contactsWrite: "contacts.write"
        case .calendarRead: "calendar.read"
        case .calendarWrite: "calendar.write"
        case .filesRead: "files.read"
        case .filesWrite: "files.write"
        case .location: "location.read"
        case .notifications: "notifications.post"
        case .healthRead: "health.read"
        case .camera: "camera.capture"
        case .microphone: "microphone.capture"
        case .speech: "speech.recognize"
        case .translation: "translation.perform"
        }
        let capabilityID = try HanlinCapabilityID(validating: capabilityRawValue)
        let constraints: HanlinValue = request.domain.map {
            .object(["domain": .string($0)])
        } ?? .object([:])
        return HanlinCapabilityDeclaration(
            id: capabilityID,
            reason: try localized(request.reason),
            constraints: constraints,
            optional: request.optional,
            risk: request.capability == .network ? .read : .sensitiveRead,
            requiresSystemAuthorization: request.capability != .network
        )
    }

    private static func project(_ category: NativeAppCategory) -> HanlinAppCategory {
        switch category {
        case .knowledge: .knowledge
        case .productivity: .productivity
        case .utility: .utilities
        case .text: .productivity
        case .media: .media
        case .automation: .assistant
        case .developer: .developer
        }
    }

    private static func project(_ style: NativeAppPresentationStyle) -> HanlinPresentationIntent {
        switch style {
        case .fullScreen: .fullScreen
        case .largeSheet: .largeSheet
        case .newWindow: .newWindow
        }
    }

    private static func localized(_ value: String) throws -> LocalizedValue {
        try LocalizedValue(["en": value])
    }
}
