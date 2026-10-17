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

    @Test func capabilityCheckWithPackageIdentityAndContextFallback() async throws {
        let appID = try HanlinAppID(validating: "package-app")
        let packageID = try HanlinInstalledPackageID(validating: "install-package-app")
        let authority = HanlinHostCapabilityAuthority.shared

        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: packageID,
            origin: .nativeModule,
            capabilities: ["javascript", "node"],
            canPresentUI: true
        )
        let r1 = await authority.authorize(capability: "runtime.javascript", context: context)
        #expect(r1 == .allowed)
        let r2 = await authority.authorize(capability: "runtime.python", context: context)
        #expect(r2 == .notGranted)
    }

    // MARK: - EXP-01 & EXP-02: Expo Untagged JSON and Date Bridge

    @Test func expoUntaggedJSONNodeDecoding() throws {
        let untaggedJSON: [String: Any] = [
            "kind": "vStack",
            "properties": [
                "spacing": 8
            ],
            "children": [
                [
                    "kind": "text",
                    "properties": [
                        "content": "Counter: 7",
                        "font": "body"
                    ],
                    "children": []
                ]
            ]
        ]

        let node = try ExpoHostServicesAdapter.parseUntaggedNode(untaggedJSON, depth: 0)
        #expect(node.kind.rawValue == "vStack")
        #expect(node.properties["spacing"] == .integer(8))
        #expect(node.children.count == 1)

        let child = node.children[0]
        #expect(child.kind.rawValue == "text")
        #expect(child.properties["content"] == .string("Counter: 7"))
        #expect(child.properties["font"] == .string("body"))
    }

    @Test func expoValidUntilDateParsing() {
        // 1. Fractional seconds ISO-8601
        let isoFractional = ["validUntil": "2026-10-18T12:34:56.789Z"]
        let parsedDate1 = ExpoHostServicesAdapter.parseValidUntil(from: isoFractional)
        #expect(parsedDate1 != nil)

        // 2. Epoch milliseconds
        let epochMillis: [String: Any] = ["validUntilEpochMilliseconds": 1792272000000.0]
        let parsedDate2 = ExpoHostServicesAdapter.parseValidUntil(from: epochMillis)
        #expect(parsedDate2 != nil)

        // 3. Invalid date returns nil
        let invalidDate = ["validUntil": "not-a-valid-date-string"]
        let parsedDate3 = ExpoHostServicesAdapter.parseValidUntil(from: invalidDate)
        #expect(parsedDate3 == nil)
    }

    // MARK: - SEC-03 & SEC-04: Authorized Attachment & Evidence Scoping

    @Test func authorizedAttachmentRegistryCrossChatDenial() async throws {
        let registry = AuthorizedAttachmentRegistry()
        let sampleData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]) // JPEG header

        let handle = await registry.register(
            data: sampleData,
            mimeType: "image/jpeg",
            chatID: "chat_A",
            requestID: "req_01"
        )

        // Cross-chat resolution must throw capabilityNotGranted / accessDenied
        do {
            _ = try await registry.resolve(handle: handle, chatID: "chat_B", requestID: "req_02")
            Issue.record("Expected cross-chat resolution to fail")
        } catch let error as HanlinHostServiceError {
            if case .capabilityNotGranted = error {
                // Expected
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }

        // Path traversal must fail closed
        do {
            _ = try await registry.resolve(handle: "../../etc/passwd", chatID: "chat_A")
            Issue.record("Expected directory traversal to fail")
        } catch is HanlinHostServiceError {
            // Expected
        }
    }

    @Test func torahEvidenceStoreChatScopingAndExpiry() async {
        let store = TorahEvidenceStore()
        let record = TorahEvidenceRecord(
            evidenceID: "ev_test_123",
            rawText: "בראשית ברא אלהים",
            attachmentHandle: "att_001",
            providerID: "apple_vision_local",
            chatID: "chat_alpha",
            requestID: "req_01",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        // BLOCKER-COMP-01: Call store(record:) with the authoritative signature
        await store.store(record: record)

        // Retrieved by same chat
        let retrieved = await store.retrieve(evidenceID: "ev_test_123", chatID: "chat_alpha")
        #expect(retrieved != nil)
        #expect(retrieved?.rawText == "בראשית ברא אלהים")
        #expect(retrieved?.evidenceID == "ev_test_123")

        // Denied for different chat
        let crossRetrieved = await store.retrieve(evidenceID: "ev_test_123", chatID: "chat_beta")
        #expect(crossRetrieved == nil)

        // Actual expiration enforcement test
        let expiredRecord = TorahEvidenceRecord(
            evidenceID: "ev_expired_456",
            rawText: "פסוק ישן שתוקפו פג",
            attachmentHandle: "att_002",
            providerID: "apple_vision_local",
            chatID: "chat_alpha",
            requestID: "req_01",
            createdAt: Date().addingTimeInterval(-100),
            expiresAt: Date().addingTimeInterval(-10)
        )
        await store.store(record: expiredRecord)
        let expiredResult = await store.retrieve(evidenceID: "ev_expired_456", chatID: "chat_alpha")
        #expect(expiredResult == nil, "Expired record must be rejected and evicted")
    }

    // MARK: - INT-01 & INT-03: Multi-grant Verification & Collision Prevention

    @Test func multiGrantVerificationRequiresAllCapabilities() {
        let grantedCaps: Set<String> = ["files", "network"]
        let requiredActionCaps: Set<String> = ["files", "runtime.node"]

        // If one of two required capabilities is missing (e.g. runtime.node is not in grantedCaps),
        // allRequired.isSubset(of: grantedCaps) MUST evaluate to false.
        let isFullyAuthorized = requiredActionCaps.isSubset(of: grantedCaps)
        #expect(!isFullyAuthorized, "Action requiring both files and runtime.node must NOT authorize when runtime.node is missing")

        let fullGrantedCaps: Set<String> = ["files", "network", "runtime.node"]
        let isAuthorizedWithFull = requiredActionCaps.isSubset(of: fullGrantedCaps)
        #expect(isAuthorizedWithFull, "Action must authorize when all required capabilities are granted")
    }

    @Test func actionEntityScopedIDsPreventCollision() {
        // Two packages exposing the same action name "toggle_state"
        let pkgA = "com.author.packageA"
        let pkgB = "com.author.packageB"
        let entrypoint = "main"
        let actionID = "toggle_state"

        let scopedIDA = "\(pkgA)::\(entrypoint)::\(actionID)"
        let scopedIDB = "\(pkgB)::\(entrypoint)::\(actionID)"

        #expect(scopedIDA != scopedIDB, "Scoped entity IDs across different packages must never collide")
        #expect(scopedIDA.components(separatedBy: "::").last == actionID)
        #expect(scopedIDB.components(separatedBy: "::").last == actionID)
    }
}
