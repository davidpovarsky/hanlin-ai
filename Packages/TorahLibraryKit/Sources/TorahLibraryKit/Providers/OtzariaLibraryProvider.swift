import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// Real local Otzaria Torah library provider querying the on-device `seforim.db`
/// SQLite database and shared iTorah App Group container (`group.com.davidpovarsky.itorah`).
public final class OtzariaLibraryProvider: TorahLibraryProvider, TorahLibrarySearchEngine, @unchecked Sendable {
    public let providerID = "otzaria"
    public let displayName = "Otzaria Local Library"

    public let databaseURL: URL?
    private let lock = NSLock()

    #if canImport(SQLite3)
    private var dbHandle: OpaquePointer?
    #endif

    public static func fileSystemPath(for url: URL) -> String {
        var p = url.path
        if p.hasPrefix("/") && p.count > 2 {
            let secondChar = p[p.index(after: p.startIndex)]
            if secondChar == ":" {
                p = String(p.dropFirst())
            }
        }
        return p
    }

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL ?? Self.resolveDefaultDatabaseURL()
        #if canImport(SQLite3)
        if let url = self.databaseURL {
            let fsPath = Self.fileSystemPath(for: url)
            if FileManager.default.fileExists(atPath: fsPath) {
                var db: OpaquePointer?
                let status = sqlite3_open_v2(fsPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
                if status == SQLITE_OK {
                    self.dbHandle = db
                }
            }
        }
        #endif
    }

    deinit {
        #if canImport(SQLite3)
        lock.lock()
        if let db = dbHandle {
            sqlite3_close(db)
        }
        lock.unlock()
        #endif
    }

    public var isAvailable: Bool {
        guard let url = databaseURL else { return false }
        return FileManager.default.fileExists(atPath: Self.fileSystemPath(for: url))
    }

