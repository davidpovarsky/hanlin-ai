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
        let expectedAppID = try HanlinAppID("test.miniapp")
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
            modelVisibleSummary: "Test summary",
            rawJSONPayload: "{\"metric\": 42}"
        )

        let session = resolver.resolve(
            handler: "test.miniapp:render_chart",
            payload: testPayload
        )

        #expect(session != nil)
        #expect(session?.engine == .swift)
        #expect(session?.appID == expectedAppID)
        #expect(receivedHandler == "render_chart")
        #expect(receivedPayload?.modelVisibleSummary == "Test summary")
    }

    @MainActor
    @Test("Resolver dispatches to injected ScriptUI, NativeScript and Expo test doubles")
    func resolverDispatchesToScriptingEngines() throws {
        let resolver = HanlinEmbeddedResultResolver()
        let packageID = try HanlinPackageID("com.example.package")

        resolver.customScriptUIResolver = { pkgID, handler, _ in
            guard pkgID == packageID && handler == "script_view" else { return nil }
            return AnyEmbeddedResultSession(
                engine: .scriptUI,
                appID: try! HanlinAppID("script.ui"),
                rootView: AnyView(Text("ScriptUI View"))
            )
        }

        resolver.customNativeScriptResolver = { pkgID, handler, _ in
            guard pkgID == packageID && handler == "native_view" else { return nil }
            return AnyEmbeddedResultSession(
                engine: .nativeScript,
                appID: try! HanlinAppID("native.script"),
                rootView: AnyView(Text("NativeScript View"))
            )
        }

        resolver.customExpoResolver = { pkgID, handler, _ in
            guard pkgID == packageID && handler == "expo_view" else { return nil }
            return AnyEmbeddedResultSession(
                engine: .expo,
                appID: try! HanlinAppID("expo.app"),
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
            appID: try HanlinAppID("lifecycle.test"),
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
    @Test("EmbeddedResultPayload preserves sizing, expansion, and metadata")
    func payloadPreservation() throws {
        let sizing = HanlinEmbeddedSizingPreference(
            preset: .large,
            idealHeight: 350,
            minimumHeight: 200,
            maximumHeight: 600
        )
        let expansion = HanlinExpansionDescriptor(
            supportedModes: [.sheet, .fullScreen]
        )
        let payload = HanlinEmbeddedResultPayload(
            modelVisibleSummary: "Calculated analytics",
            rawJSONPayload: "{\"val\": 123}",
            sizing: sizing,
            expansion: expansion
        )

        #expect(payload.modelVisibleSummary == "Calculated analytics")
        #expect(payload.sizing?.preset == .large)
        #expect(payload.sizing?.idealHeight == 350)
        #expect(payload.expansion?.supportedModes.contains(.sheet) == true)
        #expect(payload.expansion?.supportedModes.contains(.fullScreen) == true)
        #expect(payload.expansion?.supportedModes.contains(.window) == false)
    }

    @MainActor
    @Test("BoundedToolResultStore enforces capacity bounds and provides slices")
    func boundedResultStoreCapacity() throws {
        let store = BoundedToolResultStore(maxStoredBytes: 500)
        let ref1 = store.store("AAAAA")
        let ref2 = store.store("BBBBB")

        #expect(store.read(reference: ref1, offset: 0, limit: 10)?.text == "AAAAA")
        #expect(store.read(reference: ref2, offset: 0, limit: 10)?.text == "BBBBB")

        // Overfill store
        let large = String(repeating: "Z", count: 600)
        let ref3 = store.store(large)

        #expect(store.read(reference: ref3, offset: 0, limit: 10)?.text == "ZZZZZZZZZZ")
        // Older entries should be pruned to keep total stored bytes under bound
        #expect(store.read(reference: ref1, offset: 0, limit: 10) == nil)
    }
}
