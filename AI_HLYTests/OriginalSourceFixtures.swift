import Foundation

/// Source snapshots are produced from the current checkout by this test target's build phase.
/// A simulator test must not depend on the compiler host's absolute #filePath being readable.
enum OriginalSourceFixtures {
    static func root() throws -> URL {
        let tests = Bundle(for: OriginalSourceFixtureBundleMarker.self)
        guard let root = tests.url(forResource: "OriginalSourceFixtures", withExtension: "bundle"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("manifest.json").path)
        else {
            throw NSError(
                domain: "HanlinOriginalSourceFixtures", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "The current-build original source fixture bundle is required; source audits cannot be skipped."]
            )
        }
        return root
    }
}

private final class OriginalSourceFixtureBundleMarker: NSObject {}
