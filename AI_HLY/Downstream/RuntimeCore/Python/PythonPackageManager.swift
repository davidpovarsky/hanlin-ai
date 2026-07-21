import CryptoKit
import Foundation
import ZIPFoundation

struct PythonPackageRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String { normalizedName }
    let name: String
    let normalizedName: String
    let version: String
    let wheelFileName: String
    let sha256: String
    let installedAt: Date
    let storageBytes: Int64
    let importName: String
    let dependencyRequirements: [String]
}

struct PythonPackagePreview: Sendable {
    let name: String
    let version: String
    let summary: String?
    let wheelFileName: String?
    let isPurePython: Bool
    let compatibilityExplanation: String
}

actor PythonPackageManager {
    private struct PyPIProject: Decodable {
        struct Info: Decodable { let name: String; let version: String; let summary: String?; let requiresDist: [String]? }
        struct Distribution: Decodable {
            struct Digests: Decodable { let sha256: String }
            let filename: String
            let url: URL
            let packagetype: String
            let digests: Digests
            let size: Int64
        }
        let info: Info
        let releases: [String: [Distribution]]
    }

    private let fileLayout: RuntimeFileLayout
    private let python: PythonRuntimeService
    private var records: [PythonPackageRecord]?
    private var registryURL: URL { fileLayout.registry.appending(path: "PythonPackages.json") }

    init(fileLayout: RuntimeFileLayout = .default, python: PythonRuntimeService) {
        self.fileLayout = fileLayout
        self.python = python
    }

    func installed() throws -> [PythonPackageRecord] {
        if let records { return records }
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: registryURL.path) else { records = []; return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([PythonPackageRecord].self, from: Data(contentsOf: registryURL))
        records = decoded
        return decoded
    }

    func preview(name: String, version: String? = nil) async throws -> PythonPackagePreview {
        let project = try await project(name: name)
        let selected = version ?? project.info.version
        let wheel = project.releases[selected]?.first(where: { isUniversalWheel($0) })
        return PythonPackagePreview(
            name: project.info.name,
            version: selected,
            summary: project.info.summary,
            wheelFileName: wheel?.filename,
            isPurePython: wheel != nil,
            compatibilityExplanation: wheel == nil
                ? "No universal pure-Python wheel is published for this version. Source builds and dynamically loaded native extensions are unavailable on iOS."
                : "A universal pure-Python wheel is available and can be installed without running build or lifecycle scripts."
        )
    }

    func install(name: String, version: String? = nil, importName: String? = nil) async throws -> PythonPackageRecord {
        let project = try await project(name: name)
        let selectedVersion = version ?? project.info.version
        guard let distribution = project.releases[selectedVersion]?.first(where: { isUniversalWheel($0) }) else {
            throw RuntimeCoreError.runtimeFailure("This release has no universal pure-Python wheel. Source builds and native wheels cannot be installed dynamically on iOS.")
        }
        guard distribution.size <= 100 * 1_024 * 1_024 else { throw RuntimeCoreError.runtimeFailure("The wheel exceeds the 100 MB package limit.") }
        let (temporaryURL, response) = try await URLSession.shared.download(from: distribution.url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RuntimeCoreError.runtimeFailure("PyPI wheel download failed.") }
        let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == distribution.digests.sha256.lowercased() else { throw RuntimeCoreError.runtimeFailure("The downloaded wheel failed SHA-256 verification.") }

        try fileLayout.prepareIfNeeded()
        let normalized = normalize(project.info.name)
        let operation = UUID().uuidString.lowercased()
        let staging = fileLayout.staging.appending(path: "python-\(operation)", directoryHint: .isDirectory)
        let wheelURL = fileLayout.staging.appending(path: "\(operation).whl")
        let destination = fileLayout.pythonPackages.appending(path: "\(normalized)-\(selectedVersion)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try data.write(to: wheelURL, options: [.atomic, .completeFileProtection])
        defer { try? FileManager.default.removeItem(at: wheelURL); try? FileManager.default.removeItem(at: staging) }
        let archive = try Archive(url: wheelURL, accessMode: .read)
        for entry in archive {
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), entry.type != .symlink else {
                throw RuntimeCoreError.symbolicLinkRejected
            }
            let lower = path.lowercased()
            guard !lower.hasSuffix(".so"), !lower.hasSuffix(".dylib"), !lower.hasSuffix(".a") else {
                throw RuntimeCoreError.runtimeFailure("The wheel contains a native binary and cannot be installed dynamically on iOS.")
            }
        }
        try FileManager.default.unzipItem(at: wheelURL, to: staging)
        guard try FileManager.default.contentsOfDirectory(atPath: staging.path).contains(where: { $0.hasSuffix(".dist-info") }) else {
            throw RuntimeCoreError.runtimeFailure("The wheel does not contain valid dist-info metadata.")
        }
        let size = try directorySize(staging)
        let backup = fileLayout.staging.appending(path: "python-backup-\(operation)", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.moveItem(at: destination, to: backup) }
        do {
            try FileManager.default.moveItem(at: staging, to: destination)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            if FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.moveItem(at: backup, to: destination) }
            throw error
        }
        let record = PythonPackageRecord(
            name: project.info.name,
            normalizedName: normalized,
            version: selectedVersion,
            wheelFileName: distribution.filename,
            sha256: digest,
            installedAt: .now,
            storageBytes: size,
            importName: importName ?? normalized.replacingOccurrences(of: "-", with: "_"),
            dependencyRequirements: project.info.requiresDist ?? []
        )
        var current = try installed().filter { $0.normalizedName != normalized }
        current.append(record)
        try persist(current)
        return record
    }

    func uninstall(_ record: PythonPackageRecord) throws {
        let destination = fileLayout.pythonPackages.appending(path: "\(record.normalizedName)-\(record.version)", directoryHint: .isDirectory)
        let validated = try fileLayout.validatedDescendant(destination, of: fileLayout.pythonPackages, allowRoot: false)
        if FileManager.default.fileExists(atPath: validated.path) { try FileManager.default.removeItem(at: validated) }
        try persist(try installed().filter { $0.normalizedName != record.normalizedName })
    }

    func probe(_ record: PythonPackageRecord) async throws -> RuntimeExecutionResult {
        let workspace = try fileLayout.workspace(client: .tools, identifier: "python-package-probe")
        return try await python.execute(RuntimeExecutionRequest(source: "import \(record.importName)\nprint(getattr(\(record.importName), '__version__', 'import-ok'))", workspace: workspace))
    }

    private func project(name: String) async throws -> PyPIProject {
        let normalized = normalize(name)
        guard normalized.range(of: "^[a-z0-9][a-z0-9._-]{0,127}$", options: .regularExpression) != nil,
              let url = URL(string: "https://pypi.org/pypi/\(normalized)/json") else { throw RuntimeCoreError.invalidIdentifier }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw RuntimeCoreError.runtimeFailure("The package was not found on PyPI.") }
        return try JSONDecoder().decode(PyPIProject.self, from: data)
    }

    private func isUniversalWheel(_ distribution: PyPIProject.Distribution) -> Bool {
        distribution.packagetype == "bdist_wheel" && distribution.filename.lowercased().hasSuffix("-none-any.whl")
    }

    private func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[-_.]+", with: "-", options: .regularExpression)
    }

    private func directorySize(_ root: URL) throws -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }

    private func persist(_ value: [PythonPackageRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: registryURL, options: [.atomic, .completeFileProtection])
        records = value
    }
}
