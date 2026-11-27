#if canImport(CryptoKit)
import CryptoKit
import Foundation

public struct ChatCodeFencePayload: Sendable, Identifiable {
    public let id = UUID()
    public let html: String
    public let css: String
    public let width: Double
    public let height: Double
    public let fontSize: Double
    public let dark: Bool
    public var displayHTML: String? = nil
    // Value copies share this immutable ownership token. Cache eviction, view
    // remount, zoom or caller cancellation cannot release another live copy.
    private var retention: ChatCodeFencePayloadRetention.Lease? = nil

    public init(html: String, css: String, width: Double, height: Double, fontSize: Double,
                dark: Bool, displayHTML: String? = nil) {
        self.html = html
        self.css = css
        self.width = width
        self.height = height
        self.fontSize = fontSize
        self.dark = dark
        self.displayHTML = displayHTML
    }

    var retainedUTF8Bytes: Int { html.utf8.count + css.utf8.count + (displayHTML?.utf8.count ?? 0) }

    mutating func retain(in budget: ChatCodeFencePayloadRetention) -> Bool {
        if let retention { return retention.owner === budget && retention.bytes == retainedUTF8Bytes }
        guard let lease = budget.acquire(bytes: retainedUTF8Bytes) else { return false }
        retention = lease
        return true
    }
}

public enum ChatCodeFenceDocument {
    public struct Assets: Sendable {
        public let script: String
        public let css: String
        public let identity: String
    }

    private struct Manifest: Decodable {
        struct File: Decodable { let name: String; let bytes: Int; let sha256: String }
        let schemaVersion: Int
        let files: [File]
    }

    public static func loadAssets() throws -> Assets {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let directory = bundle.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        return try loadAssets(directory: directory)
    }

    public static func loadAssets(directory: URL) throws -> Assets {
        let manifestData = try Data(contentsOf: directory.appending(path: "HanlinCodeFenceAssets.json"))
        guard manifestData.count <= 65_536 else { throw CocoaError(.fileReadTooLarge) }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        func asset(_ name: String, maximum: Int) throws -> String {
            let matches = manifest.files.filter { $0.name == name }
            guard matches.count == 1, let entry = matches.first, entry.bytes >= 0, entry.bytes <= maximum else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = try Data(contentsOf: directory.appending(path: name), options: .mappedIfSafe)
            guard data.count == entry.bytes, digest(data) == entry.sha256,
                  let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            return text
        }
        return try Assets(script: asset("HanlinCodeFenceRenderer.js", maximum: 8 * 1024 * 1024),
                          css: asset("HanlinCodeFenceRenderer.css", maximum: 256 * 1024), identity: digest(manifestData))
    }

    public static func workerHTML(assets: Assets) -> String {
        let nonce = UUID().uuidString
        let script = assets.script.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive)
        return """
        <!doctype html><html dir="ltr"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(assets.css)</style></head><body><div id="render-host"></div>
        <script nonce="\(nonce)">\(script)</script></body></html>
        """
    }

    public static func readonlyHTML(_ payload: ChatCodeFencePayload) -> String {
        """
        <!doctype html><html dir="ltr"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=4, user-scalable=yes">
        <style>\(payload.css) :root {font-size:\(payload.fontSize)px; color-scheme:\(payload.dark ? "dark" : "light");}</style>
        </head><body>\(payload.html)</body></html>
        """
    }

    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

#endif
