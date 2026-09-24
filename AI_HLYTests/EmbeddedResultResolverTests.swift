import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftUI
import Testing

@testable import AI_Hanlin

@Suite("Embedded Result Resolver and Engine Adapters Tests", .serialized)
struct EmbeddedResultResolverTests {

    @MainActor
    @Test("Resolver dispatches to injected Swift test double")
    func resolverDispatchesToSwift() throws {
        let resolver = HanlinEmbeddedResultResolver()
        let expectedAppID = try HanlinAppID(validating: "test.miniapp")
        var receivedHandler: String?
        var receivedPayload: HanlinEmbeddedResultPayload?

        resolver.customSwiftResolver = { appID, handler, payload in
            guard appID == expectedAppID else { return nil }
            receivedHandler = handler
            receivedPayload = payload
            return AnyEmbeddedResultSession(
                engine: .swift,
                appID: appID,
                rootView: AnyView(Text("Swift Mock View"))
            )
        }

        let testPayload = HanlinEmbeddedResultPayload(
            payload: .string("{\"metric\": 42}"),
            resultReference: "ref_test",
            title: "Test summary",
            metadata: ["metric": "42"]
        )

        let session = resolver.resolve(
            handler: "test.miniapp:render_chart",
            payload: testPayload
        )

        #expect(session != nil)
        #expect(session?.engine == .swift)
        #expect(session?.appID == expectedAppID)
        #expect(receivedHandler == "render_chart")
        #expect(receivedPayload?.title == "Test summary")
    }

    @MainActor
    @Test("Resolver dispatches to injected ScriptUI, NativeScript and Expo test doubles")
    func resolverDispatchesToScriptingEngines() throws {
        let resolver = HanlinEmbeddedResultResolver()
        let packageID = try HanlinPackageID(validating: "com.example.package")

        resolver.customScriptUIResolver = { pkgID, handler, _ in
            guard pkgID == packageID && handler == "script_view" else { return nil }
            return AnyEmbeddedResultSession(
                engine: .scriptUI,
                appID: try! HanlinAppID(validating: "script.ui"),
                rootView: AnyView(Text("ScriptUI View"))
            )
        }

        resolver.customNativeScriptResolver = { pkgID, handler, _ in
            guard pkgID == packageID && handler == "native_view" else { return nil }
            return AnyEmbeddedResultSession(
                engine: .nativeScript,
                appID: try! HanlinAppID(validating: "native.script"),
                rootView: AnyView(Text("NativeScript View"))
            )
        }

        resolver.customExpoResolver = { pkgID, handler, _ in
            guard pkgID == packageID && handler == "expo_view" else { return nil }
            return AnyEmbeddedResultSession(
                engine: .expo,
                appID: try! HanlinAppID(validating: "expo.app"),
                rootView: AnyView(Text("Expo View"))
            )
        }

        let s1 = resolver.resolve(handler: "com.example.package:script_view")
        #expect(s1?.engine == .scriptUI)

        let s2 = resolver.resolve(handler: "com.example.package:native_view")
        #expect(s2?.engine == .nativeScript)

        let s3 = resolver.resolve(handler: "com.example.package:expo_view")
        #expect(s3?.engine == .expo)
    }

    @MainActor
    @Test("Resolver returns nil for unknown handler enabling fallback")
    func resolverFallbackOnUnknown() throws {
        let resolver = HanlinEmbeddedResultResolver()
        let session = resolver.resolve(handler: "nonexistent.app:unknown_card")
        #expect(session == nil)

        let empty = resolver.resolve(handler: "")
        #expect(empty == nil)
    }

    @MainActor
    @Test("Session lifecycle correctly executes onTearDown handler")
    func sessionLifecycleTearDown() throws {
        var didTearDown = false
        let session = AnyEmbeddedResultSession(
            engine: .swift,
            appID: try HanlinAppID(validating: "lifecycle.test"),
            rootView: AnyView(Text("Content")),
            onTearDown: {
                didTearDown = true
            }
        )

        #expect(!didTearDown)
        session.tearDown()
        #expect(didTearDown)
    }

    @MainActor
    @Test("EmbeddedResultPayload preserves payload, reference, title, and metadata")
    func payloadPreservation() throws {
        let payload = HanlinEmbeddedResultPayload(
            payload: .string("{\"val\": 123}"),
            resultReference: "ref_analytics",
            title: "Calculated analytics",
            metadata: ["source": "tool_exec"]
        )

        #expect(payload.title == "Calculated analytics")
        #expect(payload.resultReference == "ref_analytics")
        #expect(payload.metadata?["source"] == "tool_exec")
        if case .string(let val)? = payload.payload {
            #expect(val == "{\"val\": 123}")
        } else {
            #expect(Bool(false), "Payload value was not string")
        }
    }

