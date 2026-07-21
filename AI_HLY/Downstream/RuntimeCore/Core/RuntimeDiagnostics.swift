import Foundation

actor RuntimeDiagnostics {
    private let manifestURL: URL?
    private var cachedManifest: RuntimeManifest?

    init(manifestURL: URL? = Bundle.main.url(forResource: "RuntimeManifest", withExtension: "json")) {
        self.manifestURL = manifestURL
    }

    func manifest() throws -> RuntimeManifest {
        if let cachedManifest { return cachedManifest }
        guard let manifestURL else { throw RuntimeCoreError.invalidDependencyManifest }
        let decoded = try JSONDecoder().decode(RuntimeManifest.self, from: Data(contentsOf: manifestURL))
        guard decoded.schemaVersion == 1, decoded.runtimeBundle.formatVersion == 1 else {
            throw RuntimeCoreError.invalidDependencyManifest
        }
        cachedManifest = decoded
        return decoded
    }

    func record(for id: String) throws -> RuntimeManifest.RuntimeRecord? {
        try manifest().runtimes.first { $0.id == id }
    }
}
