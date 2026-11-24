import Foundation

/// Declarative configuration rendered inside the existing composer bubble.
/// Field keys carry structured user configuration into the assistant-tool
/// context. They are separate from the model's arguments and never executable source.
public struct HanlinComposerConfiguration: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var panels: [HanlinComposerPanel]

    public init(schemaVersion: Int = 1, panels: [HanlinComposerPanel]) {
        self.schemaVersion = schemaVersion
        self.panels = panels
    }

    public var defaultValues: HanlinJSONValue {
        var values: HanlinObject<HanlinJSONValue> = [:]
        for field in panels.flatMap(\.fields) {
            if let value = field.defaultValue { values[field.key] = value }
        }
        return .object(values)
    }

    public func validateDefinition() throws {
        let issues = definitionIssues()
        if !issues.isEmpty {
            throw HanlinContractError.invalidSchema(reason: issues.map { "\($0.key): \($0.message)" }.joined(separator: "; "))
        }
    }

    public func definitionIssues() -> [HanlinComposerValidationIssue] {
        var issues: [HanlinComposerValidationIssue] = []
        if schemaVersion != 1 {
            issues.append(.init(key: "schemaVersion", message: "Unsupported composer configuration version."))
        }
        if panels.isEmpty {
            issues.append(.init(key: "panels", message: "At least one configuration panel is required."))
        }
        var panelIDs = Set<String>()
        var keys = Set<String>()
        for panel in panels {
            if panel.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !panelIDs.insert(panel.id).inserted {
                issues.append(.init(key: panel.id, message: "Panel identifiers must be nonempty and unique."))
            }
            if panel.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(key: panel.id, message: "A configuration panel needs a title."))
            }
            if panel.fields.isEmpty && panel.customViewID == nil {
                issues.append(.init(key: panel.id, message: "A configuration panel needs fields or a host view."))
            }
            if let customViewID = panel.customViewID, customViewID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(key: panel.id, message: "The custom view identifier must be nonempty."))
            }
            for field in panel.fields {
                if field.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !keys.insert(field.key).inserted {
                    issues.append(.init(key: field.key, message: "Configuration field keys must be nonempty and unique across panels."))
                }
                if field.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(.init(key: field.key, message: "A configuration field needs a title."))
                }
                if field.minimum?.isFinite == false || field.maximum?.isFinite == false {
                    issues.append(.init(key: field.key, message: "Configuration bounds must be finite."))
                }
                if let minimum = field.minimum, let maximum = field.maximum, minimum > maximum {
                    issues.append(.init(key: field.key, message: "Configuration bounds must be ordered."))
                }
                let options = field.options.flatMap(\.flattened)
                if [.choice, .multiChoice, .catalog].contains(field.kind) && options.isEmpty {
                    issues.append(.init(key: field.key, message: "A selection field needs catalog options."))
                }
                var optionIDs = Set<String>()
                for option in options {
                    if option.id.isEmpty || !optionIDs.insert(option.id).inserted || option.title.isEmpty {
                        issues.append(.init(key: field.key, message: "Option identifiers must be nonempty and unique, with a title."))
                    }
                }
                if let defaultValue = field.defaultValue {
                    issues += field.validationIssues(for: defaultValue)
                }
            }
        }
        return issues
    }

    public func validationIssues(for configuration: HanlinJSONValue) -> [HanlinComposerValidationIssue] {
        var issues = definitionIssues()
        guard case let .object(values) = configuration else {
            return issues + [.init(key: "configuration", message: "Composer configuration must be an object.")]
        }
        let fields = panels.flatMap(\.fields)
        // Host custom views may own additional structured fields. Their
        // provider validates those values; action inputSchema applies only to
        // model arguments, not to this separate configuration context.
        if !panels.contains(where: { $0.customViewID != nil }) {
            let keys = Set(fields.map(\.key))
            for (key, _) in values where !keys.contains(key) {
                issues.append(.init(key: key, message: "This configuration field is not declared."))
            }
        }
        for field in fields { issues += field.validationIssues(for: values[field.key]) }
        return issues
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, panels }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeManifestValueIfDeclared(Int.self, forKey: .schemaVersion) ?? 1
        panels = try values.decode([HanlinComposerPanel].self, forKey: .panels)
    }
}

public struct HanlinComposerPanel: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var fields: [HanlinComposerField]
    /// A native host may supply a custom view for this key through the shared
    /// configuration view's builder. It must update configuration, not execute.
    public var customViewID: String?

    public init(id: String, title: String, fields: [HanlinComposerField] = [], customViewID: String? = nil) {
        self.id = id
        self.title = title
        self.fields = fields
        self.customViewID = customViewID
    }

    private enum CodingKeys: String, CodingKey { case id, title, fields, customViewID }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        fields = try values.decodeManifestValueIfDeclared([HanlinComposerField].self, forKey: .fields) ?? []
        customViewID = try values.decodeManifestValueIfDeclared(String.self, forKey: .customViewID)
    }
}

