import Foundation

func errorRecord(_ value: Error, depth: Int = 0) -> [String: Any] {
    let error = value as NSError
    var result: [String: Any] = [
        "domain": error.domain,
        "code": error.code,
        "localizedDescription": error.localizedDescription,
    ]
    if let reason = error.localizedFailureReason { result["failureReason"] = reason }
    if let recovery = error.localizedRecoverySuggestion { result["recoverySuggestion"] = recovery }
    if depth < 3, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
        result["underlyingError"] = errorRecord(underlying, depth: depth + 1)
    }
    for key in [NSFilePathErrorKey, NSURLErrorKey] {
        if let value = error.userInfo[key] { result[key] = String(describing: value) }
    }
    return result
}

func writeJSON(_ value: [String: Any], to url: URL) throws {
    let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try bytes.write(to: url, options: .atomic)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let manager = FileManager.default
try manager.createDirectory(at: output, withIntermediateDirectories: true)
let root = manager.temporaryDirectory.appending(
    path: "hanlin-system-ui-bookmark-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
let selectedDirectory = root.appending(path: "Selected", directoryHint: .isDirectory)
let selectedFile = selectedDirectory.appending(path: "source note.txt", directoryHint: .notDirectory)
try manager.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
try Data("selected-content".utf8).write(to: selectedFile)

var rows: [[String: Any]] = []
for (urlKind, url) in [("raw", selectedFile), ("resolvedSymlinks", selectedFile.resolvingSymlinksInPath())] {
    for mode in ["originalSecurityScoped", "plainDiagnosticOnly"] {
        let creation: URL.BookmarkCreationOptions = mode == "originalSecurityScoped" ? [.withSecurityScope] : []
        let resolution: URL.BookmarkResolutionOptions = mode == "originalSecurityScoped" ? [.withSecurityScope, .withoutUI] : [.withoutUI]
        var row: [String: Any] = [
            "urlKind": urlKind, "mode": mode,
            "url": url.absoluteString, "path": url.path(percentEncoded: false),
            "fileExistsBefore": manager.fileExists(atPath: url.path(percentEncoded: false)),
            "creationOptionsRawValue": creation.rawValue,
            "resolutionOptionsRawValue": resolution.rawValue,
        ]
        let sourceScope = url.startAccessingSecurityScopedResource()
        row["inputSecurityScopeAcquired"] = sourceScope
        do {
            row["inputReadBytes"] = try Data(contentsOf: url).count
            let data = try url.bookmarkData(options: creation, includingResourceValuesForKeys: nil, relativeTo: nil)
            row["creationSucceeded"] = true
            row["bookmarkByteCount"] = data.count
            let retainedBookmark = output.appending(path: "\(urlKind)-\(mode).bookmark")
            try data.write(to: retainedBookmark, options: .atomic)
            row["retainedBookmarkPath"] = retainedBookmark.path(percentEncoded: false)
            var stale = false
            do {
                let restored = try URL(resolvingBookmarkData: data, options: resolution,
                                       relativeTo: nil, bookmarkDataIsStale: &stale)
                row["resolutionSucceeded"] = true
                row["stale"] = stale
                row["resolvedURL"] = restored.absoluteString
                row["resolvedPath"] = restored.path(percentEncoded: false)
                row["resolvedFileExists"] = manager.fileExists(atPath: restored.path(percentEncoded: false))
                let restoredScope = restored.startAccessingSecurityScopedResource()
                row["resolvedSecurityScopeAcquired"] = restoredScope
                do {
                    let bytes = try Data(contentsOf: restored)
                    row["resolvedReadBytes"] = bytes.count
                    row["resolvedContentEqualsOriginal"] = bytes == Data("selected-content".utf8)
                } catch { row["resolvedReadError"] = errorRecord(error) }
                if restoredScope { restored.stopAccessingSecurityScopedResource() }
            } catch {
                row["resolutionSucceeded"] = false
                row["resolutionError"] = errorRecord(error)
            }
        } catch {
            row["creationSucceeded"] = false
            row["creationError"] = errorRecord(error)
        }
        if sourceScope { url.stopAccessingSecurityScopedResource() }
        rows.append(row)
    }
}

let record: [String: Any] = [
    "status": "FOUNDATION_BOOKMARK_DIAGNOSTIC_COMPLETED",
    "sourceContext": "bd4c83baff2ed049a5a98aa0e0608f56f5a5cbcb",
    "processID": ProcessInfo.processInfo.processIdentifier,
    "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    "temporaryRoot": root.path(percentEncoded: false),
    "selectedFile": selectedFile.path(percentEncoded: false),
    "fixtureBytes": Data("selected-content".utf8).count,
    "attempts": rows,
    "boundary": "Foundation-only native diagnostic on an owned temporary fixture. Plain bookmarks are a diagnostic comparison only; no production change, entitlement change or test gate credit.",
]
try writeJSON(record, to: output.appending(path: "foundation-bookmark-result.json"))

var cleanup: [String: Any] = ["resultsRetainedBeforeCleanup": true, "temporaryRoot": root.path(percentEncoded: false)]
do {
    try manager.removeItem(at: root)
    cleanup["removed"] = !manager.fileExists(atPath: root.path(percentEncoded: false))
} catch { cleanup["cleanupError"] = errorRecord(error) }
try writeJSON(cleanup, to: output.appending(path: "foundation-bookmark-cleanup.json"))
let printed = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
FileHandle.standardOutput.write(printed)
FileHandle.standardOutput.write(Data("\n".utf8))
