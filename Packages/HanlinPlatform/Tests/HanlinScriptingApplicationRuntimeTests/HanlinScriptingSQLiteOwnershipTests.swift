import Foundation
import Testing
@testable import HanlinScriptingApplicationRuntime
import HanlinPlatformContracts

@Suite("Actual SQLite JavaScript ownership", .serialized)
struct HanlinScriptingSQLiteOwnershipTests {
    @MainActor
    @Test("Original JS database owners retain more than sixteen independent temporary databases")
    func liveOwnersAndDisposal() async throws {
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: .init(validating: "sqlite-owner-proof"),
            program: #"""
            Navigation.present({ element: createElement(Text, null, "Waiting") });
            globalThis.databases = [];
            (async () => {
              for (let i = 0; i < 24; i++) {
                const db = SQLite.openInMemory(`owner-${i}`);
                databases.push(db);
                await db.execute("CREATE TEMP TABLE state(value INTEGER); INSERT INTO state VALUES (?)", [i]);
              }
              const values = [];
              for (const db of databases) values.push((await db.fetchOne("SELECT value FROM state")).value);
              Navigation.present({ element: createElement(Text, null, JSON.stringify(values)) });
            })().catch(error => Navigation.present({ element: createElement(Text, null, String(error)) }));
            """#,
            filename: "sqlite-owners.js", storageAllowed: true
        )
        defer { session.dispose() }
        await session.waitForNativeQuiescence()
        #expect(session.model.root.properties["text"] == .string("[" + (0..<24).map(String.init).joined(separator: ",") + "]"))
        #expect(session.openSQLiteDatabaseCount == 24)
        session.dispose()
        // Wait for actual C handles to close; disposal does not fabricate a zero count.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.openSQLiteDatabaseCount != 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(session.openSQLiteDatabaseCount == 0)
    }

    @MainActor
    @Test("Actual JavaScript Data round trip preserves empty BLOB and an ordinary column matching the private tag")
    func originalDataRoundTrip() async throws {
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: .init(validating: "sqlite-data-proof"),
            program: #"""
            Navigation.present({ element: createElement(Text, null, "Waiting") });
            (async () => {
              const db = SQLite.openInMemory();
              const binary = Data.fromBase64String("AAH+/w==");
              const empty = Data.fromBase64String("");
              const text = "שלום\u0000tail";
              const row = await db.fetchOne("SELECT ? AS binary, ? AS empty, ? AS text, NULL AS missing, 'ordinary' AS __hanlinSQLiteData, typeof(?) AS binaryType, typeof(?) AS emptyType", [binary, empty, text, binary, empty]);
              const named = await db.fetchOne("SELECT :__hanlinSQLiteData AS normal", { __hanlinSQLiteData: "ordinary" });
              const result = [row.binary.toBase64String(), row.empty.toBase64String(), row.text === text, row.missing === null, row.__hanlinSQLiteData, row.binaryType, row.emptyType, named.normal];
              Navigation.present({ element: createElement(Text, null, JSON.stringify(result)) });
            })().catch(error => Navigation.present({ element: createElement(Text, null, String(error)) }));
            """#,
            filename: "sqlite-data.js", storageAllowed: true
        )
        defer { session.dispose() }
        await session.waitForNativeQuiescence()
        #expect(session.model.root.properties["text"] == .string(#"["AAH+/w==","",true,true,"ordinary","blob","blob","ordinary"]"#))
    }

    @Test("Store validates before side effects and preserves remaining owners when one handle is released")
    func releasedHandleAndStoppedStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "sqlite-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = try HanlinScriptingPackageFileSystem(installedPackageID: "sqlite-store", allowed: true, runtimeRoot: root, packageSourceDirectory: nil)
        let store = HanlinScriptingSQLiteStore(fileSystem: fileSystem)
        defer { store.requestStop(); store.closeAll() }
        func query(_ handle: String, sql: String = "SELECT 17 AS value", configuration: [String: Any] = [:]) throws -> [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: ["handle": handle, "path": ":memory:", "sql": sql, "configuration": configuration])
            return try #require(store.perform(operation: "sqlite.fetchAll", payloadJSON: String(decoding: data, as: UTF8.self)) as? [[String: Any]])
        }
        #expect(throws: (any Error).self) { try query("invalid", sql: "bad\0sql") }
        #expect(store.openDatabaseCount == 0)
        #expect((try query("first", sql: "PRAGMA busy_timeout", configuration: ["busyMode": "immediateError"])[0]["timeout"] as? NSNumber)?.intValue == 0)
        #expect((try query("second", sql: "PRAGMA busy_timeout", configuration: ["busyMode": 360])[0]["timeout"] as? NSNumber)?.intValue == 360_000)
        store.release(handles: ["first"])
        #expect(store.openDatabaseCount == 1)
        #expect((try query("second")[0]["value"] as? NSNumber)?.intValue == 17)
        store.requestStop()
        #expect(throws: (any Error).self) { try query("late") }
        #expect(store.openDatabaseCount == 1)
        store.closeAll()
        #expect(store.openDatabaseCount == 0)
    }
}