    @MainActor
    @Test("BoundedToolResultStore enforces capacity bounds and provides slices")
    func boundedResultStoreCapacity() throws {
        let store = BoundedToolResultStore(maxStoredBytes: 500)
        let ref1 = try #require(store.store(String(repeating: "A", count: 200)))
        let ref2 = try #require(store.store(String(repeating: "B", count: 200)))

        #expect(!ref1.isEmpty && !ref2.isEmpty)
        #expect(store.currentTotalBytes == 400)
        #expect(store.read(reference: ref1, offset: 0, limit: 10)?.text == "AAAAAAAAAA")
        #expect(store.read(reference: ref2, offset: 0, limit: 10)?.text == "BBBBBBBBBB")

        // 1. Oversized entry that individually exceeds maxTotalBytes (600 > 500) is rejected returning nil
        let refOversized = store.store(String(repeating: "Z", count: 600))
        #expect(refOversized == nil)
        #expect(store.currentTotalBytes == 400)
        #expect(store.read(reference: ref1, offset: 0, limit: 10)?.text == "AAAAAAAAAA")

        // 2. Adding a valid entry (200 bytes) pushes total (600 > 500), evicting oldest (ref1)
        let ref3 = try #require(store.store(String(repeating: "C", count: 200)))
        #expect(!ref3.isEmpty)
        #expect(store.currentTotalBytes == 400)
        #expect(store.read(reference: ref1, offset: 0, limit: 10) == nil)
        #expect(store.read(reference: ref2, offset: 0, limit: 10)?.text == "BBBBBBBBBB")
        #expect(store.read(reference: ref3, offset: 0, limit: 10)?.text == "CCCCCCCCCC")
    }

    @MainActor
    @Test("BoundedToolResultStore hard bound rejection returns nil and preserves existing data")
    func boundedResultStoreHardBoundRejection() throws {
        let store = BoundedToolResultStore(maxStoredBytes: 1000)
        let initialRef = try #require(store.store("Initial data that fits", mimeType: "text/plain"))
        #expect(store.currentTotalBytes == "Initial data that fits".utf8.count)

        // Attempting to store single payload strictly exceeding 1000 bytes returns nil
        let hugePayload = String(repeating: "X", count: 1001)
        let rejectedRef = store.store(hugePayload, mimeType: "text/plain")
        #expect(rejectedRef == nil)

        // Existing store data is completely uncorrupted and retains its exact bytes
        #expect(store.currentTotalBytes == "Initial data that fits".utf8.count)
        #expect(store.read(reference: initialRef, offset: 0, limit: 50)?.text == "Initial data that fits")
    }

    @MainActor
    @Test("BoundedToolResultStore supports Unicode UTF-8 multi-byte pagination without truncation")
    func resultStoreUnicodePagination() throws {
        let store = BoundedToolResultStore(maxStoredBytes: 2048)
        let hebrewText = "שלום עולם! בדיקת תוצאה משובצת במסד נתונים מקומי."
        let ref = try #require(store.store(hebrewText))
        #expect(!ref.isEmpty)

        // Read initial chunk
        let slice1 = store.read(reference: ref, offset: 0, limit: 15)
        #expect(slice1 != nil)
        #expect(!slice1!.chunk.isEmpty)
        #expect(slice1!.hasMore)

        // Read with offset mid-character: snaps forward to valid leading UTF-8 byte
        let sliceMid = store.read(reference: ref, offset: 1, limit: 20)
        #expect(sliceMid != nil)
        #expect(!sliceMid!.chunk.isEmpty)

        // Full payload retrieval returns identical string
        let full = store.fullPayload(for: ref)
        #expect(full == hebrewText)
    }

    @MainActor
    @Test("ResultStore entries expire and clear upon session run finish")
    func resultStoreSessionCleanup() throws {
        let session = AssistantCapabilitySession()
        let ref = try #require(session.resultStore.store("temporary run artifact"))
        #expect(!ref.isEmpty)
        #expect(session.resultStore.read(reference: ref, offset: 0, limit: 10)?.text == "temporary ")

        session.finishRun()
        #expect(session.resultStore.currentTotalBytes == 0)
        #expect(session.resultStore.read(reference: ref, offset: 0, limit: 10) == nil)
    }

