import Foundation
import Testing
@testable import HanlinMiniAppCore

#if canImport(SQLite3)
@Suite("SQLite SQL buffer lifetime")
struct HanlinSQLiteServiceTests {
    @Test("Dynamic UTF-8 multi-statement transactions retain SQLite tail bytes")
    func dynamicMultiStatementTransactions() throws {
        let service = HanlinSQLiteService(rootURL: FileManager.default.temporaryDirectory)
        _ = try service.open(handle: "buffer-lifetime", name: ":memory:")
        defer { service.closeAll() }
        try service.execute(handle: "buffer-lifetime", sql: "CREATE TABLE entries (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
        let nonce = UUID().uuidString
        for batch in 0..<4 {
            var sql = "BEGIN TRANSACTION;\n"
            for offset in 0..<32 {
                let index = batch * 32 + offset
                sql += "INSERT INTO entries VALUES (\(index), 'שלום-\(nonce)-\(index)');\n"
            }
            sql += "COMMIT;"
            try service.execute(handle: "buffer-lifetime", sql: sql)
        }
        let rows = try service.fetchAll(handle: "buffer-lifetime", sql: "SELECT id, text FROM entries ORDER BY id")
        #expect(rows.count == 128)
        for (index, row) in rows.enumerated() {
            #expect((row["id"] as? NSNumber)?.intValue == index)
            #expect(row["text"] as? String == "שלום-\(nonce)-\(index)")
        }
    }
}
#endif
