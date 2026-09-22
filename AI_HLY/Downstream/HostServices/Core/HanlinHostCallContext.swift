import Foundation
import HanlinPlatformContracts

public enum HanlinHostStorageScope: Sendable, Hashable, Equatable {
    case app(HanlinAppID)
    case package(HanlinInstalledPackageID)
    case agent
    case system
    case shared
}

public struct HanlinHostCallContext: Sendable {
    public let subject: HanlinPermissionSubject
    public let origin: HanlinExecutionOrigin
    public let appID: HanlinAppID?
    public let installedPackageID: HanlinInstalledPackageID?
    public let appSessionID: HanlinAppSessionID
    public let runtimeSessionID: HanlinRuntimeSessionID
    public let effectiveCapabilities: Set<String>
    public let storageScope: HanlinHostStorageScope
    public let runtimeWorkspaceIdentifier: String
    public let userGesturePresent: Bool
    public let canPresentUI: Bool

    public init(
        subject: HanlinPermissionSubject,
        origin: HanlinExecutionOrigin,
        appID: HanlinAppID?,
        installedPackageID: HanlinInstalledPackageID?,
        appSessionID: HanlinAppSessionID,
        runtimeSessionID: HanlinRuntimeSessionID,
        effectiveCapabilities: Set<String>,
        storageScope: HanlinHostStorageScope,
        runtimeWorkspaceIdentifier: String,
        userGesturePresent: Bool,
        canPresentUI: Bool
    ) {
        self.subject = subject
        self.origin = origin
        self.appID = appID
        self.installedPackageID = installedPackageID
        self.appSessionID = appSessionID
        self.runtimeSessionID = runtimeSessionID
        self.effectiveCapabilities = effectiveCapabilities
        self.storageScope = storageScope
        self.runtimeWorkspaceIdentifier = runtimeWorkspaceIdentifier
        self.userGesturePresent = userGesturePresent
        self.canPresentUI = canPresentUI
    }

    // MARK: - Convenience Factories

    private static func makeSessionID(kind: String) -> String {
        // Lowercase hex UUID suitable for HanlinStringIdentifier validation
        UUID().uuidString.lowercased()
    }

    public static func forAgent(
        runtimeSessionID: HanlinRuntimeSessionID? = nil
    ) -> HanlinHostCallContext {
        let appSession = try! HanlinAppSessionID(validating: makeSessionID(kind: "app-session"))
        let runtimeSession = runtimeSessionID ?? (try! HanlinRuntimeSessionID(validating: makeSessionID(kind: "runtime-session")))
        return HanlinHostCallContext(
            subject: .provider(try! HanlinProviderInstanceID(validating: "hanlin-assistant")),
            origin: .assistantModel,
            appID: nil,
            installedPackageID: nil,
            appSessionID: appSession,
            runtimeSessionID: runtimeSession,
            effectiveCapabilities: ["all"],
            storageScope: .agent,
            runtimeWorkspaceIdentifier: "agent-\(runtimeSession.rawValue)",
            userGesturePresent: false,
            canPresentUI: false
        )
    }

    public static func forMiniApp(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID? = nil,
        origin: HanlinExecutionOrigin,
        capabilities: Set<String>,
        sessionID: HanlinAppSessionID? = nil,
        runtimeSessionID: HanlinRuntimeSessionID? = nil,
        storageScope: HanlinHostStorageScope? = nil,
        canPresentUI: Bool
    ) -> HanlinHostCallContext {
        let appSession = sessionID ?? (try! HanlinAppSessionID(validating: makeSessionID(kind: "app-session")))
        let runtimeSession = runtimeSessionID ?? (try! HanlinRuntimeSessionID(validating: makeSessionID(kind: "runtime-session")))
        let resolvedScope = storageScope ?? (installedPackageID.map { .package($0) } ?? .app(appID))
        return HanlinHostCallContext(
            subject: .app(appID, installedPackageID: installedPackageID),
            origin: origin,
            appID: appID,
            installedPackageID: installedPackageID,
            appSessionID: appSession,
            runtimeSessionID: runtimeSession,
            effectiveCapabilities: capabilities,
            storageScope: resolvedScope,
            runtimeWorkspaceIdentifier: "miniapp-\(appID.rawValue)-\(appSession.rawValue)",
            userGesturePresent: false,
            canPresentUI: canPresentUI
        )
    }
}
