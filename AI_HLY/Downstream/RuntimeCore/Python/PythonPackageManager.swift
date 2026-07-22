import CryptoKit
import Foundation
import ZIPFoundation

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
    private struct PyPIProject: Decodable {
        struct Info: Decodable, Sendable {
            let name: String
            let version: String
            let summary: String?
            let requiresDist: [String]?
        }

        struct Distribution: Decodable, Sendable {
            struct Digests: Decodable, Sendable { let sha256: String }
            let filename: String
            let url: URL
            let packagetype: String
            let digests: Digests
            let size: Int64
        }

        let info: Info
        let releases: [String: [Distribution]]
        let urls: [Distribution]?
    }

    private struct Requirement: Sendable {
        let name: String
        let constraints: String
    }

    private struct ResolvedWheel: Sendable {
        let name: String
        let normalizedName: String
        let version: String
        let summary: String?
        let distribution: PyPIProject.Distribution
        let requirements: [String]
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
        guard FileManager.default.fileExists(atPath: registryURL.path) else {
            records = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([PythonPackageRecord].self, from: Data(contentsOf: registryURL))
        records = decoded
        return decoded
    }

    func preview(name: String, version: String? = nil) async throws -> PythonPackagePreview {
        let project = try await project(name: name)
        let selected = version ?? project.info.version
        let distributions = version == nil ? project.releases[selected] ?? [] : try await project(name: name, version: selected).urls ?? []
        let wheel = distributions.first(where: isUniversalWheel)
        return PythonPackagePreview(
            name: project.info.name,
            version: selected,
            summary: project.info.summary,
            wheelFileName: wheel?.filename,
            isPurePython: wheel != nil,
            compatibilityExplanation: wheel == nil
                ? "No py3-none-any wheel is published for this version. Source builds and dynamically loaded native extensions are unavailable on iOS."
                : "A py3-none-any wheel is available. Its complete dependency graph will be verified before installation."
        )
    }

    func install(
        name: String,
        version: String? = nil,
        importName: String? = nil,
        progress: @escaping @MainActor @Sendable (PythonPackageInstallProgress) -> Void = { _ in }
    ) async throws -> PythonPackageRecord {
        await progress(.init(phase: .resolving, completedUnits: 0, totalUnits: 1, packageName: name))
        let graph = try await resolveGraph(rootName: name, version: version) { update in
            await progress(update)
        }
        try Task.checkCancellation()
        guard let root = graph.first else { throw RuntimeCoreError.runtimeFailure("PyPI returned an empty dependency graph.") }

        try fileLayout.prepareIfNeeded()
        let operation = UUID().uuidString.lowercased()
        let staging = fileLayout.staging.appending(path: "python-\(operation)", directoryHint: .isDirectory)
        let candidate = fileLayout.pythonPackages.appending(path: ".000-candidate-\(operation)", directoryHint: .isDirectory)
        let destination = fileLayout.pythonPackages.appending(path: "\(root.normalizedName)-\(root.version)", directoryHint: .isDirectory)
        let backup = fileLayout.staging.appending(path: "python-backup-\(operation)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: candidate)
            try? FileManager.default.removeItem(at: backup)
        }

        var resolvedDependencies: [PythonPackageDependency] = []
        for (index, wheel) in graph.enumerated() {
            try Task.checkCancellation()
            await progress(.init(phase: .downloading, completedUnits: index, totalUnits: graph.count, packageName: wheel.name))
            let wheelURL = fileLayout.staging.appending(path: "\(operation)-\(index).whl")
            let digest = try await downloadAndVerify(wheel.distribution, to: wheelURL)
            defer { try? FileManager.default.removeItem(at: wheelURL) }
            await progress(.init(phase: .validating, completedUnits: index, totalUnits: graph.count, packageName: wheel.name))
            try inspectAndExtract(wheelURL: wheelURL, to: staging)
            if index > 0 {
                resolvedDependencies.append(.init(
                    name: wheel.name,
                    version: wheel.version,
                    wheelFileName: wheel.distribution.filename,
                    sha256: digest
                ))
            }
        }

        try Task.checkCancellation()
        try validateInstalledTree(staging, expectedDistributionCount: graph.count)
        let size = try directorySize(staging)
        await progress(.init(phase: .installing, completedUnits: graph.count, totalUnits: graph.count, packageName: root.name))

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: backup)
        }
        do {
            try FileManager.default.moveItem(at: staging, to: candidate)
            try Task.checkCancellation()
            await progress(.init(phase: .probing, completedUnits: graph.count, totalUnits: graph.count, packageName: root.name))
            let rootImportName = importName ?? root.normalizedName.replacingOccurrences(of: "-", with: "_")
            let probeResult = try await importProbe(name: rootImportName, identifier: operation)
            guard probeResult.exitCode == 0, !probeResult.didTimeOut else {
                throw RuntimeCoreError.runtimeFailure("The staged package failed its import probe.\n\(probeResult.stderr)")
            }

            try Task.checkCancellation()
            await progress(.init(phase: .committing, completedUnits: graph.count, totalUnits: graph.count, packageName: root.name))
            try FileManager.default.moveItem(at: candidate, to: destination)
            let record = PythonPackageRecord(
                name: root.name,
                normalizedName: root.normalizedName,
                version: root.version,
                wheelFileName: root.distribution.filename,
                sha256: root.distribution.digests.sha256.lowercased(),
                installedAt: .now,
                storageBytes: size,
                importName: rootImportName,
                dependencyRequirements: root.requirements,
                resolvedDependencies: resolvedDependencies
            )
            var current = try installed().filter { $0.normalizedName != root.normalizedName }
            current.append(record)
            do {
                try persist(current)
                try? FileManager.default.removeItem(at: backup)
                return record
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if FileManager.default.fileExists(atPath: backup.path) {
                    try? FileManager.default.moveItem(at: backup, to: destination)
                }
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: candidate)
            if FileManager.default.fileExists(atPath: backup.path), !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    func uninstall(_ record: PythonPackageRecord) throws {
        let destination = fileLayout.pythonPackages.appending(path: "\(record.normalizedName)-\(record.version)", directoryHint: .isDirectory)
        let validated = try fileLayout.validatedDescendant(destination, of: fileLayout.pythonPackages, allowRoot: false)
        if FileManager.default.fileExists(atPath: validated.path) { try FileManager.default.removeItem(at: validated) }
        try persist(try installed().filter { $0.normalizedName != record.normalizedName })
    }

    func probe(_ record: PythonPackageRecord) async throws -> RuntimeExecutionResult {
        try await importProbe(name: record.importName, identifier: "installed")
    }

    private func resolveGraph(
        rootName: String,
        version: String?,
        progress: @escaping @Sendable (PythonPackageInstallProgress) async -> Void
    ) async throws -> [ResolvedWheel] {
        var queue = [Requirement(name: rootName, constraints: version.map { "==\($0)" } ?? "")]
        var resolved: [String: ResolvedWheel] = [:]
        var order: [String] = []

        while !queue.isEmpty {
            try Task.checkCancellation()
            guard resolved.count < 64 else { throw RuntimeCoreError.runtimeFailure("The package dependency graph exceeds the 64-package safety limit.") }
            let requirement = queue.removeFirst()
            let normalized = normalize(requirement.name)
            if let existing = resolved[normalized] {
                guard version(existing.version, satisfies: requirement.constraints) else {
                    throw RuntimeCoreError.runtimeFailure("Conflicting dependency requirements were found for \(requirement.name).")
                }
                continue
            }

            await progress(.init(phase: .resolving, completedUnits: resolved.count, totalUnits: resolved.count + queue.count + 1, packageName: requirement.name))
            let index = try await project(name: requirement.name)
            let selectedVersion = try selectVersion(from: index, constraints: requirement.constraints)
            let release = try await project(name: requirement.name, version: selectedVersion)
            let distributions = release.urls ?? release.releases[selectedVersion] ?? []
            guard let wheel = distributions.first(where: isUniversalWheel) else {
                if order.isEmpty {
                    throw RuntimeCoreError.runtimeFailure("This release has no py3-none-any wheel. Source builds and native wheels cannot be installed dynamically on iOS.")
                }
                throw RuntimeCoreError.runtimeFailure("This package depends on a native extension that cannot be installed dynamically on iOS.")
            }
            guard wheel.size <= 100 * 1_024 * 1_024 else {
                throw RuntimeCoreError.runtimeFailure("The wheel for \(release.info.name) exceeds the 100 MB package limit.")
            }
            let requirements = release.info.requiresDist ?? []
            let resolvedWheel = ResolvedWheel(
                name: release.info.name,
                normalizedName: normalize(release.info.name),
                version: selectedVersion,
                summary: release.info.summary,
                distribution: wheel,
                requirements: requirements
            )
            resolved[normalized] = resolvedWheel
            order.append(normalized)
            for raw in requirements {
                if let dependency = parseRequirement(raw), markerApplies(raw) {
                    queue.append(dependency)
                }
            }
        }
        return order.compactMap { resolved[$0] }
    }

    private func project(name: String, version: String? = nil) async throws -> PyPIProject {
        let normalized = normalize(name)
        guard normalized.range(of: "^[a-z0-9][a-z0-9._-]{0,127}$", options: .regularExpression) != nil else {
            throw RuntimeCoreError.invalidIdentifier
        }
        let suffix = version.map { "/\($0)" } ?? ""
        guard let url = URL(string: "https://pypi.org/pypi/\(normalized)\(suffix)/json") else {
            throw RuntimeCoreError.invalidIdentifier
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RuntimeCoreError.runtimeFailure("The package or requested version was not found on PyPI.")
        }
        return try JSONDecoder().decode(PyPIProject.self, from: data)
    }

    private func selectVersion(from project: PyPIProject, constraints: String) throws -> String {
        let versions = project.releases.keys
            .filter { version($0, satisfies: constraints) }
            .filter { candidate in project.releases[candidate]?.contains(where: isUniversalWheel) == true }
            .sorted { compareVersions($0, $1) == .orderedDescending }
        guard let selected = versions.first else {
            throw RuntimeCoreError.runtimeFailure("This package depends on a native extension that cannot be installed dynamically on iOS.")
        }
        return selected
    }

    private func downloadAndVerify(_ distribution: PyPIProject.Distribution, to destination: URL) async throws -> String {
        try validatePyPIURL(distribution.url)
        let (temporaryURL, response) = try await URLSession.shared.download(from: distribution.url)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let finalURL = http.url else {
            throw RuntimeCoreError.runtimeFailure("PyPI wheel download failed.")
        }
        try validatePyPIURL(finalURL)
        let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == distribution.digests.sha256.lowercased() else {
            throw RuntimeCoreError.runtimeFailure("The downloaded wheel failed SHA-256 verification.")
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return digest
    }

    private func validatePyPIURL(_ url: URL) throws {
        let host = url.host?.lowercased() ?? ""
        guard url.scheme?.lowercased() == "https",
              host == "pypi.org" || host == "files.pythonhosted.org" || host.hasSuffix(".pythonhosted.org") else {
            throw RuntimeCoreError.runtimeFailure("PyPI returned an untrusted wheel URL.")
        }
    }

    private func inspectAndExtract(wheelURL: URL, to staging: URL) throws {
        let archive = try Archive(url: wheelURL, accessMode: .read)
        for entry in archive {
            try Task.checkCancellation()
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let pathWithoutDirectorySuffix = path.hasSuffix("/") ? String(path.dropLast()) : path
            let components = pathWithoutDirectorySuffix.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"), !pathWithoutDirectorySuffix.isEmpty,
                  !components.contains(".."), !components.contains(""), entry.type != .symlink else {
                throw RuntimeCoreError.symbolicLinkRejected
            }
            let lower = path.lowercased()
            let forbiddenSuffixes = [".so", ".dylib", ".a", ".o", ".pyd", ".dll", ".exe", ".wasm", ".pth"]
            guard !forbiddenSuffixes.contains(where: lower.hasSuffix) else {
                throw RuntimeCoreError.runtimeFailure("The wheel contains executable or native binary material and cannot be installed dynamically on iOS.")
            }
        }
        try FileManager.default.unzipItem(at: wheelURL, to: staging)
    }

    private func validateInstalledTree(_ root: URL, expectedDistributionCount: Int) throws {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys)) else {
            throw RuntimeCoreError.runtimeFailure("The staged Python package could not be inspected.")
        }
        var distributionCount = 0
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { throw RuntimeCoreError.symbolicLinkRejected }
            if url.lastPathComponent.hasSuffix(".dist-info") { distributionCount += 1 }
            if values.isRegularFile == true, try hasExecutableMagic(url) {
                throw RuntimeCoreError.runtimeFailure("The wheel contains executable binary material and cannot be installed dynamically on iOS.")
            }
        }
        guard distributionCount >= expectedDistributionCount else {
            throw RuntimeCoreError.runtimeFailure("The wheel set does not contain complete dist-info metadata.")
        }
    }

    private func hasExecutableMagic(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 8) ?? Data()
        let signatures: [[UInt8]] = [
            [0x7f, 0x45, 0x4c, 0x46], [0x4d, 0x5a],
            [0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
            [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 0x0a],
            [0x00, 0x61, 0x73, 0x6d]
        ]
        return signatures.contains { bytes.starts(with: $0) }
    }

    private func importProbe(name: String, identifier: String) async throws -> RuntimeExecutionResult {
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_.]*$", options: .regularExpression) != nil else {
            throw RuntimeCoreError.invalidIdentifier
        }
        let workspace = try fileLayout.workspace(client: .tools, identifier: "python-package-probe-\(identifier)")
        let quoted = String(data: try JSONEncoder().encode(name), encoding: .utf8) ?? "\"\""
        let source = """
        import importlib, sys
        _hanlin_name = \(quoted)
        try:
            _hanlin_module = importlib.import_module(_hanlin_name)
            print(getattr(_hanlin_module, '__version__', 'import-ok'))
        finally:
            for _hanlin_key in list(sys.modules):
                if _hanlin_key == _hanlin_name or _hanlin_key.startswith(_hanlin_name + '.'):
                    sys.modules.pop(_hanlin_key, None)
        """
        return try await python.execute(RuntimeExecutionRequest(source: source, workspace: workspace))
    }

    private func isUniversalWheel(_ distribution: PyPIProject.Distribution) -> Bool {
        guard distribution.packagetype == "bdist_wheel" else { return false }
        let stem = distribution.filename.lowercased().dropLast(distribution.filename.lowercased().hasSuffix(".whl") ? 4 : 0)
        let tags = stem.split(separator: "-").suffix(3)
        return tags.count == 3 && tags[tags.startIndex] == "py3" && tags[tags.index(after: tags.startIndex)] == "none" && tags.last == "any"
    }

    private func parseRequirement(_ raw: String) -> Requirement? {
        let specification = raw.split(separator: ";", maxSplits: 1).first.map(String.init) ?? raw
        guard let match = specification.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*", options: .regularExpression) else { return nil }
        let name = String(specification[match])
        var remainder = String(specification[match.upperBound...]).trimmingCharacters(in: .whitespaces)
        if remainder.hasPrefix("[") {
            guard let closing = remainder.firstIndex(of: "]") else { return nil }
            remainder = String(remainder[remainder.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        }
        if remainder.hasPrefix("("), remainder.hasSuffix(")") {
            remainder = String(remainder.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return Requirement(name: name, constraints: remainder)
    }

    private func markerApplies(_ raw: String) -> Bool {
        guard let marker = raw.split(separator: ";", maxSplits: 1).dropFirst().first else { return true }
        let expression = marker.lowercased()
        if expression.contains("extra ") { return false }
        let groups = expression.components(separatedBy: " or ")
        return groups.contains { group in
            group.components(separatedBy: " and ").allSatisfy(evaluateMarker)
        }
    }

    private func evaluateMarker(_ raw: String) -> Bool {
        let marker = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
        let pattern = #"^(python_version|python_full_version|implementation_name|os_name|sys_platform|platform_system|platform_machine)\s*(==|!=|<=|>=|<|>)\s*['\"]([^'\"]+)['\"]$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: marker, range: NSRange(marker.startIndex..., in: marker)),
              match.numberOfRanges == 4,
              let variableRange = Range(match.range(at: 1), in: marker),
              let operatorRange = Range(match.range(at: 2), in: marker),
              let valueRange = Range(match.range(at: 3), in: marker) else { return true }
        let actual: String
        switch String(marker[variableRange]) {
        case "python_version": actual = "3.14"
        case "python_full_version": actual = "3.14.6"
        case "implementation_name": actual = "cpython"
        case "os_name": actual = "posix"
        case "sys_platform": actual = "ios"
        case "platform_system": actual = "iOS"
        case "platform_machine": actual = "arm64"
        default: return true
        }
        return compare(actual, String(marker[valueRange]), using: String(marker[operatorRange]))
    }

    private func version(_ candidate: String, satisfies constraints: String) -> Bool {
        let trimmed = constraints.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.split(separator: ",").allSatisfy { component in
            let value = component.trimmingCharacters(in: .whitespaces)
            for operation in ["===", "~=", "==", "!=", "<=", ">=", "<", ">"] where value.hasPrefix(operation) {
                let required = String(value.dropFirst(operation.count)).trimmingCharacters(in: .whitespaces)
                if required.hasSuffix(".*"), operation == "==" {
                    return candidate.hasPrefix(String(required.dropLast(1)))
                }
                if operation == "~=" {
                    let lower = compare(candidate, required, using: ">=")
                    let pieces = required.split(separator: ".")
                    let prefix = pieces.dropLast().joined(separator: ".") + "."
                    return lower && candidate.hasPrefix(prefix)
                }
                return compare(candidate, required, using: operation == "===" ? "==" : operation)
            }
            return false
        }
    }

    private func compare(_ lhs: String, _ rhs: String, using operation: String) -> Bool {
        let result = compareVersions(lhs, rhs)
        switch operation {
        case "==": return result == .orderedSame
        case "!=": return result != .orderedSame
        case "<": return result == .orderedAscending
        case "<=": return result != .orderedDescending
        case ">": return result == .orderedDescending
        case ">=": return result != .orderedAscending
        default: return false
        }
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive])
    }

    private func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[-_.]+", with: "-", options: .regularExpression)
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
