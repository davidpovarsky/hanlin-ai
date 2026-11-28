import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Runtime Package Acceptance", .serialized)
struct RuntimePackageAcceptanceTests {
    private let npmPackage = (name: "is-number", version: "7.0.0")
    private let npmESMPackage = (name: "yocto-queue", version: "1.2.2")
    private let pythonPackage = (name: "requests", version: "2.34.2")

    @Test("Real npm packages install, import through Node and TypeScript, persist, and uninstall")
    func npmInstallImportPersistenceAndUninstall() async throws {
        let manager = AppRuntimeCore.shared.nodePackages
        try? await manager.uninstall(name: npmPackage.name)
        try? await manager.uninstall(name: npmESMPackage.name)

        do {
            let preview = try await withRegistryRetry {
                try await manager.preview(name: npmPackage.name, version: npmPackage.version)
            }
            #expect(preview.name == npmPackage.name)
            #expect(preview.version == npmPackage.version)
            #expect(preview.lifecycle?.rejected.isEmpty != false)

            let installed = try await withRegistryRetry {
                try await manager.install(name: npmPackage.name, version: npmPackage.version)
            }
            #expect(installed.version == npmPackage.version)
            #expect(try await manager.installed().contains { $0.name == npmPackage.name && $0.version == npmPackage.version })

            let probe = try await manager.probe(installed)
            #expect(probe.exitCode == 0)
            let nodeResult = await ExecuteJavaScriptTool().execute(
                argumentsJSON: #"{"source":"const {default: isNumber} = await import('is-number'); console.log(isNumber('42'));","runtime":"node"}"#,
                context: NativeToolExecutionContext(localeIdentifier: "en")
            )
            #expect(nodeResult.outcome == .succeeded)
            #expect(nodeResult.modelText.contains("true"))

            let typeScriptResult = await ExecuteTypeScriptTool().execute(
                argumentsJSON: #"{"source":"import isNumber from 'is-number'; console.log(isNumber('42'));","file_name":"npm-acceptance.ts","compile_only":false,"timeout_seconds":30}"#,
                context: NativeToolExecutionContext(localeIdentifier: "en")
            )
            #expect(typeScriptResult.outcome == .succeeded)
            #expect(typeScriptResult.modelText.contains("true"))

            let esmPreview = try await withRegistryRetry {
                try await manager.preview(name: npmESMPackage.name, version: npmESMPackage.version)
            }
            #expect(esmPreview.version == npmESMPackage.version)
            _ = try await withRegistryRetry {
                try await manager.install(name: npmESMPackage.name, version: npmESMPackage.version)
            }
            let esmResult = await ExecuteJavaScriptTool().execute(
                argumentsJSON: #"{"source":"const {default: Queue} = await import('yocto-queue'); const queue = new Queue(); queue.enqueue(40); queue.enqueue(2); console.log(queue.dequeue() + queue.dequeue());","runtime":"node","timeout_seconds":30}"#,
                context: NativeToolExecutionContext(localeIdentifier: "en")
            )
            #expect(esmResult.outcome == .succeeded)
            #expect(esmResult.modelText.contains("42"))

            #expect(try await manager.installed().contains { $0.name == npmPackage.name })
            #expect(try await manager.installed().contains { $0.name == npmESMPackage.name })

            try await manager.uninstall(name: npmPackage.name)
            try await manager.uninstall(name: npmESMPackage.name)
            #expect(try await manager.installed().allSatisfy { $0.name != npmPackage.name && $0.name != npmESMPackage.name })

            let missingImport = await ExecuteJavaScriptTool().execute(
                argumentsJSON: #"{"source":"await import('is-number')","runtime":"node"}"#,
                context: NativeToolExecutionContext(localeIdentifier: "en")
            )
            #expect(missingImport.outcome == .failed)
        } catch {
            try? await manager.uninstall(name: npmPackage.name)
            try? await manager.uninstall(name: npmESMPackage.name)
            throw error
        }
    }

