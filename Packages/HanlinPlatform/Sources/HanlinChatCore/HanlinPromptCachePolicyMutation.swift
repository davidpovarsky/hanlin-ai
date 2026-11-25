/// A user choice is distinct from the absence of an edit. In particular, the
/// automatic preset replaces a saved override with nil; preserve leaves it intact.
public enum HanlinPromptCachePolicySelection: Hashable, Sendable {
    case preserveSaved
    case inheritBase
    case preset(HanlinPromptCachePreset)
}

/// An explicit mutation lets native persistence preserve an untouched custom
/// policy, including its original serialized representation.
public enum HanlinPromptCachePolicyMutation: Equatable, Sendable {
    case preserve
    case replace(HanlinPromptCachePolicy?)

    public static func resolve(
        originalModelID: String,
        originalCompany: String?,
        selectedBaseModelID: String?,
        selectedBaseCompany: String?,
        selectedBasePolicy: HanlinPromptCachePolicy?,
        selection: HanlinPromptCachePolicySelection?
    ) -> Self {
        switch selection {
        case .preserveSaved:
            return .preserve
        case .preset(let preset):
            return .replace(preset.policy)
        case .inheritBase:
            return selectedBaseModelID == nil ? .preserve : .replace(selectedBasePolicy)
        case nil:
            guard let selectedBaseModelID else { return .preserve }
            let sameModel = restoreBaseModelName(from: originalModelID)
                == restoreBaseModelName(from: selectedBaseModelID)
            let sameProvider = originalCompany?.uppercased() == selectedBaseCompany?.uppercased()
            return sameModel && sameProvider ? .preserve : .replace(selectedBasePolicy)
        }
    }
}
