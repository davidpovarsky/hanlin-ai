import CryptoKit
import Foundation
import HanlinAgentCore
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore

/// Request-scoped projections of installed assistantTool metadata. Neither
/// discovery nor attachment preparation starts an app or evaluates JavaScript.
@MainActor
enum HanlinMiniAppAssistantToolExports {
    static func descriptors() -> [HanlinComposerCapabilityDescriptor] {
        descriptors(in: HanlinScriptingPlatform.shared.installedPackages)
    }

    static func descriptors(in packages: [HanlinStoredPackageSnapshot]) -> [HanlinComposerCapabilityDescriptor] {
        packages.flatMap { package in
            package.entrypoints.compactMap { descriptor(package: package, entrypoint: $0) }
        }.sorted { $0.id < $1.id }
    }

    static func toolName(installedPackageID: String, entrypointID: String, actionID: String) -> String {
        let identity = [installedPackageID, entrypointID, actionID]
            .map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "miniapp_" + String(digest.prefix(40))
    }

    static func tools(attachments: [HanlinCapabilityAttachment]) -> [NativeTool] {
        tools(attachments: attachments, in: HanlinScriptingPlatform.shared.installedPackages)
    }

    static func tools(
        attachments: [HanlinCapabilityAttachment],
        in packages: [HanlinStoredPackageSnapshot]
    ) -> [NativeTool] {
        var selected: [String: HanlinMiniAppAssistantNativeTool] = [:]
        var ambiguous = Set<String>()
        for attachment in attachments where attachment.reference.kind == .miniApp {
            guard let package = packages.first(where: {
                $0.record.installedPackageID.rawValue == attachment.reference.sourceID
            }), let entrypoint = package.entrypoints.first(where: {
                $0.id == attachment.reference.capabilityID
            }), let descriptor = descriptor(package: package, entrypoint: entrypoint),
                  descriptor.validationIssues(for: attachment).isEmpty,
                  let declaration = entrypoint.assistantTool else { continue }
            for action in declaration.actions where attachment.actionID == nil || attachment.actionID == action.id {
                let selection = HanlinMiniAppAssistantToolSelection(
                    package: package, entrypoint: entrypoint, action: action, attachment: attachment)
                guard let tool = try? HanlinMiniAppAssistantNativeTool(selection: selection) else { continue }
                if let previous = selected[tool.name],
                   previous.selection.attachment.configuration != attachment.configuration {
                    ambiguous.insert(tool.name)
                }
                selected[tool.name] = tool
            }
        }
        // A whole-entry selection and a specific action may overlap. Conflicting
        // user configurations must be rejected by preparation, never arbitrarily chosen.
        return selected.keys.sorted().compactMap { name -> NativeTool? in
            ambiguous.contains(name) ? nil : selected[name]
        }
    }

    static func descriptor(
        package: HanlinStoredPackageSnapshot,
        entrypoint: HanlinPackageEntrypointDescriptor
    ) -> HanlinComposerCapabilityDescriptor? {
        guard package.enabled, entrypoint.kind == .assistantTool,
              entrypoint.compatibility != .unsupported,
              [.hanlinNativeScript, .hanlinExpo].contains(entrypoint.runtimeProfile),
              !package.entrypoints.contains(where: {
                  $0.kind == .app && ($0.sourcePath as NSString).deletingLastPathComponent
                      == (entrypoint.sourcePath as NSString).deletingLastPathComponent
              }),
              let declaration = entrypoint.assistantTool,
              (try? declaration.validateDefinition()) != nil,
              declaration.actions.allSatisfy({ action in
                  guard let handler = action.embeddedResultID else { return true }
                  return package.entrypoints.contains { $0.id == handler && $0.kind == .embeddedResult }
              }) else { return nil }
        return .init(
            reference: .init(kind: .miniApp, sourceID: package.record.installedPackageID.rawValue,
                             capabilityID: entrypoint.id, revision: String(package.record.activeGeneration)),
            title: declaration.title, summary: declaration.summary, systemImage: "square.stack.3d.up",
            actions: declaration.actions.map { .init(id: $0.id, title: $0.title, summary: $0.summary) },
            configuration: declaration.configuration)
    }
}

struct HanlinMiniAppAssistantToolSelection: Sendable {
    let package: HanlinStoredPackageSnapshot
    let entrypoint: HanlinPackageEntrypointDescriptor
    let action: HanlinAssistantToolAction
    let attachment: HanlinCapabilityAttachment

    @MainActor
    func currentPackage(in snapshots: [HanlinStoredPackageSnapshot]) throws -> HanlinStoredPackageSnapshot {
        guard let current = snapshots.first(where: {
            $0.record.installedPackageID == package.record.installedPackageID
        }), current.enabled,
              current.record.packageID == package.record.packageID,
              current.appID == package.appID,
              current.record.activeGeneration == package.record.activeGeneration,
              current.entrypoints.contains(entrypoint),
              let descriptor = HanlinMiniAppAssistantToolExports.descriptor(package: current, entrypoint: entrypoint),
              descriptor.validationIssues(for: attachment).isEmpty,
              attachment.actionID == nil || attachment.actionID == action.id,
              entrypoint.assistantTool?.actions.contains(action) == true else {
            throw HanlinMiniAppAssistantToolError.staleSelection
        }
        return current
    }

