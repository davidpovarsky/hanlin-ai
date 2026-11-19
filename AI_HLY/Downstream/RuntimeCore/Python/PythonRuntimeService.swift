import Foundation
import CryptoKit


/// An observed original-CPython resolution is a module-availability fact, not an
/// import test or a successful Skill execution.
struct PythonSkillModuleFact: Sendable {
    let name: String
    let status: String
    let resolvedPath: String?
    let identity: String
    let observedAt: Date
    let executionID: UUID
    let engineVersion: String
}

actor PythonRuntimeService {
    /// Original requirements/TOML helper and pinned packaging parser only. No Skill
    /// path is added to sys.path and no declaration is installed or imported.
    func analyzeSkillManifest(payload: Data, workspace: URL) async throws -> RuntimeExecutionResult {
        guard let helperURL = Bundle.main.url(forResource: "hanlin_python_manifest", withExtension: "py"),
              let wheel = Bundle.main.url(forResource: "packaging-26.3-py3-none-any", withExtension: "whl") else {
            throw RuntimeCoreError.invalidRequest("Bundled original manifest parser unavailable")
        }
        let wheelBytes = try Data(contentsOf: wheel)
        let hash = SHA256.hash(data: wheelBytes).map { String(format: "%02x", $0) }.joined()
        guard hash == "d7193f7c8e4e93f444fde0262bf90af30e16fa0ad0ad44cb553c87339b23cd1c" else {
            throw RuntimeCoreError.invalidDependencyManifest
        }
        let literal: (String) throws -> String = {
            // Python string literals do not decode JSON's optional escaped slash.
            // Match the original PythonPackageManager's trusted-path encoding.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: try encoder.encode($0), as: UTF8.self)
        }
        let helper = try String(contentsOf: helperURL, encoding: .utf8)
        let source = helper + """

        import json, base64, os
        _wheel = \(try literal(wheel.path))
        for _name, _module in list(sys.modules.items()):
            if _name == 'packaging' or _name.startswith('packaging.'):
                if not str(getattr(_module, '__file__', '')).startswith(_wheel + '/'):
                    raise RuntimeError('Untrusted packaging module origin')
        sys.path.insert(0, _wheel)
        import packaging
        from packaging.requirements import Requirement
        if packaging.__version__ != '26.3' or not packaging.__file__.startswith(_wheel + '/'):
            raise RuntimeError('Original packaging provenance mismatch')
        _input = json.loads(base64.b64decode(\(try literal(payload.base64EncodedString()))))
        _report = analyze_python_manifest(_input['file'], base64.b64decode(_input['base64']), requirement_parser=Requirement, packaging_version=packaging.__version__)
        print(json.dumps(_report))
        """
        return try await executePythonJob(.init(source: source, workspace: workspace,
            environment: ["SKILL_ID": "hanlin-skill-analysis"]), trustedInspection: true)
    }

    private struct BridgeResponse: Decodable {
        let stdout: String?
        let stderr: String?
        let value: RuntimeJSONValue?
        let exitCode: Int?
        let didTimeOut: Bool?
        let wasCancelled: Bool?
        let outputWasTruncated: Bool?
        let outputFiles: [String: RuntimeOutputArtifact]?
        let error: String?
    }
    private let fileLayout: RuntimeFileLayout
    private let environmentStore: RuntimeEnvironmentStore?
    private let jobs: RuntimeJobStore
    private var snapshotValue = RuntimeSnapshot.stopped(.localPython)
    private var activeIDs: Set<UUID> = []
    private var stopGeneration: UInt64 = 0
    private var stopRequested = false

    init(fileLayout: RuntimeFileLayout = .default, jobs: RuntimeJobStore? = nil, environment: RuntimeEnvironmentStore? = nil) {
        self.fileLayout = fileLayout
        self.environmentStore = environment
        self.jobs = jobs ?? RuntimeJobStore(fileLayout: fileLayout)
    }
    func snapshot() -> RuntimeSnapshot { snapshotValue }

    private struct ModuleResolution: Decodable, Sendable {
        struct Module: Codable, Sendable {
            struct SourceFile: Codable, Sendable {
                let path: String
                let sha256: String
                let bytes: Int
            }
            let name: String
            let status: String
            let reason: String
            let resolvedPath: String?
            let sourceFiles: [SourceFile]
        }
        let scope: String
        let producer: String
        let engineVersion: String
        let resolutionOnly: Bool
        let modules: [Module]
    }
    private struct CachedModuleResolution: Sendable {
        let report: ModuleResolution
        let environment: String
        let generation: UInt64
        let helperSHA256: String
        let observedAt: Date
        let executionID: UUID
    }
    private var moduleFactGeneration: UInt64 = 0
    private var moduleResolution: CachedModuleResolution?

    private func moduleEnvironmentIdentity() throws -> String {
        var bytes = Data("native-skill-isolated/v1".utf8)
        for url in [fileLayout.environmentRegistry, fileLayout.registry.appending(path: "PythonPackages.json")] {
            bytes.append(0)
            bytes.append(contentsOf: url.lastPathComponent.utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                bytes.append(1)
                bytes.append(try Data(contentsOf: url))
            } else { bytes.append(0) }
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Passive: read cached native observations and recheck their exact source
    /// hashes. This method never starts Python, imports a module, or submits a job.
    func observedSkillModuleFacts() async -> [PythonSkillModuleFact] {
        guard [.ready, .executing].contains(snapshotValue.state),
              let cached = moduleResolution, cached.generation == moduleFactGeneration,
              cached.report.engineVersion == snapshotValue.version,
              let environment = try? moduleEnvironmentIdentity(), environment == cached.environment else { return [] }
        let facts = await Task.detached {
            var verifiedFiles: [String: Bool] = [:]
            var totalBytes = 0
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return cached.report.modules.compactMap { module -> PythonSkillModuleFact? in
                for source in module.sourceFiles {
                    let key = source.path + "\0" + source.sha256
                    if verifiedFiles[key] == false { return nil }
                    if verifiedFiles[key] == true { continue }
                    guard source.bytes >= 0, source.bytes <= 64 * 1_048_576,
                          totalBytes <= 64 * 1_048_576 - source.bytes,
                          source.sha256.count == 64,
                          let file = FileHandle(forReadingAtPath: source.path) else { return nil }
                    defer { try? file.close() }
                    var hash = SHA256()
                    var count = 0
                    do {
                        while let bytes = try file.read(upToCount: min(65_536, source.bytes - count + 1)), !bytes.isEmpty {
                            count += bytes.count
                            guard count <= source.bytes else { verifiedFiles[key] = false; return nil }
                            hash.update(data: bytes)
                        }
                    } catch { verifiedFiles[key] = false; return nil }
                    totalBytes += count
                    let matches = count == source.bytes
                        && hash.finalize().map { String(format: "%02x", $0) }.joined() == source.sha256
                    verifiedFiles[key] = matches
                    guard matches else { return nil }
                }
                guard let encoded = try? encoder.encode(module) else { return nil }
                var identity = Data(cached.helperSHA256.utf8)
                identity.append(encoded)
                return .init(name: module.name, status: module.status, resolvedPath: module.resolvedPath,
                    identity: SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined(),
                    observedAt: cached.observedAt, executionID: cached.executionID,
                    engineVersion: cached.report.engineVersion)
            }
        }.value
        guard cached.generation == moduleFactGeneration,
              (try? moduleEnvironmentIdentity()) == cached.environment else { return [] }
        return facts
    }

    /// Original AST and original import finders run only on this explicit action.
    /// The analyzed source remains data. Module resolution requires loaded
    /// original dependencies; this is not an arbitrary-interpreter security boundary.
    func analyzeSkillSyntax(payload: Data, workspace: URL) async throws -> RuntimeExecutionResult {
        guard let url = Bundle.main.url(forResource: "hanlin_python_ast", withExtension: "py") else {
            throw RuntimeCoreError.invalidRequest("Bundled Python syntax helper unavailable")
        }
        let helper = try String(contentsOf: url, encoding: .utf8)
        let helperHash = SHA256.hash(data: Data(helper.utf8)).map { String(format: "%02x", $0) }.joined()
        let generation = moduleFactGeneration
        let environment = try moduleEnvironmentIdentity()
        let literal = String(decoding: try JSONEncoder().encode(payload.base64EncodedString()), as: UTF8.self)
        let source = helper + """

        import json, base64, os
        _hanlin = json.loads(base64.b64decode(\(literal)))
        _report = analyze_python_source(_hanlin['file'], base64.b64decode(_hanlin['base64']))
        _report['moduleResolution'] = inspect_python_module_requirements(_report['findings'])
        print(json.dumps(_report))
        """
        moduleResolution = nil
        let result = try await executePythonJob(.init(source: source, workspace: workspace,
            environment: ["SKILL_ID": "hanlin-skill-analysis"]), trustedInspection: true)
        struct Envelope: Decodable { let moduleResolution: ModuleResolution }
        if result.exitCode == 0, !result.wasCancelled, !result.didTimeOut,
           generation == moduleFactGeneration, environment == (try moduleEnvironmentIdentity()),
           let value = try? JSONDecoder().decode(Envelope.self, from: Data(result.stdout.utf8)) {
            let report = value.moduleResolution
            if report.scope == "native-skill-isolated", report.producer == "CPython.importlib.machinery",
               report.resolutionOnly, report.engineVersion == snapshotValue.version,
               report.modules.count <= 64, Set(report.modules.map(\.name)).count == report.modules.count,
               report.modules.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 256
                   && ["available", "unknown"].contains($0.status) }) {
                moduleResolution = .init(report: report, environment: environment, generation: generation,
                    helperSHA256: helperHash, observedAt: .now, executionID: result.executionID)
            }
        }
        return result
    }
    func prepare() throws -> RuntimeSnapshot {
        try fileLayout.prepareIfNeeded()
        let version = try PythonRuntimeBridge.version()
        guard version == "3.14.6" else { throw RuntimeCoreError.runtimeFailure("Expected embedded Python 3.14.6, received \(version).") }
        stopRequested = false
        snapshotValue.state = activeIDs.isEmpty ? .ready : .executing
        snapshotValue.version = version
        snapshotValue.source = "beeware/Python-Apple-support"
        snapshotValue.lastHealthCheck = .now
        snapshotValue.lastErrorCode = nil
        return snapshotValue
    }
    func stop() async -> RuntimeSnapshot {
        moduleFactGeneration &+= 1
        moduleResolution = nil
        stopGeneration &+= 1
        stopRequested = true
        for id in activeIDs {
            PythonRuntimeBridge.cancel(id: id)
            try? await jobs.requestCancellation(id: id, kind: .localPython)
        }
        snapshotValue.state = activeIDs.isEmpty ? .stopped : .executing
        snapshotValue.lastDiagnostic = activeIDs.isEmpty ? nil : "Stop requested; native Python calls must yield before cancellation can finish."
        return snapshotValue
    }
    func execute(_ request: RuntimeExecutionRequest) async throws -> RuntimeExecutionResult {
        try await executePythonJob(request)
    }

    func executeCLI(entryPoint: URL, arguments: [String], workspace: URL,
                    environment: [String: String] = [:], standardInput: URL? = nil) async throws -> RuntimeExecutionResult {
        let entry = try fileLayout.validatedReadableFile(entryPoint)
        let input = try standardInput.map { try fileLayout.validatedReadableFile($0) }
        return try await executePythonJob(RuntimeExecutionRequest(source: "", arguments: arguments,
            workspace: workspace, environment: environment), entryPoint: entry, standardInput: input)
    }

    private func executePythonJob(_ request: RuntimeExecutionRequest, entryPoint: URL? = nil,
                                  standardInput: URL? = nil, trustedInspection: Bool = false) async throws -> RuntimeExecutionResult {
        // A user job may change Python import state. Only these private, trusted
        // inspection calls may retain observations; an environment flag cannot.
        if !trustedInspection {
            moduleFactGeneration &+= 1
            moduleResolution = nil
        }
        let operation = RuntimeUserOperation.current
        try operation?.checkInterruption()
        let interruption = operation?.registerInterruption { reason in
            Task { await self.interrupt(id: request.id, reason: reason) }
        }
        defer { if let interruption { operation?.unregisterInterruption(interruption) } }
        let environment = try await environmentStore?.resolved(scopes: [.shared, .python, .execution(request.id)], overrides: request.environment)
            ?? RuntimePolicy.validatedEnvironment(request.environment)
        try Task.checkCancellation()
        if snapshotValue.state != .ready && snapshotValue.state != .executing { _ = try prepare() }
        let generation = stopGeneration
        let workspace = try fileLayout.validatedWorkspace(request.workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let initial = try await jobs.create(id: request.id, kind: .localPython)
        let observer = RuntimeJobProgress.reporter
        if let observer { await observer(initial) }
        do {
            guard generation == stopGeneration else { throw CancellationError() }
            PythonRuntimeBridge.register(id: request.id)
            activeIDs.insert(request.id)
            snapshotValue.state = .executing
            snapshotValue.activeExecutionCount = activeIDs.count
            defer {
                PythonRuntimeBridge.unregister(id: request.id)
                activeIDs.remove(request.id)
                snapshotValue.activeExecutionCount = activeIDs.count
                snapshotValue.state = activeIDs.isEmpty ? (stopRequested ? .stopped : .ready) : .executing
            }
            // A status-tool cancellation can race registration while the queued
            // journal is already visible. Reconcile it after the native slot exists.
            if let latest = try await jobs.snapshot(id: request.id, kind: .localPython), latest.cancellationRequested {
                PythonRuntimeBridge.cancel(id: request.id)
            }
            try Task.checkCancellation()
            let milliseconds = try request.limits.timeoutMilliseconds()
            var body: [String: Any] = [
                "executionID": request.id.uuidString, "source": request.source, "arguments": request.arguments,
                "workspace": workspace.path, "packages": fileLayout.pythonPackages.path, "environment": environment,
                "outputDirectory": jobs.directory(id: request.id, kind: .localPython).path,
                "maximumOutputBytes": request.limits.maximumOutputBytes
            ]
            if let entryPoint { body["entryPoint"] = entryPoint.path }
            if let standardInput { body["standardInputPath"] = standardInput.path }
            if let milliseconds { body["timeoutSeconds"] = Double(milliseconds) / 1000 }
            let registry = fileLayout.registry.appending(path: "PythonPackages.json")
            if FileManager.default.fileExists(atPath: registry.path) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let installed = try decoder.decode([PythonPackageRecord].self, from: Data(contentsOf: registry))
                body["packageDirectories"] = try installed.sorted { $0.installedAt > $1.installedAt }.map { item in
                    try fileLayout.validatedDescendant(fileLayout.pythonPackages.appending(path: "\(item.normalizedName)-\(item.version)"), of: fileLayout.pythonPackages, allowRoot: false).path
                }
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
            let started = ContinuousClock.now
            let jobs = self.jobs
            let responseData = try await withThrowingTaskGroup(of: Data?.self) { group in
                group.addTask {
                    try await PythonRuntimeBridge.execute(requestJSON: json, id: request.id) {
                        Task {
                            try? await jobs.markRunning(id: request.id, kind: .localPython)
                            if let observer, let record = try? await jobs.snapshot(id: request.id, kind: .localPython) { await observer(record) }
                        }
                    }
                }
                group.addTask {
                    do {
                        while !Task.isCancelled {
                            try await Task.sleep(for: .milliseconds(500))
                            if let record = try await jobs.refresh(id: request.id, kind: .localPython) {
                                if let observer { await observer(record) }
                            }
                        }
                    } catch is CancellationError { return nil }
                    return nil
                }
                defer { group.cancelAll() }
                for try await data in group { if let data { return data } }
                throw RuntimeCoreError.runtimeFailure("Python job ended without a result.")
            }
            let response = try JSONDecoder().decode(BridgeResponse.self, from: responseData)
            if let error = response.error { throw RuntimeCoreError.runtimeFailure(error) }
            let duration = started.duration(to: .now)
            let result = RuntimeExecutionResult(
                executionID: request.id, stdout: response.stdout ?? "", stderr: response.stderr ?? "", value: response.value,
                exitCode: response.exitCode, durationMilliseconds: duration.components.seconds * 1000 + Int64(duration.components.attoseconds / 1_000_000_000_000_000),
                didTimeOut: response.didTimeOut ?? false, wasCancelled: response.wasCancelled ?? false,
                outputWasTruncated: response.outputWasTruncated ?? false, outputFiles: response.outputFiles
            )
            operation?.recordJobOutput(id: request.id,
                stdout: result.outputFiles?["stdout"]?.bytes ?? Int64(result.stdout.utf8.count),
                stderr: result.outputFiles?["stderr"]?.bytes ?? Int64(result.stderr.utf8.count))
            let completed = try await jobs.complete(result, kind: .localPython)
            if let observer, let record = try await jobs.snapshot(id: request.id, kind: .localPython) { await observer(record) }
            return completed
        } catch {
            try? await jobs.fail(id: request.id, kind: .localPython, error: error)
            throw error
        }
    }

    private func interrupt(id: UUID, reason: String) async {
        try? await jobs.requestInterruption(id: id, kind: .localPython, reason: reason)
        PythonRuntimeBridge.cancel(id: id)
    }
}