    public static func resolveDefaultDatabaseURL() -> URL? {
        // 1. Environment variable override
        if let envPath = ProcessInfo.processInfo.environment["OTZARIA_DATABASE_PATH"],
           !envPath.isEmpty,
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath)
        }

        // 2. Shared App Group container: group.com.davidpovarsky.itorah
        #if os(iOS)
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.davidpovarsky.itorah"
        ) {
            let candidate = containerURL.appendingPathComponent("Otzaria/seforim.db")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        #endif

        // 3. Application Support directory
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let candidate = appSupport.appendingPathComponent("Otzaria/seforim.db")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let directCandidate = appSupport.appendingPathComponent("seforim.db")
            if FileManager.default.fileExists(atPath: directCandidate.path) {
                return directCandidate
            }
        }

        return nil
    }

    // MARK: - Search Engine Conformance

    public func search(query: String, limit: Int = 10) async throws -> [TorahSearchHit] {
        try await search(anchors: [query], limit: limit)
    }

    public func search(anchors: [String], limit: Int = 10) async throws -> [TorahSearchHit] {
        guard isAvailable else {
            return []
        }

        #if canImport(SQLite3)
        return performNativeSQLiteSearch(anchors: anchors, limit: limit)
        #else
        var results: [TorahSearchHit] = []
        var seenKeys = Set<String>()
        for anchor in anchors {
            let cleanAnchor = HebrewTextNormalizer.stripNiqqud(from: anchor).trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanAnchor.count >= 3 else { continue }

            let sql = """
            SELECT l.bookId, b.name as bookTitle, l.lineIndex, l.content, l.heRef
            FROM line l
            JOIN book b ON l.bookId = b.id
            WHERE l.content LIKE ?
            LIMIT ?;
            """
            let rows = executeSQLiteQuery(sql: sql, args: ["%\(cleanAnchor)%", "\(limit)"])
            for row in rows {
                guard let bookId = row["bookId"] as? Int,
                      let bookTitle = row["bookTitle"] as? String,
                      let lineIndex = row["lineIndex"] as? Int,
                      let content = row["content"] as? String else { continue }
                let heRef = (row["heRef"] as? String) ?? "\(bookTitle) line \(lineIndex)"
                let locator = SourceLocator(
                    providerID: providerID,
                    corpusID: "canonical",
                    workKey: "book:\(bookId)",
                    positionKind: .line,
                    positionValue: "\(lineIndex)"
                )
                if !seenKeys.contains(locator.persistenceKey) {
                    seenKeys.insert(locator.persistenceKey)
                    results.append(
                        TorahSearchHit(
                            locator: locator,
                            workTitle: heRef.isEmpty ? bookTitle : "\(bookTitle) (\(heRef))",
                            textSnippet: content,
                            fullText: content,
                            providerScore: 1.0
                        )
                    )
                }
                if results.count >= limit { break }
            }
            if results.count >= limit { break }
        }
        #endif

        return results
    }

    public func fetchSection(locator: SourceLocator) async throws -> String? {
        let sec = try await getSection(locator: locator)
        return sec?.primaryText
    }

    public func getSection(locator: SourceLocator) async throws -> StudySource? {
        guard isAvailable else { return nil }

        #if canImport(SQLite3)
        return performNativeSQLiteGetSection(locator: locator)
        #else
        let bookId: Int
        if locator.workKey.hasPrefix("book:"),
           let parsed = Int(locator.workKey.dropFirst("book:".count)) {
            bookId = parsed
        } else if let parsed = Int(locator.workKey) {
            bookId = parsed
        } else {
            bookId = 1
        }
        let lineIndex = Int(locator.positionValue) ?? 0

        let sql = """
        SELECT l.content, l.heRef, b.name as bookTitle
        FROM line l
        JOIN book b ON l.bookId = b.id
        WHERE l.bookId = ? AND l.lineIndex = ?
        LIMIT 1;
        """
        let rows = executeSQLiteQuery(sql: sql, args: ["\(bookId)", "\(lineIndex)"])
        if let row = rows.first,
           let content = row["content"] as? String {
            let heRef = row["heRef"] as? String
            let bookTitle = (row["bookTitle"] as? String) ?? locator.workKey
            return StudySource(
                locator: locator,
                primaryText: content,
                contextBefore: nil,
                contextAfter: nil,
                links: [],
                topics: [],
                versionMetadata: VersionMetadata(versionTitle: bookTitle, versionTitleInHebrew: heRef, language: "he"),
                licenseMetadata: LicenseMetadata(licenseName: "Public Domain / CC", copyrightNotice: nil),
                provenance: "otzaria_local_sqlite"
            )
        }
        #endif

        return nil
    }

    public func getLinks(locator: SourceLocator, type: String? = nil) async throws -> [TorahLinkedSource] {
        // Otzaria links if table exists
        return []
    }

    public func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic] {
        // No fake topics: return empty when local SQLite doesn't have a topics table
        return []
    }

    #if canImport(SQLite3)
    private func performNativeSQLiteSearch(anchors: [String], limit: Int) -> [TorahSearchHit] {
        lock.lock()
        defer { lock.unlock() }

        guard let db = dbHandle else { return [] }
        var results: [TorahSearchHit] = []
        var seenKeys = Set<String>()

        for anchor in anchors {
            let cleanAnchor = HebrewTextNormalizer.stripNiqqud(from: anchor).trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanAnchor.count >= 3 else { continue }

            let sql = """
            SELECT l.bookId, b.name, l.lineIndex, l.content, l.heRef
            FROM line l
            JOIN book b ON l.bookId = b.id
            WHERE l.content LIKE ?
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                let pattern = "%\(cleanAnchor)%"
                sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 2, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let bookId = Int(sqlite3_column_int(stmt, 0))
                    let bookTitle = String(cString: sqlite3_column_text(stmt, 1))
                    let lineIndex = Int(sqlite3_column_int(stmt, 2))
                    let content = sqlite3_column_text(stmt, 3) != nil ? String(cString: sqlite3_column_text(stmt, 3)) : ""
                    let heRef = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : "\(bookTitle) line \(lineIndex)"

                    let locator = SourceLocator(
                        providerID: providerID,
                        corpusID: "canonical",
                        workKey: "book:\(bookId)",
                        positionKind: .line,
                        positionValue: "\(lineIndex)"
                    )

                    if !seenKeys.contains(locator.persistenceKey) {
                        seenKeys.insert(locator.persistenceKey)
                        results.append(
                            TorahSearchHit(
                                locator: locator,
                                workTitle: heRef.isEmpty ? bookTitle : "\(bookTitle) (\(heRef))",
                                textSnippet: content,
                                fullText: content,
                                providerScore: 1.0
                            )
                        )
                    }

                    if results.count >= limit { break }
                }
                sqlite3_finalize(stmt)
            }
            if results.count >= limit { break }
        }
        return results
    }

    private func performNativeSQLiteGetSection(locator: SourceLocator) -> StudySource? {
        lock.lock()
        defer { lock.unlock() }

        guard let db = dbHandle else { return nil }

        let bookId: Int
        if locator.workKey.hasPrefix("book:"),
           let parsed = Int(locator.workKey.dropFirst("book:".count)) {
            bookId = parsed
        } else if let parsed = Int(locator.workKey) {
            bookId = parsed
        } else {
            bookId = resolveBookId(title: locator.workKey, db: db) ?? 1
        }

        let lineIndex = Int(locator.positionValue) ?? 0

        let sql = """
        SELECT l.content, l.heRef, b.name
        FROM line l
        JOIN book b ON l.bookId = b.id
        WHERE l.bookId = ? AND l.lineIndex = ?
        LIMIT 1;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(bookId))
            sqlite3_bind_int(stmt, 2, Int32(lineIndex))

            if sqlite3_step(stmt) == SQLITE_ROW {
                let content = sqlite3_column_text(stmt, 0) != nil ? String(cString: sqlite3_column_text(stmt, 0)) : ""
                let heRef = sqlite3_column_text(stmt, 1) != nil ? String(cString: sqlite3_column_text(stmt, 1)) : nil
                let bookTitle = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : locator.workKey
                sqlite3_finalize(stmt)

                return StudySource(
                    locator: locator,
                    primaryText: content,
                    contextBefore: nil,
                    contextAfter: nil,
                    links: [],
                    topics: [],
                    versionMetadata: VersionMetadata(versionTitle: bookTitle, versionTitleInHebrew: heRef, language: "he"),
                    licenseMetadata: LicenseMetadata(licenseName: "Public Domain / CC", copyrightNotice: nil),
                    provenance: "otzaria_local_sqlite"
                )
            }
            sqlite3_finalize(stmt)
        }
        return nil
    }

    private func resolveBookId(title: String, db: OpaquePointer) -> Int? {
        let sql = "SELECT id FROM book WHERE name = ? OR title = ? LIMIT 1;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (title as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                sqlite3_finalize(stmt)
                return id
            }
            sqlite3_finalize(stmt)
        }
        return nil
    }
    #else
    private func executeSQLiteQuery(sql: String, args: [String]) -> [[String: Any]] {
        guard let url = databaseURL else { return [] }
        let fsPath = Self.fileSystemPath(for: url)

        let queryPayload: [String: Any] = [
            "db": fsPath,
            "sql": sql,
            "args": args
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: queryPayload) else { return [] }

        let pyScript = "import sqlite3, json, sys; sys.stdin.reconfigure(encoding='utf-8'); sys.stdout.reconfigure(encoding='utf-8'); req = json.loads(sys.stdin.read()); conn = sqlite3.connect(req['db']); cur = conn.cursor(); cur.execute(req['sql'], tuple(req['args'])); cols = [d[0] for d in cur.description] if cur.description else []; rows = [dict(zip(cols, r)) for r in cur.fetchall()]; print(json.dumps(rows, ensure_ascii=False))"

        let pythonPath: String = {
            let candidates = [
                "C:\\Users\\DAVID\\AppData\\Local\\Programs\\Python\\Python312\\python.exe",
                "C:\\Users\\DAVID\\AppData\\Local\\Programs\\Python\\Python310\\python.exe"
            ]
            for c in candidates {
                if FileManager.default.fileExists(atPath: c) { return c }
            }
            return "C:\\Windows\\py.exe"
        }()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: pythonPath)
        p.arguments = ["-c", pyScript]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUTF8"] = "1"
        p.environment = env

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        p.standardInput = inputPipe
        p.standardOutput = outputPipe
        do {
            try p.run()
            inputPipe.fileHandleForWriting.write(jsonData)
            try? inputPipe.fileHandleForWriting.close()
            p.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return array
            }
        } catch {
            return []
        }
        return []
    }
    #endif
}
