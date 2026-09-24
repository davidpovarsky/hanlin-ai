import Testing
@testable import AI_Hanlin
import HanlinPlatformContracts
import HanlinMiniAppCore

@Suite("Unified Host Services", .serialized)
struct HanlinUnifiedHostServicesTests {

    // MARK: - Context Construction

    @Test func agentContextHasAllCapabilities() {
        let context = HanlinHostCallContext.forAgent()
        #expect(context.effectiveCapabilities.contains("all"))
        #expect(context.origin == .assistantModel)
        #expect(context.appID == nil)
        #expect(context.canPresentUI == false)
    }

    @Test func miniAppContextScopesCapabilities() throws {
        let appID = try HanlinAppID(validating: "test-app")
        let caps: Set<String> = ["runtime.node", "files", "network"]
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .nativeModule,
            capabilities: caps,
            canPresentUI: true
        )
        #expect(context.effectiveCapabilities == caps)
        #expect(context.appID == appID)
        #expect(context.canPresentUI == true)
        #expect(!context.effectiveCapabilities.contains("all"))
    }

    @Test func miniAppContextDerivesWorkspaceIdentifier() throws {
        let appID = try HanlinAppID(validating: "my-app")
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .scriptPackage,
            capabilities: [],
            canPresentUI: false
        )
        #expect(context.runtimeWorkspaceIdentifier == "miniapp-my-app-\(context.appSessionID.rawValue)")
    }

    // MARK: - Capability Authority

    @Test func legacyAliasResolution() {
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("node") == "runtime.node")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("python") == "runtime.python")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("javascript") == "runtime.javascript")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("jsc") == "runtime.javascript")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("runtime.jsc") == "runtime.javascript")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("typescript") == "runtime.typescript")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("shell") == "runtime.shell")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("network.fetch") == "network")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("speech") == "speech-recognition")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("biometrics") == "local-authentication")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("icloud") == "cloud")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("sharesheet") == "share-sheet")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("vision") == "document-utilities")
        // Non-aliased IDs pass through unchanged
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("files") == "files")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("sqlite") == "sqlite")
        #expect(HanlinHostCapabilityAuthority.canonicalCapabilityID("network") == "network")
    }

    @Test func allKnownCapabilitiesHaveMetadata() {
        let allKnown = HanlinHostCapabilityMetadata.allKnown
        #expect(!allKnown.isEmpty)
        // Every capability should have a non-empty display name
        for metadata in allKnown {
            #expect(!metadata.id.isEmpty)
            #expect(!metadata.displayName.isEmpty)
        }
    }

    @Test func capabilityCheckWithAllWildcard() async {
        let context = HanlinHostCallContext.forAgent()
        let result = await HanlinHostCapabilityAuthority.shared.authorize(
            capability: "runtime.node",
            context: context
        )
        #expect(result == .allowed)
    }

    @Test func capabilityCheckDeniesUngranted() async throws {
        let appID = try HanlinAppID(validating: "limited-app")
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .nativeModule,
            capabilities: ["files"],
            canPresentUI: false
        )
        let result = await HanlinHostCapabilityAuthority.shared.authorize(
            capability: "runtime.node",
            context: context
        )
        #expect(result == .notGranted)
    }

    @Test func liveCapabilityGrantAndRevokeTakesImmediateEffect() async throws {
        let appID = try HanlinAppID(validating: "dynamic-perm-app")
        let authority = HanlinHostCapabilityAuthority.shared
        
        // Ensure clean initial state
        await authority.revoke(capability: "runtime.node", for: appID)
        
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .nativeModule,
            capabilities: ["files"],
            canPresentUI: false
        )
        
        // 1. Initial check: not granted
        let r1 = await authority.authorize(capability: "runtime.node", context: context)
        #expect(r1 == .notGranted)
        
        // 2. Grant dynamically at runtime
        await authority.grant(capability: "runtime.node", for: appID)
        
        // 3. Same context now immediately authorized without recreation!
        let r2 = await authority.authorize(capability: "runtime.node", context: context)
        #expect(r2 == .allowed)
        
        // 4. Revoke dynamically at runtime
        await authority.revoke(capability: "runtime.node", for: appID)
        
        // 5. Same context now immediately denied without recreation!
        let r3 = await authority.authorize(capability: "runtime.node", context: context)
        #expect(r3 == .notGranted)
    }

    // MARK: - Availability Store

    @Test func runtimesStoppedByDefaultOnFreshLaunch() {
        let store = RuntimeAvailabilityStore.shared
        // On a fresh launch before any start or auto-start, runtimes are stopped
        // (Unless a previous test started one, but reset() proves the default state)
        store.reset()
        for kind in RuntimeKind.allCases {
            #expect(!store.isAvailable(kind), "Runtime \(kind) should be stopped by default on fresh process")
        }
    }

    @Test func runtimeAvailabilityStateUpdates() {
        let store = RuntimeAvailabilityStore.shared
        let kind = RuntimeKind.javaScriptCore

        // Save original state and restore after test
        let original = store.isAvailable(kind)
        defer { store.setAvailable(original, for: kind) }

        store.setAvailable(false, for: kind)
        #expect(!store.isAvailable(kind))

        store.setAvailable(true, for: kind)
        #expect(store.isAvailable(kind))
    }

    @Test func typeScriptDependencyWarning() {
        let store = RuntimeAvailabilityStore.shared
        let originalNode = store.isAvailable(.node)
        defer { store.setAvailable(originalNode, for: .node) }

        store.setAvailable(false, for: .node)
        #expect(store.dependencyWarning(for: .typeScript) != nil)

        store.setAvailable(true, for: .node)
        #expect(store.dependencyWarning(for: .typeScript) == nil)
    }

    // MARK: - Error Descriptions

    @Test func allErrorCasesHaveDescription() {
        let errors: [HanlinHostServiceError] = [
            .runtimeDisabledByUser(.node),
            .capabilityNotGranted("test"),
            .systemAuthorizationDenied("test"),
            .systemCapabilityUnavailable("test"),
            .runtimeUnavailable(.node),
            .runtimeRestartRequired(.node),
            .invalidCallerContext("test"),
            .pathOutOfScope("test"),
            .sqliteFailure("test"),
            .cancelled,
            .timeout(.seconds(30)),
            .unsupportedByPlatform("test"),
            .quotaExceeded("test"),
            .invalidRequest("test"),
        ]
        for error in errors {
            #expect(error.errorDescription != nil, "\(error) should have errorDescription")
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Engine Enum

    @Test func scriptingJSCEngineExists() {
        let engine = HanlinMiniAppEngine.scriptingJSC
        #expect(engine.rawValue == "scriptingJSC")
        #expect(engine.displayName == "ScriptUI")
        #expect(HanlinMiniAppEngine.allCases.contains(.scriptingJSC))
    }

    // MARK: - Broker Capability Checks

    @Test func brokerRejectsUngrantedCapability() async throws {
        let appID = try HanlinAppID(validating: "no-caps-app")
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .nativeModule,
            capabilities: [],
            canPresentUI: false
        )
        do {
            try await HanlinHostServicesBroker.shared.requireCapability("files", context: context)
            Issue.record("Expected capabilityNotGranted error")
        } catch let error as HanlinHostServiceError {
            if case .capabilityNotGranted = error {
                // Expected
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test func brokerAllowsWildcardCapability() async throws {
        let context = HanlinHostCallContext.forAgent()
        // Should not throw
        try await HanlinHostServicesBroker.shared.requireCapability("files", context: context)
        try await HanlinHostServicesBroker.shared.requireCapability("runtime.node", context: context)
        try await HanlinHostServicesBroker.shared.requireCapability("sqlite", context: context)
    }

    // MARK: - File Path Validation

    @Test func fileServiceRejectsTraversal() {
        #expect(throws: HanlinHostServiceError.self) {
            try HanlinFileService.validatePath("../../etc/passwd")
        }
        #expect(throws: HanlinHostServiceError.self) {
            try HanlinFileService.validatePath("/absolute/path")
        }
        #expect(throws: HanlinHostServiceError.self) {
            try HanlinFileService.validatePath("")
        }
    }

    @Test func fileServiceAcceptsSafePaths() throws {
        try HanlinFileService.validatePath("documents/data.json")
        try HanlinFileService.validatePath("db.sqlite")
        try HanlinFileService.validatePath("nested/path/to/file.txt")
    }
}
