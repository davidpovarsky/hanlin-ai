import CryptoKit
import Foundation

/// Hash actual installed code once per process, off the main actor. Build numbers or
/// filenames alone cannot stand in for engine identity when reusing an execution receipt.
actor SkillRuntimeInstalledIdentity {
    static let shared = SkillRuntimeInstalledIdentity()
    private var cached: String?

    func fingerprint() throws -> String {
        if let cached { return cached }
        guard let executable = Bundle.main.executableURL else { throw RuntimeCoreError.invalidPath }
        var urls = [executable]
        if let directory = Bundle.main.privateFrameworksURL {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where url.pathExtension == "framework" {
                guard let binary = Bundle(url: url)?.executableURL else { throw RuntimeCoreError.invalidPath }
                urls.append(binary)
            }
        }
        if let host = Bundle.main.url(forResource: "RuntimeHostResources", withExtension: "zip") { urls.append(host) }
        var hash = SHA256()
        hash.update(data: Data(ProcessInfo.processInfo.operatingSystemVersionString.utf8))
        for url in urls.sorted(by: { $0.path < $1.path }) {
            hash.update(data: Data(url.lastPathComponent.utf8))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        }
        let value = hash.finalize().map { String(format: "%02x", $0) }.joined()
        cached = value
        return value
    }
}