    @MainActor
    @Test("Swift embedded adapter strictly resolves custom view and never embeds full app")
    func swiftAdapterStrictResolution() throws {
        let sefariaAppID = try HanlinAppID(validating: "nativeapp.sefaria")
        // Sefaria provider exists and conforms to HanlinCompiledMiniAppProvider (makeRootView),
        // but does NOT conform to HanlinCompiledEmbeddedResultProvider.
        // It must cleanly return nil rather than embedding the entire foreground application!
        let session = SwiftEmbeddedResultAdapter.resolve(
            appID: sefariaAppID,
            handler: "custom_card",
            payload: nil
        )
        #expect(session == nil)
    }

    @MainActor
    @Test("ScriptUI, NativeScript and Expo adapters return nil for undeclared handlers")
    func scriptingAdaptersStrictResolution() throws {
        let unknownPackageID = try HanlinPackageID(validating: "com.example.nonexistent")
        let scriptSession = ScriptUIEmbeddedResultAdapter.resolve(
            packageID: unknownPackageID,
            handler: "chart_view",
            payload: nil
        )
        #expect(scriptSession == nil)

        let nativeSession = NativeScriptEmbeddedResultAdapter.resolve(
            packageID: unknownPackageID,
            handler: "native_chart",
            payload: nil
        )
        #expect(nativeSession == nil)

        let expoSession = ExpoEmbeddedResultAdapter.resolve(
            packageID: unknownPackageID,
            handler: "expo_chart",
            payload: nil
        )
        #expect(expoSession == nil)
    }

    @MainActor
    @Test("Resolver uses explicit owner identity and never falls back to toolName guessing")
    func resolverOwnerIdentityRouting() throws {
        let resolver = HanlinEmbeddedResultResolver()
        var receivedAppID: HanlinAppID?

        resolver.customSwiftResolver = { appID, handler, _ in
            receivedAppID = appID
            return AnyEmbeddedResultSession(
                engine: .swift,
                appID: appID,
                rootView: AnyView(Text("View"))
            )
        }

        // 1. Explicit ownerID is respected
        let session1 = resolver.resolve(
            handler: "render_view",
            ownerID: "explicit.app",
            toolName: "some_unrelated_tool",
            payload: nil
        )
        #expect(session1 != nil)
        #expect(receivedAppID?.rawValue == "explicit.app")

        // 2. Unqualified handler with NO ownerID returns nil — toolName is NEVER guessed as appID!
        receivedAppID = nil
        let session2 = resolver.resolve(
            handler: "render_view",
            ownerID: nil,
            toolName: "some_unrelated_tool",
            payload: nil
        )
        #expect(session2 == nil)
        #expect(receivedAppID == nil)

        // 3. Qualified handler format "owner:handler" resolves
        let session3 = resolver.resolve(
            handler: "qualified.app:render_view",
            ownerID: nil,
            toolName: nil,
            payload: nil
        )
        #expect(session3 != nil)
        #expect(receivedAppID?.rawValue == "qualified.app")
    }

    @MainActor
    @Test("ChatPresentationBridge resolves multiple valid expansions and validates expandedHandler")
    func chatPresentationBridgeMultiExpansions() throws {
        // 1. Multiple valid expansion modes coexist
        let multiDescriptor = HanlinExpansionDescriptor(
            supportedModes: [.sheet, .fullScreen]
        )
        let expansions = ChatPresentationBridge.resolveExpansions(
            descriptor: multiDescriptor,
            title: "Result View"
        )
        #expect(expansions.count == 2)
        #expect(expansions[0].mode == .sheet)
        #expect(expansions[1].mode == .fullScreen)

        // 2. When expandedHandler cannot resolve, expansion is excluded
        let expDescriptor = HanlinExpansionDescriptor(
            supportedModes: [.sheet],
            expandedHandler: "modal_expanded_view"
        )
        let rejected = ChatPresentationBridge.resolveExpansions(
            descriptor: expDescriptor,
            canResolveHandler: { _ in false }
        )
        #expect(rejected.isEmpty)

        // 3. When expandedHandler resolves, expansion is included with expandedHandler
        let accepted = ChatPresentationBridge.resolveExpansions(
            descriptor: expDescriptor,
            canResolveHandler: { handler in handler == "modal_expanded_view" }
        )
        #expect(accepted.count == 1)
        #expect(accepted.first?.expandedHandler == "modal_expanded_view")
    }

