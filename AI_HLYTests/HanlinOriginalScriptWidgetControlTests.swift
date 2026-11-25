import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptCompiler
import HanlinWidgetUI
import Testing
@testable import HanlinScriptExtensions

struct HanlinOriginalScriptWidgetControlTests {
    private func program() throws -> HanlinWidgetProgram {
        let source = """
        function press() {
          if ($getenv('action-source') !== 'control' || $getenv('control-id') !== 'press') {
            throw new Error('The original button environment was lost');
          }
          $storage.setString('presses', String(Number($storage.getString('presses') || '0') + 1));
        }
        function changeEnabled() {
          const intended = $getenv('control-value');
          if ((intended !== 'true' && intended !== 'false') ||
              $getenv('action-value') !== intended ||
              $storage.getString('enabled') !== intended ||
              $getenv('action-id') !== 'change-enabled') {
            throw new Error('The original toggle environment/storage shape was lost');
          }
          $storage.setString('last-control', $getenv('control-id'));
        }
        """
        let original = Data("""
        {
          "formatVersion":2,"id":"test.original-controls","name":"Original Controls",
          "version":"1.0.0","runtimeVersion":"1.0","entry":"main.jsx",
          "supportedFamilies":["systemSmall"],"permissions":["storage"],"networkDomains":[],
          "actions":[
            {"id":"press","title":"Press","systemImage":"play.fill","function":"press"},
            {"id":"change-enabled","title":"Enable","systemImage":"switch.2","function":"changeEnabled"}
          ],
          "controls":[
            {"id":"press","type":"button","title":"Press","systemImage":"play.fill","actionID":"press"},
            {"id":"enabled","type":"toggle","title":"Enabled","systemImage":"switch.2",
             "actionID":"change-enabled","stateKey":"enabled"}
          ]
        }
        """.utf8)
        let manifest = HanlinScriptingManifest(name: "Original Controls", version: "1.0.0", entry: "main.jsx",
            unknownFields: ["kind": .string("widget"), "widgetEngine": .string("scriptwidget"),
                "hanlinWidget": .object(["abiVersion": .integer(1), "sourceFormat": .string("jsx"),
                    "families": .array([.string("systemSmall")]), "actions": .array([])])])
        let packageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanlinOriginalControlImport-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageRoot) }
        let files = ["script.json": try JSONEncoder().encode(manifest),
                     "main.jsx": Data(source.utf8), "widget.json": original]
        for (path, data) in files { try data.write(to: packageRoot.appendingPathComponent(path)) }
        let totalBytes = Int64(files.values.reduce(0) { $0 + $1.count })
        let staged = HanlinStagedPackage(
            source: .init(originalFileName: "OriginalControls.scriptwidget", format: .zip,
                contentSHA256: String(repeating: "a", count: 64), byteCount: totalBytes, importedAt: .now),
            stagingRoot: packageRoot, archiveURL: packageRoot.appendingPathComponent("source.zip"),
            packageRoot: packageRoot,
            inspection: .init(fileCount: files.count, directoryCount: 1, compressedBytes: totalBytes,
                uncompressedBytes: totalBytes, maximumDepth: 1, manifestPath: "script.json"),
            manifest: manifest)
        let preview = try HanlinScriptAnalyzer(inventory: .init(baselineID: "original-controls-test",
            baselineDigest: String(repeating: "b", count: 64), symbols: [])).analyze(staged)
        #expect(preview.canInstall)
        #expect(preview.entrypoints.count == 1)
        #expect(preview.entrypoints.first?.sourcePath == "main.jsx")
        let prepared = try HanlinWidgetPackagePreparation.programs(packageRoot: packageRoot, preview: preview)
        let installed = HanlinWidgetPackagePreparation.installedEntrypoints(preview: preview,
            artifactDigest: String(repeating: "c", count: 64))
        let path = try #require(installed.first?.sourcePath)
        return try JSONDecoder().decode(HanlinWidgetProgram.self, from: #require(prepared[path]))
    }

    private func install(_ program: HanlinWidgetProgram, store: HanlinScriptExtensionStore,
                         installedID: String, generation: UInt64 = 1) throws -> HanlinWidgetInstance {
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: installedID),
            packageID: try .init(validating: "package.original-controls"), generation: generation, entrypointID: "widget")
        let instance = HanlinWidgetInstance(identity: identity, engine: .scriptwidget, displayName: "Original Controls")
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program),
            installedPackageID: identity.installedPackageID, generation: generation)
        let widget = HanlinScriptWidgetSnapshot(identity: identity, displayName: instance.displayName,
            family: "systemSmall", validUntil: .distantFuture, engine: .scriptwidget,
            payload: .scriptwidget(.init(script: "", scriptRef: artifact.ref, scriptSHA256: artifact.sha256)),
            root: .init(kind: .text))
        try store.update { current in
            let current = current ?? .init(schemaVersion: 2, generatedAt: .now)
            return current.replacing(
                widgets: current.widgets.filter { $0.identity.installedPackageID != identity.installedPackageID } + [widget],
                instances: current.widgetInstances.filter { $0.identity.installedPackageID != identity.installedPackageID } + [instance],
                inactiveInstallations: current.inactiveWidgetInstallations.filter { $0 != installedID })
        }
        return instance
    }

    @Test func originalControlsCompileAndRunNativeActionsWithoutRendering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HanlinControl-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HanlinScriptExtensionStore(root: root)
        let compiled = try program()
        #expect(Set(compiled.actions.map(\.id)) == ["press", "change-enabled",
            "__scriptwidget_control_press", "__scriptwidget_control_enabled"])
        #expect(compiled.resources["widget.json"] != nil)
        let instance = try install(compiled, store: store, installedID: "installed.original-controls")
        let button = try #require(try HanlinScriptWidgetControlCatalog.controls(type: .button, store: store).first)
        let toggle = try #require(try HanlinScriptWidgetControlCatalog.controls(type: .toggle, store: store).first)
        #expect(!toggle.isOn)
        let first = try HanlinScriptWidgetControlCatalog.perform(
            identifier: button.id, type: .button, nonce: "one-button", store: store)
        #expect(first.receipt.applied)
        let repeated = try HanlinScriptWidgetControlCatalog.perform(
            identifier: button.id, type: .button, nonce: "one-button", store: store)
        #expect(!repeated.receipt.applied)
        _ = try HanlinScriptWidgetControlCatalog.perform(identifier: toggle.id, type: .toggle, value: true, store: store)
        let state = try #require(try store.load()?.widgetStates.first { $0.identity == instance.identity })
        #expect(state.values["presses"] == .string("1"))
        #expect(state.values["enabled"] == .string("true"))
        #expect(state.values["last-control"] == .string("enabled"))
        #expect(try HanlinScriptWidgetControlCatalog.resolve(identifier: toggle.id, type: .toggle, store: store)?.isOn == true)
        _ = try HanlinScriptWidgetControlCatalog.perform(identifier: toggle.id, type: .toggle, value: false, store: store)
        #expect(try HanlinScriptWidgetControlCatalog.resolve(identifier: toggle.id, type: .toggle, store: store)?.isOn == false)
        // A genuine widget render keeps its separate rendered-root requirement.
        #expect(throws: HanlinScriptWidgetError.self) {
            _ = try HanlinScriptWidgetRuntime.shared.run(program: compiled, values: [:], environment: [:])
        }
    }

    @Test func controlSelectionPreservesProductInstallationAndGenerationOwnership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HanlinControlOwnership-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = HanlinScriptExtensionStore(root: root.appendingPathComponent("AI"))
        let other = HanlinScriptExtensionStore(root: root.appendingPathComponent("MiniApps"))
        let compiled = try program()
        let instance = try install(compiled, store: first, installedID: "installed.controls-one")
        _ = try install(compiled, store: first, installedID: "installed.controls-two")
        _ = try install(compiled, store: other, installedID: "installed.controls-one")
        let controls = try HanlinScriptWidgetControlCatalog.controls(type: .button, store: first)
        #expect(Set(controls.map(\.id)).count == 2)
        let selected = try #require(controls.first { $0.context.identity == instance.identity })
        let otherID = try #require(try HanlinScriptWidgetControlCatalog.controls(type: .button, store: other).first?.id)
        #expect(selected.id != otherID)
        #expect(throws: HanlinWidgetActionError.inactiveInstance) {
            _ = try HanlinScriptWidgetControlCatalog.perform(identifier: selected.id, type: .button, store: other)
        }
        let next = try install(compiled, store: first, installedID: instance.identity.installedPackageID.rawValue, generation: 2)
        #expect(try HanlinScriptWidgetControlCatalog.resolve(identifier: selected.id, type: .button, store: first)?.context.identity == next.identity)
        #expect(throws: HanlinWidgetActionError.inactiveInstance) {
            _ = try HanlinWidgetActionExecutor.perform(.init(context: selected.context,
                actionID: selected.actionID, controlID: selected.controlID), store: first)
        }
        try first.invalidateWidgetActions(installedPackageID: next.identity.installedPackageID)
        #expect(try HanlinScriptWidgetControlCatalog.resolve(identifier: selected.id, type: .button, store: first) == nil)
        #expect(throws: HanlinWidgetActionError.inactiveInstance) {
            _ = try HanlinScriptWidgetControlCatalog.perform(identifier: selected.id, type: .button, store: first)
        }
    }

    @Test @MainActor
    func originalControlEntitiesProvidersAndNativeIntentsUseThePublishedHostStore() async throws {
        let store = try HanlinScriptExtensionStore()
        let id = "installed.original-control-test." + UUID().uuidString.lowercased()
        let instance = try install(program(), store: store, installedID: id)
        defer {
            _ = try? store.update { current in
                guard let current else { return .init(schemaVersion: 2, generatedAt: .now) }
                return current.replacing(
                    widgets: current.widgets.filter { $0.identity.installedPackageID.rawValue != id },
                    instances: current.widgetInstances.filter { $0.identity.installedPackageID.rawValue != id },
                    states: current.widgetStates.filter { $0.identity.installedPackageID.rawValue != id },
                    inactiveInstallations: current.inactiveWidgetInstallations.filter { $0 != id })
            }
        }
        let buttonRecord = try #require(try HanlinScriptWidgetControlCatalog.controls(type: .button, store: store)
            .first { $0.context.identity == instance.identity })
        let toggleRecord = try #require(try HanlinScriptWidgetControlCatalog.controls(type: .toggle, store: store)
            .first { $0.context.identity == instance.identity })
        let button = try #require(try await ScriptWidgetButtonControlQuery().entities(for: [buttonRecord.id]).first)
        let toggle = try #require(try await ScriptWidgetToggleControlQuery().entities(for: [toggleRecord.id]).first)
        #expect(try await ScriptWidgetButtonControlQuery().suggestedEntities().contains { $0.id == button.id })
        #expect(try await ScriptWidgetToggleControlQuery().suggestedEntities().contains { $0.id == toggle.id })
        var buttonConfiguration = SelectScriptWidgetButtonIntent()
        buttonConfiguration.control = button
        var toggleConfiguration = SelectScriptWidgetToggleIntent()
        toggleConfiguration.control = toggle
        #expect(try await ScriptWidgetButtonControlProvider().currentValue(configuration: buttonConfiguration).title == "Press")
        #expect(try await ScriptWidgetToggleControlProvider().currentValue(configuration: toggleConfiguration).isOn == false)
        _ = try await RunScriptWidgetControlIntent(controlID: button.id).perform()
        var setValue = SetScriptWidgetControlValueIntent(controlID: toggle.id)
        setValue.value = true
        _ = try await setValue.perform()
        #expect(try await ScriptWidgetToggleControlProvider().currentValue(configuration: toggleConfiguration).isOn == true)
        let state = try #require(try store.load()?.widgetStates.first { $0.identity == instance.identity })
        #expect(state.values["presses"] == .string("1"))
        #expect(state.values["enabled"] == .string("true"))
        try store.invalidateWidgetActions(installedPackageID: instance.identity.installedPackageID)
        #expect(try await ScriptWidgetButtonControlQuery().entities(for: [button.id]).isEmpty)
        #expect(try await ScriptWidgetToggleControlQuery().entities(for: [toggle.id]).isEmpty)
    }
}
