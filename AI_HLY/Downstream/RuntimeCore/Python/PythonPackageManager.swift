import Foundation

struct PythonPackageDependency: Codable, Hashable, Sendable {
    let name: String
    let version: String
    let wheelFileName: String
    let sha256: String
}

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
    let resolvedDependencies: [PythonPackageDependency]?
    let sourceRequirement: String?
}

struct PythonPackagePreview: Sendable {
    let name: String
    let version: String
    let summary: String?
    let wheelFileName: String?
    let isPurePython: Bool
    let compatibilityExplanation: String
}

struct PythonPackageInstallProgress: Sendable {
    enum Phase: String, Sendable {
        case resolving
        case downloading
        case validating
        case installing
        case probing
        case committing
    }

    let phase: Phase
    let completedUnits: Int
    let totalUnits: Int
    let packageName: String
}

actor PythonPackageManager {
    private struct Distribution: Decodable, Sendable {
        let name: String
        let version: String
        let wheelFileName: String
        let sha256: String
        let requirements: [String]
        let summary: String
        let pure: Bool
        let origin: String
        let importName: String?
    }
    private struct Resolution: Decodable, Sendable {
        let root: Distribution
        let dependencies: [Distribution]
    }
    private struct PackagingLock: Decodable {
        struct Dependency: Decodable { let file: String; let sha256: String }
        let packages: [Dependency]
    }

    let maximumWheelSizeBytes: Int64?
    let pypiBaseURL: URL
    private let fileLayout: RuntimeFileLayout
    private let python: PythonRuntimeService
    private var records: [PythonPackageRecord]?
    private var installTail: Task<Void, Never>?
    private var registryURL: URL { fileLayout.registry.appending(path: "PythonPackages.json") }

    init(fileLayout: RuntimeFileLayout = .default, python: PythonRuntimeService,
         maximumWheelSizeBytes: Int64? = nil, pypiBaseURL: URL = URL(string: "https://pypi.org")!) {
        self.fileLayout = fileLayout
        self.python = python
        self.maximumWheelSizeBytes = maximumWheelSizeBytes
        self.pypiBaseURL = pypiBaseURL
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
        let resolution = try await packaging(name: name, version: version, destination: nil)
        return PythonPackagePreview(name: resolution.root.name, version: resolution.root.version,
            summary: resolution.root.summary, wheelFileName: resolution.root.wheelFileName,
            isPurePython: resolution.root.pure,
            compatibilityExplanation: resolution.root.pure
                ? "Resolved for the running interpreter using standard requirements, markers and wheel tags. Installation still requires a successful import probe."
                : "The wheel tags match the running interpreter. Native imports require a compatible extension packaged and signed with this app; extraction alone does not prove availability.")
    }

    func install(name: String, version: String? = nil, importName: String? = nil,
                 progress: @escaping @MainActor @Sendable (PythonPackageInstallProgress) -> Void = { _ in }) async throws -> PythonPackageRecord {
        let previous = installTail
        let task = Task {
            if let previous { await previous.value }
            try Task.checkCancellation()
            return try await performInstall(name: name, version: version, importName: importName, progress: progress)
        }
        installTail = Task { _ = await task.result }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performInstall(name: String, version: String?, importName: String?,
                                progress: @escaping @MainActor @Sendable (PythonPackageInstallProgress) -> Void) async throws -> PythonPackageRecord {
        try fileLayout.prepareIfNeeded()
        let operation = UUID().uuidString.lowercased()
        let staging = fileLayout.staging.appending(path: "python-\(operation)", directoryHint: .isDirectory)
        let candidate = fileLayout.pythonPackages.appending(path: ".000-candidate-\(operation)", directoryHint: .isDirectory)
        let backup = fileLayout.staging.appending(path: "python-backup-\(operation)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        // A backup is removed only after commit or successful restoration; never erase
        // the owner's sole previous installation when restoration itself fails.
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: candidate)
        }
        await progress(.init(phase: .resolving, completedUnits: 0, totalUnits: 1, packageName: name))
        let resolution = try await packaging(name: name, version: version, destination: staging)
        try Task.checkCancellation()
        let root = resolution.root
        let destination = try fileLayout.validatedDescendant(
            fileLayout.pythonPackages.appending(path: "\(root.name)-\(root.version)", directoryHint: .isDirectory),
            of: fileLayout.pythonPackages, allowRoot: false)
        let rootImport = importName ?? root.importName ?? root.name.replacingOccurrences(of: "-", with: "_")
        let size = try directorySize(staging)
        await progress(.init(phase: .installing, completedUnits: 1, totalUnits: 1, packageName: root.name))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: backup)
        }
        do {
            try FileManager.default.moveItem(at: staging, to: candidate)
            try Task.checkCancellation()
            await progress(.init(phase: .probing, completedUnits: 1, totalUnits: 1, packageName: root.name))
            let probe = try await importProbe(name: rootImport, directory: candidate, identifier: operation)
            guard probe.exitCode == 0, !probe.didTimeOut, !probe.wasCancelled else {
                throw RuntimeCoreError.runtimeFailure("The staged package failed its import probe. Full output is retained in job \(probe.executionID).\n\(probe.stderr)")
            }
            try Task.checkCancellation()
            await progress(.init(phase: .committing, completedUnits: 1, totalUnits: 1, packageName: root.name))
            try FileManager.default.moveItem(at: candidate, to: destination)
            let record = PythonPackageRecord(name: root.name, normalizedName: root.name, version: root.version,
                wheelFileName: root.wheelFileName, sha256: root.sha256, installedAt: .now, storageBytes: size,
                importName: rootImport, dependencyRequirements: root.requirements,
                resolvedDependencies: resolution.dependencies.map {
                    PythonPackageDependency(name: $0.name, version: $0.version, wheelFileName: $0.wheelFileName, sha256: $0.sha256)
                }, sourceRequirement: name)
            var current = try installed().filter { $0.normalizedName != root.name }
            current.append(record)
            do { try persist(current) }
            catch {
                try FileManager.default.removeItem(at: destination)
                throw error
            }
            try? FileManager.default.removeItem(at: backup)
            return record
        } catch {
            if FileManager.default.fileExists(atPath: backup.path), !FileManager.default.fileExists(atPath: destination.path) {
                do { try FileManager.default.moveItem(at: backup, to: destination) }
                catch let restorationError {
                    throw RuntimeCoreError.runtimeFailure("Installation failed: \(error.localizedDescription). The previous installation is retained at \(backup.path); restoration failed: \(restorationError.localizedDescription)")
                }
            }
            throw error
        }
    }

    private func packaging(name: String, version: String?, destination: URL?) async throws -> Resolution {
        let helper = try bundled("HanlinPythonPackaging.py")
        let lock = try JSONDecoder().decode(PackagingLock.self, from: Data(contentsOf: bundled("HanlinPythonPackaging.lock.json")))
        let resources = try lock.packages.map { ["path": try bundled($0.file).path, "sha256": $0.sha256] }
        let workspace = try fileLayout.workspace(client: .tools, identifier: "python-packaging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        var request: [String: Any] = ["requirement": name, "indexURL": pypiBaseURL.absoluteString,
            "workspace": workspace.path, "resources": resources]
        let nativeManifest = try JSONSerialization.jsonObject(with: Data(contentsOf: bundled("HanlinPythonNativeExtensions.json"))) as? [String: Any]
        request["nativeExtensions"] = try (nativeManifest?["extensions"] as? [[String: Any]] ?? []).map { entry in
            var resolved = entry
            guard let name = entry["wheel"] as? String else { throw RuntimeCoreError.invalidIdentifier }
            resolved["path"] = try bundled(name).path
            return resolved
        }
        if let version, !version.isEmpty { request["version"] = version }
        if let destination { request["destination"] = destination.path }
        if let maximumWheelSizeBytes { request["maximumArtifactBytes"] = maximumWheelSizeBytes }
        let requestJSON = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let requestLiteral = try pythonString(requestJSON)
        let helperLiteral = try pythonString(helper.path)
        let source = """
        import json, runpy
        _hanlin_packaging = runpy.run_path(\(helperLiteral))
        __hanlin_result__ = _hanlin_packaging['run'](json.loads(\(requestLiteral)))
        """
        let result = try await python.execute(RuntimeExecutionRequest(source: source, workspace: workspace))
        try Task.checkCancellation()
        if result.wasCancelled { throw CancellationError() }
        guard result.exitCode == 0, !result.didTimeOut, let value = result.value else {
            throw RuntimeCoreError.runtimeFailure("Package operation failed. Full output is retained in job \(result.executionID).\n\(result.stderr)")
        }
        return try JSONDecoder().decode(Resolution.self, from: JSONEncoder().encode(value))
    }

    private func bundled(_ name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil) else {
            throw RuntimeCoreError.runtimeFailure("Missing bundled Python packaging resource: \(name)")
        }
        return url
    }

    private func pythonString(_ value: String) throws -> String {
        // JSON's optional \/ escape is not a Python string escape.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func uninstall(_ record: PythonPackageRecord) async throws {
        let previous = installTail
        let task = Task {
            if let previous { await previous.value }
            try Task.checkCancellation()
            try performUninstall(record)
        }
        installTail = Task { _ = await task.result }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private func performUninstall(_ record: PythonPackageRecord) throws {
        let destination = try fileLayout.validatedDescendant(fileLayout.pythonPackages.appending(path: "\(record.normalizedName)-\(record.version)"), of: fileLayout.pythonPackages, allowRoot: false)
        let backup = fileLayout.staging.appending(path: "python-remove-\(UUID().uuidString)")
        let exists = FileManager.default.fileExists(atPath: destination.path)
        if exists { try FileManager.default.moveItem(at: destination, to: backup) }
        do { try persist(try installed().filter { $0.normalizedName != record.normalizedName }) }
        catch {
            if exists { try FileManager.default.moveItem(at: backup, to: destination) }
            throw error
        }
        if exists { try? FileManager.default.removeItem(at: backup) }
    }

    func probe(_ record: PythonPackageRecord) async throws -> RuntimeExecutionResult {
        try await importProbe(name: record.importName,
            directory: fileLayout.pythonPackages.appending(path: "\(record.normalizedName)-\(record.version)"), identifier: "installed")
    }

    private func importProbe(name: String, directory: URL, identifier: String) async throws -> RuntimeExecutionResult {
        guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$"#, options: .regularExpression) != nil else { throw RuntimeCoreError.invalidIdentifier }
        let workspace = try fileLayout.workspace(client: .tools, identifier: "python-package-probe-\(identifier)")
        let quoted = try pythonString(name)
        let path = try pythonString(directory.path)
        let source = """
        import importlib, sys, site
        from pathlib import Path
        _hanlin_name = \(quoted)
        _hanlin_target = Path(\(path)).resolve()
        _hanlin_root = _hanlin_name.split('.')[0]
        for _key in list(sys.modules):
            if _key == _hanlin_root or _key.startswith(_hanlin_root + '.'):
                sys.modules.pop(_key, None)
        sys.path.insert(0, str(_hanlin_target))
        try:
            site.addsitedir(str(_hanlin_target))
            importlib.invalidate_caches()
            _module = importlib.import_module(_hanlin_name)
            _origin = getattr(_module, '__file__', None)
            _paths = [_origin] if _origin else list(getattr(_module, '__path__', []))
            if not _paths or not all(Path(_p).resolve().is_relative_to(_hanlin_target) for _p in _paths):
                raise ImportError('Import probe resolved outside the candidate installation')
            print(getattr(_module, '__version__', 'import-ok'))
        finally:
            for _key in list(sys.modules):
                if _key == _hanlin_root or _key.startswith(_hanlin_root + '.'):
                    sys.modules.pop(_key, None)
        """
        return try await python.execute(RuntimeExecutionRequest(source: source, workspace: workspace))
    }

    private func directorySize(_ root: URL) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: keys)
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
