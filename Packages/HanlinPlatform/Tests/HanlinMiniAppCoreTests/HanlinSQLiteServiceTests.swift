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

    @Test("Default SQLite resources preserve live handles, complete rows, parameters and large SQL")
    func actualResourcesBeyondLegacyBudgets() throws {
        let service = HanlinSQLiteService(rootURL: FileManager.default.temporaryDirectory)
        defer { service.closeAll() }
        for index in 0..<24 {
            let handle = "live-\(index)"
            _ = try service.open(handle: handle, name: ":memory:")
            try service.execute(handle: handle, sql: "CREATE TEMP TABLE state(value INTEGER); INSERT INTO state VALUES (?)", arguments: [index])
        }
        #expect(service.openDatabaseCount == 24)
        for index in 0..<24 {
            let rows = try service.fetchAll(handle: "live-\(index)", sql: "SELECT value FROM state")
            #expect((rows.first?["value"] as? NSNumber)?.intValue == index)
        }
        let rows = try service.fetchAll(handle: "live-0", sql: "WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<10501) SELECT x FROM n")
        #expect(rows.count == 10_502)
        #expect((rows.last?["x"] as? NSNumber)?.intValue == 10_501)
        let values = (0..<1_500).map { $0 }
        try service.execute(handle: "live-0", sql: "CREATE TABLE parameters(value INTEGER); INSERT INTO parameters VALUES " + values.map { _ in "(?)" }.joined(separator: ","), arguments: values)
        let total = try service.fetchAll(handle: "live-0", sql: "SELECT count(*) AS count, sum(value) AS total FROM parameters")
        #expect((total[0]["count"] as? NSNumber)?.intValue == 1_500)
        #expect((total[0]["total"] as? NSNumber)?.intValue == values.reduce(0, +))
        let text = "שלום-" + String(repeating: "z", count: 1_048_600)
        let large = try service.fetchAll(handle: "live-0", sql: "SELECT '\(text)' AS text")
        #expect(large[0]["text"] as? String == text)
    }

    @Test("SQLite preserves NUL text, empty binary, NULL, full bytes and numeric storage classes")
    func actualStorageClassesAndBytes() throws {
        let service = HanlinSQLiteService(rootURL: FileManager.default.temporaryDirectory)
        defer { service.closeAll() }
        _ = try service.open(handle: "bytes", name: ":memory:")
        let text = "שלום\0tail"
        let binary = Data((0..<1_024).map { UInt8($0 % 256) })
        let rows = try service.fetchAll(handle: "bytes", sql: "SELECT ? AS text, ? AS empty, ? AS binary, ? AS missing, ? AS integer, ? AS real, typeof(?) AS emptyType, typeof(?) AS integerType, typeof(?) AS realType", arguments: [text, Data(), binary, NSNull(), NSNumber(value: Int64.max), NSNumber(value: 1e30), Data(), NSNumber(value: Int64.max), NSNumber(value: 1e30)])
        let row = try #require(rows.first)
        #expect(row["text"] as? String == text)
        #expect((row["empty"] as? [String: String])?["__hanlinSQLiteData"] == "")
        #expect((row["binary"] as? [String: String])?["__hanlinSQLiteData"] == binary.base64EncodedString())
        #expect(row["missing"] is NSNull)
        #expect((row["integer"] as? NSNumber)?.int64Value == Int64.max)
        #expect((row["real"] as? NSNumber)?.doubleValue == 1e30)
        #expect(row["emptyType"] as? String == "blob")
        #expect(row["integerType"] as? String == "integer")
        #expect(row["realType"] as? String == "real")
        let booleansAndReal = try service.fetchAll(handle: "bytes", sql: "SELECT ? AS flag, typeof(?) AS realType", arguments: [true, NSNumber(value: 1.0)])
        #expect((booleansAndReal[0]["flag"] as? NSNumber)?.intValue == 1)
        #expect(booleansAndReal[0]["realType"] as? String == "real")
        #expect(throws: (any Error).self) {
            try service.fetchAll(handle: "bytes", sql: "SELECT ?", arguments: [NSNumber(value: UInt64.max)])
        }
    }

    @Test("Explicit budgets reject work and terminal stop prevents delayed queries or reopening")
    func explicitBudgetsAndOwnerStop() throws {
        let root = FileManager.default.temporaryDirectory
        let zero = HanlinSQLiteService(rootURL: root, resourceLimits: .init(maximumOpenDatabases: 0))
        #expect(throws: HanlinSQLiteServiceError.tooManyDatabases) { try zero.open(handle: "zero", name: ":memory:") }
        let service = HanlinSQLiteService(rootURL: root, resourceLimits: .init(maximumFetchRows: 1, maximumBindParameters: 1, maximumStatementBytes: 128))
        defer { service.closeAll() }
        _ = try service.open(handle: "one", name: ":memory:")
        #expect(throws: HanlinSQLiteServiceError.tooManyRows) { try service.fetchAll(handle: "one", sql: "SELECT 1 UNION ALL SELECT 2") }
        #expect(throws: HanlinSQLiteServiceError.tooManyParameters) { try service.fetchAll(handle: "one", sql: "SELECT ?, ?", arguments: [1, 2]) }
        #expect(throws: HanlinSQLiteServiceError.statementTooLarge) { try service.execute(handle: "one", sql: "SELECT 1;--" + String(repeating: "x", count: 128)) }
        service.requestStop()
        #expect(throws: (any Error).self) { try service.fetchAll(handle: "one", sql: "SELECT 1") }
        #expect(throws: (any Error).self) { try service.open(handle: "late", name: ":memory:") }
        #expect(service.openDatabaseCount == 1)
        service.closeAll()
        #expect(service.openDatabaseCount == 0)
    }
}
#endif
