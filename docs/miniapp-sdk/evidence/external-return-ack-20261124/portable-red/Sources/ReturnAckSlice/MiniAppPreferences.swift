import Foundation

public struct MiniAppPreferences: Codable, Hashable, Sendable {
    public var favorites: [String]
    public var hidden: Set<String>
    public var opensInNewWindow: Bool

    public init(favorites: [String] = [], hidden: Set<String> = [], opensInNewWindow: Bool = true) {
        self.favorites = favorites; self.hidden = hidden; self.opensInNewWindow = opensInNewWindow
        normalize()
    }

    public mutating func normalize() {
        var seen = Set<String>()
        favorites = favorites.filter { seen.insert($0).inserted }
        hidden.subtract(favorites)
    }

    public mutating func setFavorite(_ appID: String, _ favorite: Bool) {
        favorites.removeAll { $0 == appID }
        if favorite { favorites.append(appID); hidden.remove(appID) }
    }

    public mutating func setVisible(_ appID: String, _ visible: Bool) {
        if visible { hidden.remove(appID) }
        else { hidden.insert(appID); favorites.removeAll { $0 == appID } }
    }

    public mutating func moveFavorites(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let indices = offsets.filter { favorites.indices.contains($0) }
        let moved = indices.map { favorites[$0] }
        let remaining = favorites.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = min(remaining.count, max(0, destination - indices.filter { $0 < destination }.count))
        favorites = Array(remaining.prefix(insertion)) + moved + Array(remaining.dropFirst(insertion))
    }

    public func orderedItems(_ catalog: [MiniAppCatalogItem], includeHidden: Bool = false) -> [MiniAppCatalogItem] {
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let first = favorites.compactMap { byID[$0] }
        let rest = catalog.filter { !favorites.contains($0.id) && (includeHidden || !hidden.contains($0.id)) }
        return first + rest
    }
}

public enum MiniAppTextEditing {
    /// Hosts commit this value and their request-ID receipt in the same editor transaction.
    /// This helper never mutates the document or acknowledges the transport result.
    public static func applying(_ result: MiniAppResult, to text: String,
                                selection: MiniAppTextSelection?) throws -> String {
        guard result.status == .success else { return text }
        switch result.operation {
        case .display, .custom: return text
        case .replaceDocument: return result.text
        case .insert:
            let position: String.Index
            if let selection {
                let range = try range(for: selection, in: text)
                position = range.upperBound
            } else { position = text.endIndex }
            var edited = text
            edited.insert(contentsOf: result.text, at: position)
            return edited
        case .replaceSelection:
            guard let selection else { throw MiniAppBridgeError.invalidSelection }
            let range = try range(for: selection, in: text)
            guard String(text[range]) == selection.text else { throw MiniAppBridgeError.selectionChanged }
            return text.replacingCharacters(in: range, with: result.text)
        }
    }

    private static func range(for selection: MiniAppTextSelection, in text: String) throws -> Range<String.Index> {
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= text.utf16.count,
              selection.length <= text.utf16.count - selection.location,
              let range = Range(NSRange(location: selection.location, length: selection.length), in: text)
        else { throw MiniAppBridgeError.invalidSelection }
        return range
    }
}