    /// Arguments and user configuration have different authorities. Preserve
    /// the exact approved arguments; configuration can only come from the snapshot.
    func parameters(argumentsJSON: Data) throws -> HanlinValue {
        let parsed = try HanlinJSONValue.decodeCanonicalJSON(argumentsJSON)
        guard case .object = parsed else { throw HanlinMiniAppAssistantToolError.invalidArguments }
        let arguments = try HanlinValue(jsonValue: parsed)
        let projected = try arguments.jsonValue(destination: .javaScriptBinary64).canonicalJSONData()
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: argumentsJSON, projectedJSON: projected)
        let configuration = try HanlinValue(jsonValue: attachment.configuration)
        _ = try configuration.jsonValue(destination: .javaScriptBinary64)
        return .object(["arguments": arguments, "configuration": configuration])
    }
}

@MainActor
private struct HanlinMiniAppAssistantNativeTool: NativeTool {
    let selection: HanlinMiniAppAssistantToolSelection
    let name: String
    private let schema: [String: Any]
    private let inputValidation: HanlinHostSchemaValidation
    private let outputValidation: HanlinHostSchemaValidation?

    init(selection: HanlinMiniAppAssistantToolSelection) throws {
        self.selection = selection
        self.name = HanlinMiniAppAssistantToolExports.toolName(
            installedPackageID: selection.package.record.installedPackageID.rawValue,
            entrypointID: selection.entrypoint.id, actionID: selection.action.id)
        let schemaData = try selection.action.inputSchema.canonicalJSONData()
        _ = try HanlinHostSchemaValidation.providerSchema(schemaData)
        guard let schema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw HanlinMiniAppAssistantToolError.invalidArguments
        }
        try HanlinHostSchemaValidation.requireSameValue(
            originalJSON: schemaData, projectedJSON: JSONSerialization.data(withJSONObject: schema))
        self.schema = schema
        self.inputValidation = try HanlinHostSchemaValidation(schemaJSON: schemaData)
        self.outputValidation = try selection.action.outputSchema.map {
            try HanlinHostSchemaValidation(schemaJSON: $0.canonicalJSONData())
        }
    }

    var catalogEntry: NativeToolCatalogEntry {
        let action = selection.action
        let embedded = action.embeddedResultID.map { HanlinEmbeddedPresentationDescriptor(handler: $0) }
        return .init(
            name: name, title: action.title, summary: action.summary,
            categories: ["MiniApps"], systemImage: "square.stack.3d.up",
            sourceAppID: selection.package.appID.rawValue,
            sourceAppTitle: selection.package.manifest?.name,
            isVisibleInSettings: false,
            presentationProfile: .init(
                identity: "miniapp.\(name)",
                activity: .init(kind: .execute, systemImage: "square.stack.3d.up",
                                runningTitle: action.title, completedTitle: action.title,
                                failedTitle: action.title, visibleArgumentKeys: []),
                result: embedded == nil ? nil : .init(rendererKind: .modernNative, supportsCard: true),
                resultDisplayPolicy: embedded == nil ? .never : .always,
                canonicalEmbeddedPresentation: embedded))
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(name: name, description: selection.action.summary, parameters: schema)
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        var diagnostics = NativeToolExecutionDiagnostics(
            canonicalLogicalToolID: selection.attachment.reference.id + ":" + selection.action.id,
            modelFacingAlias: name, backendRoute: selection.entrypoint.id, source: "miniApp",
            runtimeKind: selection.entrypoint.runtimeProfile.rawValue)
        let parameters: HanlinValue
        do {
            try Task.checkCancellation()
            let bytes = Data(argumentsJSON.utf8)
            try inputValidation.validate(argumentsJSON: bytes)
            parameters = try selection.parameters(argumentsJSON: bytes)
        } catch is CancellationError {
            return failure("MiniApp action cancelled.", outcome: .cancelled, diagnostics: diagnostics)
        } catch {
            return failure("The MiniApp action arguments do not match its declared schema or cannot be represented exactly by its JavaScript runtime.",
                           outcome: .invalidArguments, diagnostics: diagnostics)
        }

        do {
            let value = try await HanlinMiniAppAssistantToolRuntime.execute(selection: selection, parameters: parameters)
            try Task.checkCancellation()
            let bytes = try value.jsonValue().canonicalJSONData(limits: .unbounded)
            try outputValidation?.validate(argumentsJSON: bytes)
            let text = String(decoding: bytes, as: UTF8.self)
            let embedded: HanlinEmbeddedResultPayload? = selection.action.embeddedResultID.map { _ in
                .init(payload: value, title: selection.action.title, metadata: [
                    "installedPackageID": selection.package.record.installedPackageID.rawValue,
                    "generation": String(selection.package.record.activeGeneration),
                    "assistantToolEntrypointID": selection.entrypoint.id,
                    "assistantToolActionID": selection.action.id
                ], ownerID: selection.package.record.packageID.rawValue)
            }
            diagnostics.runtimeStateAfter = "closed"
            return .init(modelText: text, outcome: .succeeded, diagnostics: diagnostics,
                         embeddedPayload: embedded, isStoreEligible: true,
                         fullResultPayload: text, fullResultMIMEType: "application/json")
        } catch is CancellationError {
            return failure("MiniApp action cancelled.", outcome: .cancelled, diagnostics: diagnostics)
        } catch let error as HanlinMiniAppAssistantToolError {
            return failure(error.localizedDescription, outcome: .rejectedByAvailability, diagnostics: diagnostics)
        } catch {
            return failure("MiniApp action failed: \(error.localizedDescription)", outcome: .failed, diagnostics: diagnostics)
        }
    }

    private func failure(_ message: String, outcome: NativeToolExecutionOutcome,
                         diagnostics: NativeToolExecutionDiagnostics) -> NativeToolResult {
        var diagnostics = diagnostics
        diagnostics.failureCategory = outcome.rawValue
        diagnostics.wasCancelled = outcome == .cancelled
        diagnostics.runtimeStateAfter = "closed"
        return .init(modelText: message, userText: message, outcome: outcome, diagnostics: diagnostics)
    }
}
