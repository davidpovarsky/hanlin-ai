import CryptoKit
import Foundation

struct ChatCodeFencePayload: Sendable, Identifiable {
    let id = UUID()
    let html: String
    let css: String
    let width: Double
    let height: Double
    let fontSize: Double
    let dark: Bool
    var displayHTML: String? = nil
}

enum ChatCodeFenceDocument {
    struct Assets: Sendable {
        let script: String
        let css: String
        let identity: String
    }

    private struct Manifest: Decodable {
        struct File: Decodable { let name: String; let bytes: Int; let sha256: String }
        let schemaVersion: Int
        let files: [File]
    }

    static func loadAssets() throws -> Assets {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let directory = bundle.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        return try loadAssets(directory: directory)
    }

    static func loadAssets(directory: URL) throws -> Assets {
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

    static func workerHTML(assets: Assets) -> String {
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

    static func readonlyHTML(_ payload: ChatCodeFencePayload) -> String {
        """
        <!doctype html><html dir="ltr"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'; object-src 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=4, user-scalable=yes">
        <style>\(payload.css) :root {font-size:\(payload.fontSize)px; color-scheme:\(payload.dark ? "dark" : "light");}</style>
        </head><body>\(payload.html)</body></html>
        """
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
