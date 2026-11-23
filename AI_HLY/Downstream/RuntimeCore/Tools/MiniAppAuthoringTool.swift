import Foundation
import HanlinPlatformContracts

/// Dedicated discoverable tools for the complete authoring -> validation -> build -> import flow.
struct MiniAppAuthoringTool: NativeTool {
    enum Operation: Equatable { case sdk, validate, build, importPackage }
    let operation: Operation

    var name: String {
        switch operation {
        case .sdk: "get_miniapp_sdk"
        case .validate: "validate_miniapp"
        case .build: "build_miniapp"
        case .importPackage: "import_miniapp"
        }
    }

    private var title: String {
        switch operation {
        case .sdk: "MiniApp SDK"
        case .validate: "Validate MiniApp"
        case .build: "Build MiniApp"
        case .importPackage: "Import MiniApp"
        }
    }

    var catalogEntry: NativeToolCatalogEntry {
        .init(name: name, title: RuntimeL10n.string(title), summary: description,
              categories: ["miniapps", "code", "typescript"],
              keywords: ["expo", "nativescript", "scriptwidget", "miniapp", "types", "compile", "import"],
              examples: ["Build and import a MiniApp"], isSensitive: false, systemImage: "shippingbox",
              presentationProfile: RuntimeToolSupport.profile(name: name, image: "shippingbox",
                  running: title, completed: title, arguments: ["engine", "project_path", "archive_path", "transfer_id"]))
    }

    private var description: String {
        switch operation {
        case .sdk:
            "Read the original Expo, NativeScript and ScriptWidget APIs, types, package versions and documentation packaged with this installed host. Pass resource to read a file from the returned SDK. Use these exact types before authoring."
        case .validate:
            "Typecheck an entire MiniApp source project with the original TypeScript compiler and installed host SDK. Returns structured diagnostics including code, file and one-based line/column. For a source-preserving imported package, project_path may point at the extracted archive root. Does not execute the MiniApp."
        case .build:
            "Validate and build a MiniApp package using the original host SDK. Expo uses Metro; NativeScript emits an ESM source graph for its original shared Core runtime; ScriptWidget preserves source for its original widget compiler. Successful output includes archivePath and retained sources for repair. Does not compile new native frameworks."
        case .importPackage:
            "Send a built local archive directly to Hanlin MiniApps for its actual importer. The initial receipt may be queued; query transfer_id to receive the actual installed or failed result. Never describe queued as installed."
        }
    }

    func openAIToolSchema() -> [String: Any] {
        let engine = NativeToolSchema.string(description: "Original MiniApp engine.", enumValues: ["expo", "nativescript", "scriptwidget"])
        let properties: [String: Any]
        let required: [String]
        switch operation {
        case .sdk:
            properties = ["engine": engine, "resource": NativeToolSchema.string(description: "SDK-relative documentation or declaration path from get_miniapp_sdk.")]
            required = []
        case .validate, .build:
            var fields: [String: Any] = ["engine": engine,
                "project_path": NativeToolSchema.string(description: "Absolute local directory containing script.json, package.json, tsconfig.json, source files and hanlin.authoring.json.")]
            if operation == .build {
                fields["archive_path"] = NativeToolSchema.string(description: "Optional new absolute output archive path. Omit to create a unique archive beside the prepared build.")
            }
            properties = fields
            required = ["engine", "project_path"]
        case .importPackage:
            properties = [
                "archive_path": NativeToolSchema.string(description: "Absolute local archive path from build_miniapp. Supply this or transfer_id."),
                "transfer_id": NativeToolSchema.string(description: "A previous receipt UUID to query the actual import result. Supply this or archive_path.")
            ]
            required = []
        }
        return NativeToolSchema.function(name: name, description: description,
            parameters: NativeToolSchema.object(properties: properties, required: required))
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let keys: Set<String>
            switch operation {
            case .sdk: keys = ["engine", "resource"]
            case .validate: keys = ["engine", "project_path"]
            case .build: keys = ["engine", "project_path", "archive_path"]
            case .importPackage: keys = ["archive_path", "transfer_id"]
            }
            let arguments = try NativeToolJSON.validatedDictionary(from: argumentsJSON, allowedKeys: keys)
            if operation == .sdk {
                let value = try await MiniAppAuthoringService.sdk(
                    engine: try NativeToolJSON.strictOptionalString(arguments, "engine"),
                    resource: try NativeToolJSON.strictOptionalString(arguments, "resource"))
                return try result(value, succeeded: true, summary: "Installed host SDK and original declaration resources.")
            }
            if operation == .importPackage {
                let archive = try NativeToolJSON.strictOptionalString(arguments, "archive_path")
                let transfer = try NativeToolJSON.strictOptionalString(arguments, "transfer_id")
                guard (archive != nil) != (transfer != nil) else {
                    throw RuntimeCoreError.invalidRequest("Supply exactly one of archive_path or transfer_id.")
                }
                let text: String
                if let transfer {
                    guard let id = UUID(uuidString: transfer) else { throw RuntimeCoreError.invalidRequest("transfer_id must be a UUID.") }
                    text = try MiniAppAuthoringDelivery.status(transferID: id)
                } else if let archive {
                    text = try await MiniAppAuthoringDelivery.importArchive(at: localURL(archive))
                } else {
                    throw RuntimeCoreError.invalidRequest("An import archive is required.")
                }
                let data = Data(text.utf8)
                let receipt = try JSONDecoder().decode(RuntimeJSONValue.self, from: data)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let status = object?["status"] as? String ?? "unknown"
                return try result(receipt, succeeded: status != "failed",
                    summary: status == "installed" ? "Installed in Hanlin MiniApps."
                        : status == "failed" ? "MiniApps import failed. Read the returned diagnostics."
                        : "Import receipt: \(status). Query transfer_id for completion.")
            }
            let engine = try NativeToolJSON.strictRequiredString(arguments, "engine")
            guard ["expo", "nativescript", "scriptwidget"].contains(engine) else {
                throw RuntimeCoreError.invalidRequest("Expected expo, nativescript, or scriptwidget.")
            }
            let project = try localURL(NativeToolJSON.strictRequiredString(arguments, "project_path"))
            let report: HanlinMiniAppAuthoringReport
            if operation == .validate {
                report = try await MiniAppAuthoringService.validate(project: project, engine: engine)
            } else {
                let archive = try NativeToolJSON.strictOptionalString(arguments, "archive_path").map(localURL)
                report = try await MiniAppAuthoringService.build(project: project, engine: engine, archive: archive)
            }
            let count = report.diagnostics.filter { $0.category == "error" }.count
            let summary = report.succeeded
                ? report.archivePath.map { "Built package: \($0)" } ?? "Project typecheck passed."
                : "\(count) diagnostic error(s). Repair the reported source locations and validate again."
            return try result(report, succeeded: report.succeeded, summary: summary)
        } catch {
            return RuntimeToolSupport.failure(error, title: title, runtimeKind: .typeScript)
        }
    }

    private func localURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw RuntimeCoreError.invalidRequest("An absolute local filesystem path is required.")
        }
        return URL(fileURLWithPath: path)
    }

    private func result<T: Encodable>(_ value: T, succeeded: Bool, summary: String) throws -> NativeToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(value), as: UTF8.self)
        return NativeToolResult(modelText: text, userText: summary,
            uiBlocks: [.init(type: succeeded ? .card : .error, title: RuntimeL10n.string(title),
                             body: summary, systemImage: "shippingbox")],
            outcome: succeeded ? .succeeded : .failed, isStoreEligible: true)
    }
}
