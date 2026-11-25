import Foundation

/// A public projection of the installed original widget.json schema. Parsing and
/// validation remain in ScriptWidgetPackage and WidgetPackageManifestValidator.
public struct HanlinOriginalScriptWidgetControls: Sendable {
    public struct Action: Hashable, Sendable {
        public let id: String
        public let handler: String
    }

    public struct Control: Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case button, toggle }
        public let id: String
        public let kind: Kind
        public let title: String
        public let subtitle: String?
        public let systemImage: String
        public let actionID: String
        public let handler: String
        public let stateKey: String?

        /// Original action and control identifiers cannot contain underscores.
        /// This private prepared alias keeps distinct controls using one original
        /// action from conflating their separate state keys.
        public var preparedActionID: String { "__scriptwidget_control_" + id }
    }

    public let entry: String
    public let actions: [Action]
    public let controls: [Control]

    public static func read(_ data: Data, entryPath: String? = nil) throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanlinOriginalControlManifest-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        guard ScriptWidgetPackageFiles.write(data, root: root, relative: "widget.json"),
              let manifest = ScriptWidgetPackage(path: root, readonly: true).readManifest() else {
            throw HanlinOriginalScriptWidgetFailure("The original widget.json manifest is invalid.")
        }
        let report = WidgetPackageManifestValidator.validate(
            manifest, package: ScriptWidgetPackage(path: root, readonly: true), checkEntryExists: false)
        guard report.isValid else {
            throw HanlinOriginalScriptWidgetFailure(report.errors.map(\.message).joined(separator: "\n"))
        }
        if let entryPath, manifest.entry != entryPath {
            throw HanlinOriginalScriptWidgetFailure(
                "widget.json entry \(manifest.entry) does not match the declared ScriptWidget source \(entryPath).")
        }
        let actions = manifest.actions ?? []
        let controls = try (manifest.controls ?? []).map { control -> Control in
            let action: WidgetPackageAction
            if let actionID = control.actionID,
               let declared = actions.first(where: { $0.id.caseInsensitiveCompare(actionID) == .orderedSame }) {
                action = declared
            } else if let handler = control.action {
                action = .init(id: control.id, title: control.title, description: control.subtitle,
                               systemImage: control.systemImage, function: handler)
            } else {
                throw HanlinOriginalScriptWidgetFailure("Control \(control.id) has no declared original action.")
            }
            return Control(id: control.id, kind: control.type == .button ? .button : .toggle,
                title: control.title, subtitle: control.subtitle, systemImage: control.systemImage,
                actionID: action.id, handler: action.function, stateKey: control.stateKey)
        }
        return Self(entry: manifest.entry, actions: actions.map { .init(id: $0.id, handler: $0.function) },
                    controls: controls)
    }
}
