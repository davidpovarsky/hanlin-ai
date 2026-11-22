import Foundation

/// Routing identifiers are persisted separately from the label shown to people.
/// Older custom models also appended their generated UUID to the display label;
/// clean that exact suffix at presentation time without rewriting saved history.
enum HanlinModelDisplayName {
    static func clean(_ value: String) -> String {
        let label = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = label.range(of: "_repeat_", options: .backwards),
              UUID(uuidString: String(label[marker.upperBound...])) != nil else { return label }
        let original = String(label[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return original
    }

    static func resolve(displayName: String?, modelName: String?, fallback: String = String(localized: "Model")) -> String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let label = clean(displayName)
            if !label.isEmpty { return label }
        }
        if let modelName, !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let label = clean(modelName)
            if !label.isEmpty { return label }
        }
        return fallback
    }
}