    @MainActor
    @Test("HanlinEmbeddedContentAction and HanlinLaunchRequest preserve canonical structure")
    func contentActionsAndLaunchRequestStructure() throws {
        let appID = try HanlinAppID(validating: "nativeapp.maps")
        let legacyRequest = NativeAppLaunchRequest(
            id: UUID(),
            appID: "nativeapp.maps",
            presentationStyle: .fullScreen,
            initialRoute: nil
        )

        let canonicalRequest = legacyRequest.toCanonical()
        #expect(canonicalRequest.target.appID == appID)
        #expect(canonicalRequest.presentation == .fullScreen)

        let action = HanlinEmbeddedContentAction(
            id: "navigate_maps",
            title: "Navigate",
            systemImage: "map.fill",
            launchRequest: canonicalRequest
        )

        let payload = HanlinEmbeddedResultPayload(
            ownerID: "nativeapp.maps",
            actions: [action]
        )

        #expect(payload.ownerID == "nativeapp.maps")
        #expect(payload.actions.count == 1)
        #expect(payload.actions[0].id == "navigate_maps")
        #expect(payload.actions[0].title == "Navigate")
        #expect(payload.actions[0].systemImage == "map.fill")

        // Round-trip conversion
        let roundTripLegacy = canonicalRequest.toLegacy()
        #expect(roundTripLegacy.appID == "nativeapp.maps")
        #expect(roundTripLegacy.presentationStyle == .fullScreen)
    }

    @MainActor
    @Test("HanlinEmbeddedContentAction pipeline correctly bridges from payload to transcript item and handles callback dispatch")
    func contentActionsPipelineAndDispatch() throws {
        let launchReq = HanlinLaunchRequest(
            id: HanlinLaunchID(unchecked: "launch-pipeline-test"),
            requestID: HanlinRequestID(unchecked: "req-pipeline-test"),
            target: HanlinLaunchTarget(appID: try HanlinAppID(validating: "test.app")),
            presentation: .largeSheet,
            origin: .assistantModel
        )
        let action1 = HanlinEmbeddedContentAction(
            id: "action_1",
            title: "Action One",
            systemImage: "play.circle",
            launchRequest: launchReq
        )
        let action2 = HanlinEmbeddedContentAction(
            id: "action_2",
            title: "Action Two",
            systemImage: "star.fill"
        )

        let payload = HanlinEmbeddedResultPayload(
            ownerID: "test.app",
            actions: [action1, action2]
        )

        let item = AgentTranscriptItem(
            externalID: "item-test",
            sequence: 1,
            kind: .userVisibleToolResult,
            callID: "call-1",
            toolName: "test_tool",
            resultRendererKind: .modernNative,
            resultPresentationRequest: .card,
            startedAt: Date(),
            completedAt: Date(),
            status: .completed,
            nativeUIBlocks: [],
            visibilityAfterCompletion: .remainInChat,
            embeddedResultPayload: payload
        )

        #expect(item.embeddedResultPayload?.actions.count == 2)
        #expect(item.embeddedResultPayload?.actions[0].id == "action_1")
        #expect(item.embeddedResultPayload?.actions[0].launchRequest?.id.rawValue == "launch-pipeline-test")

        // Launch request conversion to legacy for chat host
        var dispatchedLegacyLaunch: NativeAppLaunchRequest?
        let onLaunch: (NativeAppLaunchRequest) -> Void = { req in
            dispatchedLegacyLaunch = req
        }
        if let legacy = item.embeddedResultPayload?.actions[0].launchRequest?.toLegacy() {
            onLaunch(legacy)
        }
        #expect(dispatchedLegacyLaunch?.appID == "test.app")
        #expect(dispatchedLegacyLaunch?.presentationStyle == .largeSheet)
    }

    @MainActor
    @Test("ScriptUI application session receives structured EmbeddedInput when launched via embeddedResult context")
    func scriptUIEmbeddedInputContext() throws {
        let packageID = try HanlinPackageID(validating: "com.example.scriptui")
        let installedPackageID = try HanlinInstalledPackageID(validating: "pkg-scriptui-test")
        let payload = HanlinEmbeddedResultPayload(
            resultReference: "ref_script_123",
            ownerID: packageID.rawValue
        )

        let context = HanlinScriptingEntrypointContext.embeddedResult(
            handler: "custom_embedded_card",
            payloadJSON: "{\"score\": 99}",
            resultReference: payload.resultReference,
            ownerID: packageID.rawValue
        )

        let session = try HanlinScriptingApplicationSession(
            installedPackageID: installedPackageID,
            program: #"Navigation.present({ element: createElement(Text, null, "Ready") });"#,
            filename: "main.js",
            entrypointContext: context,
            storageAllowed: false
        )

        #expect(session.embeddedInput != nil)
        #expect(session.embeddedInput?.handler == "custom_embedded_card")
        #expect(session.embeddedInput?.payloadJSON == "{\"score\": 99}")
        #expect(session.embeddedInput?.resultReference == "ref_script_123")
        #expect(session.embeddedInput?.ownerID == "com.example.scriptui")

        session.dispose()
    }
}