public struct HanlinComposerOption: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var children: [HanlinComposerOption]

    public init(id: String, title: String, children: [HanlinComposerOption] = []) {
        self.id = id
        self.title = title
        self.children = children
    }

    public var flattened: [HanlinComposerOption] { [self] + children.flatMap(\.flattened) }

    private enum CodingKeys: String, CodingKey { case id, title, children }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        children = try values.decodeManifestValueIfDeclared([HanlinComposerOption].self, forKey: .children) ?? []
    }
}

public struct HanlinComposerField: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case text, toggle, number, choice, multiChoice, catalog, location
    }

    public var key: String
    public var title: String
    public var kind: Kind
    public var required: Bool
    public var defaultValue: HanlinJSONValue?
    public var options: [HanlinComposerOption]
    public var minimum: Double?
    public var maximum: Double?
    public var placeholder: String?
    public var id: String { key }

    public init(
        key: String,
        title: String,
        kind: Kind,
        required: Bool = false,
        defaultValue: HanlinJSONValue? = nil,
        options: [HanlinComposerOption] = [],
        minimum: Double? = nil,
        maximum: Double? = nil,
        placeholder: String? = nil
    ) {
        self.key = key
        self.title = title
        self.kind = kind
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
        self.minimum = minimum
        self.maximum = maximum
        self.placeholder = placeholder
    }

    public func validationIssues(for value: HanlinJSONValue?) -> [HanlinComposerValidationIssue] {
        guard let value, value != .null else {
            return required ? [issue("A value is required.")] : []
        }
        switch kind {
        case .text:
            guard case let .string(text) = value else { return [issue("Enter text.")] }
            return required && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [issue("A value is required.")] : []
        case .toggle:
            guard case .bool = value else { return [issue("Choose on or off.")] }
        case .number:
            guard let number = Self.number(value), number.isFinite else { return [issue("Enter a finite number.")] }
            if let minimum, number < minimum { return [issue("The value is below the allowed minimum.")] }
            if let maximum, number > maximum { return [issue("The value is above the allowed maximum.")] }
        case .choice:
            guard case let .string(selected) = value,
                  options.flatMap(\.flattened).contains(where: { $0.id == selected }) else {
                return [issue("Choose an available option.")]
            }
        case .multiChoice, .catalog:
            guard case let .array(selected) = value else { return [issue("Choose catalog options.")] }
            if required && selected.isEmpty { return [issue("Choose at least one option.")] }
            let available = Set(options.flatMap(\.flattened).map(\.id))
            var seen = Set<String>()
            for selection in selected {
                guard case let .string(id) = selection, available.contains(id), seen.insert(id).inserted else {
                    return [issue("The selection contains an unavailable or duplicate option.")]
                }
            }
        case .location:
            guard case let .object(location) = value,
                  let latitude = location["latitude"].flatMap(Self.number),
                  let longitude = location["longitude"].flatMap(Self.number),
                  let radius = location["radiusMeters"].flatMap(Self.number),
                  latitude.isFinite, longitude.isFinite, radius.isFinite,
                  (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude),
                  radius > 0 else {
                return [issue("Choose a valid map location and a positive radius.")]
            }
            if let minimum, radius < minimum { return [issue("The radius is below the allowed minimum.")] }
            if let maximum, radius > maximum { return [issue("The radius is above the allowed maximum.")] }
            if location.contains(where: { !["latitude", "longitude", "radiusMeters"].contains($0.key) }) {
                return [issue("The location contains an undeclared field.")]
            }
        }
        return []
    }

    private func issue(_ message: String) -> HanlinComposerValidationIssue {
        .init(key: key, message: message)
    }

    private static func number(_ value: HanlinJSONValue) -> Double? {
        switch value {
        case let .number(number): number
        case let .integer(number): Double(number)
        default: nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case key, title, kind, required, defaultValue, options, minimum, maximum, placeholder
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.decode(String.self, forKey: .key)
        title = try values.decode(String.self, forKey: .title)
        kind = try values.decode(Kind.self, forKey: .kind)
        required = try values.decodeManifestValueIfDeclared(Bool.self, forKey: .required) ?? false
        defaultValue = try values.decodeManifestValueIfDeclared(HanlinManifestJSONValue.self, forKey: .defaultValue)?.value
        options = try values.decodeManifestValueIfDeclared([HanlinComposerOption].self, forKey: .options) ?? []
        minimum = try values.decodeManifestValueIfDeclared(Double.self, forKey: .minimum)
        maximum = try values.decodeManifestValueIfDeclared(Double.self, forKey: .maximum)
        placeholder = try values.decodeManifestValueIfDeclared(String.self, forKey: .placeholder)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(key, forKey: .key)
        try values.encode(title, forKey: .title)
        try values.encode(kind, forKey: .kind)
        try values.encode(required, forKey: .required)
        try values.encodeIfPresent(defaultValue.map { HanlinManifestJSONValue($0) }, forKey: .defaultValue)
        try values.encode(options, forKey: .options)
        try values.encodeIfPresent(minimum, forKey: .minimum)
        try values.encodeIfPresent(maximum, forKey: .maximum)
        try values.encodeIfPresent(placeholder, forKey: .placeholder)
    }
}

public struct HanlinComposerValidationIssue: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var message: String
    public var id: String { key + "\n" + message }

    public init(key: String, message: String) {
        self.key = key
        self.message = message
    }
}