    @Test("npm invalid package and version fail without registry contamination")
    func npmInvalidInputsRollback() async {
        let manager = AppRuntimeCore.shared.nodePackages
        await #expect(throws: (any Error).self) {
            _ = try await manager.preview(name: "__hanlin_nonexistent_npm_404__", version: "1.0.0")
        }
        await #expect(throws: (any Error).self) {
            _ = try await manager.install(name: npmPackage.name, version: "9999.0.0")
        }
        let installed = try? await manager.installed()
        #expect(installed?.contains { $0.name == "__hanlin_nonexistent_npm_404__" } == false)
    }

    @Test("Real pure-Python dependency graph installs, imports, persists, and uninstalls")
    func pythonInstallDependencyImportPersistenceAndUninstall() async throws {
        let manager = AppRuntimeCore.shared.pythonPackages
        if let existing = try await manager.installed().first(where: { $0.normalizedName == pythonPackage.name }) {
            try await manager.uninstall(existing)
        }

        do {
            let preview = try await withRegistryRetry {
                try await manager.preview(name: pythonPackage.name, version: pythonPackage.version)
            }
            #expect(preview.version == pythonPackage.version)
            #expect(preview.isPurePython)
            #expect(preview.wheelFileName?.hasSuffix("py3-none-any.whl") == true)

            let installed = try await withRegistryRetry {
                try await manager.install(name: pythonPackage.name, version: pythonPackage.version)
            }
            #expect(installed.version == pythonPackage.version)
            #expect((installed.resolvedDependencies ?? []).count >= 4)
            #expect(installed.dependencyRequirements.contains { $0.contains("urllib3") })

            let probe = try await manager.probe(installed)
            #expect(probe.exitCode == 0)
            let execution = await ExecuteLocalPythonTool().execute(
                argumentsJSON: #"{"source":"import requests; print(requests.utils.to_native_string(b'package-ok')); print(requests.__version__)","timeout_seconds":30}"#,
                context: NativeToolExecutionContext(localeIdentifier: "en")
            )
            #expect(execution.outcome == .succeeded)
            #expect(execution.modelText.contains("package-ok"))
            #expect(execution.modelText.contains(pythonPackage.version))

            #expect(try await manager.installed().contains {
                $0.normalizedName == pythonPackage.name && $0.version == pythonPackage.version
            })

            try await manager.uninstall(installed)
            #expect(try await manager.installed().allSatisfy { $0.normalizedName != pythonPackage.name })
            let missingImport = await ExecuteLocalPythonTool().execute(
                argumentsJSON: #"{"source":"import importlib, sys\nfor name in list(sys.modules):\n    if name == 'requests' or name.startswith('requests.'):\n        del sys.modules[name]\nimportlib.invalidate_caches()\nimport requests"}"#,
                context: NativeToolExecutionContext(localeIdentifier: "en")
            )
            #expect(missingImport.outcome == .failed)
        } catch {
            if let installed = try? await manager.installed().first(where: { $0.normalizedName == pythonPackage.name }) {
                try? await manager.uninstall(installed)
            }
            throw error
        }
    }

    @Test("Python manager rejects actual incompatible interpreter tags and invalid releases")
    func pythonUnsupportedAndInvalidInputs() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "package-tags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let manager = PythonPackageManager(fileLayout: layout, python: python)
        let workspace = try layout.workspace(client: .tools, identifier: "wheel-tags")
        let filename = "hanlin_incompatible_fixture-1.0-cp999-cp999-ios_99_0_arm64_iphoneos.whl"
        // Real local wheel, rather than assuming that every future NumPy release
        // must remain unsupported or that preview can fabricate a missing wheel.
        let created = try await python.execute(RuntimeExecutionRequest(source: """
        import zipfile
        filename = "hanlin_incompatible_fixture-1.0-cp999-cp999-ios_99_0_arm64_iphoneos.whl"
        info = "hanlin_incompatible_fixture-1.0.dist-info/"
        entries = {
            "hanlin_incompatible_fixture/__init__.py": "VALUE = 42\\n",
            info + "METADATA": "Metadata-Version: 2.3\\nName: hanlin-incompatible-fixture\\nVersion: 1.0\\n\\n",
            info + "WHEEL": "Wheel-Version: 1.0\\nRoot-Is-Purelib: false\\nTag: cp999-cp999-ios_99_0_arm64_iphoneos\\n",
        }
        entries[info + "RECORD"] = "".join(path + ",,\\n" for path in [*entries, info + "RECORD"])
        with zipfile.ZipFile(filename, "w") as wheel:
            for path, value in entries.items():
                wheel.writestr(path, value)
        print("ACTUAL_INCOMPATIBLE_WHEEL_CREATED")
        """, workspace: workspace))
        try #require(created.exitCode == 0)
        #expect(created.stdout.contains("ACTUAL_INCOMPATIBLE_WHEEL_CREATED"))
        do {
            _ = try await manager.preview(name: workspace.appending(path: filename).path)
            Issue.record("The running interpreter accepted a CPython999/iOS99 wheel")
        } catch {
            #expect(error.localizedDescription.contains("Wheel tags do not match this interpreter"))
        }
        #expect(try await manager.installed().allSatisfy { $0.normalizedName != "hanlin-incompatible-fixture" })

        await #expect(throws: (any Error).self) {
            _ = try await manager.preview(name: "__hanlin_nonexistent_pypi_404__", version: "1.0.0")
        }
        await #expect(throws: (any Error).self) {
            _ = try await manager.install(name: pythonPackage.name, version: "9999.0.0")
        }
        #expect(try await manager.installed().allSatisfy { $0.normalizedName != "__hanlin_nonexistent_pypi_404__" })
    }

    private func withRegistryRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: (any Error)?
        for attempt in 1...3 {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < 3, Self.isTransientRegistryFailure(error) else { throw error }
                try await Task.sleep(for: .seconds(attempt))
            }
        }
        throw lastError ?? RuntimeCoreError.runtimeFailure("Registry operation failed without an error.")
    }

    private static func isTransientRegistryFailure(_ error: any Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return [
            "timed out", "timeout", "temporarily", "connection", "network",
            "dns", "not connected", "http 500", "http 502", "http 503", "http 504"
        ].contains { message.contains($0) }
    }
}
