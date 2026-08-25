import HanlinPlatformContracts
@testable import HanlinScriptingApplicationRuntime
import Foundation
import Testing

@Suite("Scripting application runtime", .serialized)
struct HanlinScriptingApplicationRuntimeTests {
    @MainActor
    @Test("Compiles and renders independently of the application target")
    func rendersIndependently() throws {
        let packageID = try HanlinInstalledPackageID(validating: "fast-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"Navigation.present({ element: createElement(Text, null, "Ready") });"#,
            filename: "compiled/index.js",
            storageAllowed: false
        )
        defer { session.dispose() }

        #expect(session.model.root.kind == .text)
        #expect(session.model.root.properties["text"] == .string("Ready"))
    }

    @MainActor
    @Test("Projects the native device snapshot into an immutable Scripting Device object")
    func deviceSnapshot() throws {
        let packageID = try HanlinInstalledPackageID(validating: "device-runtime-test")
        let snapshot = HanlinScriptingDeviceSnapshot(
            model: "iPad",
            localizedModel: "iPad",
            systemVersion: "26.5",
            systemName: "iPadOS",
            isiPad: true,
            isiPhone: false,
            screen: .init(width: 744, height: 1133, scale: 2),
            batteryState: "charging",
            batteryLevel: 0.75,
            proximityState: false,
            orientation: "landscapeRight",
            colorScheme: "dark",
            isiOSAppOnMac: false,
            systemLocale: "he_IL",
            preferredLanguages: ["he-IL", "en-US"],
            systemLanguageTag: "he-IL",
            systemLanguageCode: "he",
            systemCountryCode: "IL",
            systemScriptCode: "Hebr"
        )
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Navigation.present({ element: createElement(Text, null, JSON.stringify([
              Device.model, Device.systemName, Device.screen.width, Device.batteryState,
              Device.orientation, Device.colorScheme, Device.systemLanguageCode,
              Device.systemCountryCode, Device.isLandscape, Device.isPortrait,
              Object.isFrozen(Device), Object.isFrozen(Device.screen),
              Object.isFrozen(Device.preferredLanguages)
            ])) });
            """#,
            filename: "compiled/index.js",
            storageAllowed: false,
            deviceSnapshot: snapshot
        )
        defer { session.dispose() }

        #expect(session.model.root.properties["text"] == .string(
            #"["iPad","iPadOS",744,"charging","landscapeRight","dark","he","IL",true,false,true,true,true]"#
        ))
    }

    @Test("Decodes bounded Assistant requests and emits Web-compatible chunks")
    func assistantNativePayloads() throws {
        let request = try HanlinScriptingAssistantPayloadDecoder.decode(#"""
        {
          "kind": "streaming",
          "systemPrompt": "Be concise",
          "messages": [{"role":"user","content":"Hello"}],
          "provider": {"custom":"https://assistant.example/v1"},
          "modelId": "test-model"
        }
        """#)
        #expect(request.kind == .streaming)
        #expect(request.provider == .custom("https://assistant.example/v1"))
        #expect(request.modelID == "test-model")
        #expect(request.messagesJSON != nil)

        let usage = try HanlinScriptingAssistantChunk.usage(.init(
            totalCost: nil,
            cacheReadTokens: 4,
            inputTokens: 7,
            outputTokens: 3
        )).nativeObject()
        #expect(usage["type"] as? String == "usage")
        let content = try #require(usage["content"] as? [String: Any])
        #expect(content["inputTokens"] as? Int == 7)

        let structured = try HanlinScriptingAssistantChunk.structuredJSON(
            Data(#"{"answer":"verified"}"#.utf8)
        ).nativeObject()
        #expect(structured["type"] as? String == "structured")
        #expect((structured["content"] as? [String: Any])?["answer"] as? String == "verified")
    }

    @Test("SQLite executes parameterized statements and returns typed rows")
    func sqliteRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-sqlite-test-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = try HanlinScriptingPackageFileSystem(
            installedPackageID: "sqlite-test",
            allowed: true,
            runtimeRoot: root,
            packageSourceDirectory: nil
        )
        let store = HanlinScriptingSQLiteStore(fileSystem: fileSystem)
        let prefix = #"{"handle":"database-1","path":"/app-group/history.sqlite","configuration":{"foreignKeysEnabled":true,"journalMode":"wal","busyMode":1},"#
        _ = try store.perform(
            operation: "sqlite.execute",
            payloadJSON: prefix + #""sql":"CREATE TABLE items (id TEXT PRIMARY KEY, count INTEGER, enabled INTEGER)","arguments":null}"#
        )
        _ = try store.perform(
            operation: "sqlite.execute",
            payloadJSON: prefix + #""sql":"INSERT INTO items VALUES (:id, :count, :enabled)","arguments":{"id":"one","count":7,"enabled":1}}"#
        )
        let result = try store.perform(
            operation: "sqlite.fetchAll",
            payloadJSON: prefix + #""sql":"SELECT id, count, enabled FROM items WHERE id = ?","arguments":["one"]}"#
        )
        let rows = try #require(result as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["id"] as? String == "one")
        #expect((rows[0]["count"] as? NSNumber)?.intValue == 7)
        #expect((rows[0]["enabled"] as? NSNumber)?.intValue == 1)
    }

    @Test("Location requests validate capabilities, coordinates, locales, and accuracy")
    func locationPayloads() throws {
        let current = try HanlinScriptingLocationPayloadDecoder.decode(
            operation: "location.requestCurrent",
            json: #"{"forceRequest":true}"#
        )
        #expect(current.action == .requestCurrent)
        #expect(current.forceRequest)

        let reverse = try HanlinScriptingLocationPayloadDecoder.decode(
            operation: "location.reverseGeocode",
            json: #"{"latitude":31.7683,"longitude":35.2137,"locale":"he_IL"}"#
        )
        #expect(reverse.latitude == 31.7683)
        #expect(reverse.longitude == 35.2137)
        #expect(reverse.localeIdentifier == "he_IL")

        let accuracy = try HanlinScriptingLocationPayloadDecoder.decode(
            operation: "location.setAccuracy",
            json: #"{"accuracy":"hundredMeters"}"#
        )
        #expect(accuracy.accuracy == "hundredMeters")

        #expect(throws: (any Error).self) {
            try HanlinScriptingLocationPayloadDecoder.decode(
                operation: "location.reverseGeocode",
                json: #"{"latitude":91,"longitude":35}"#
            )
        }
        #expect(throws: (any Error).self) {
            try HanlinScriptingLocationPayloadDecoder.decode(
                operation: "location.setAccuracy",
                json: #"{"accuracy":"unbounded"}"#
            )
        }
    }
}
