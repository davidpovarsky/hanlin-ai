import Foundation

/// Manifest-owned approval policy. This controls Hanlin consent only; platform,
/// credential, package, and resource permission authorities still run independently.
public struct HanlinToolApprovalDescriptor: Codable, Hashable, Sendable {
    public let requiresApproval: Bool
    public let actionParameter: String?
    /// Exact manifest-declared read actions in a mixed-action tool.
    public let nonSensitiveActions: [String]
    /// Argument fields that identify a delegated provider/resource, never arbitrary payloads.
    public let scopeParameters: [String]

    public init(requiresApproval: Bool = true, actionParameter: String? = nil,
                nonSensitiveActions: [String] = [], scopeParameters: [String] = []) {
        self.requiresApproval = requiresApproval
        self.actionParameter = actionParameter
        self.nonSensitiveActions = nonSensitiveActions
        self.scopeParameters = scopeParameters
    }

    public func requiresConsent(arguments: HanlinJSONValue, risk: HanlinRiskLevel) -> Bool {
        if let actionParameter, case .object(let object) = arguments,
           case .string(let action)? = object[actionParameter],
           nonSensitiveActions.contains(where: { $0.utf8.elementsEqual(action.utf8) }) {
            return false
        }
        return requiresApproval || ![HanlinRiskLevel.passive, .read].contains(risk)
    }

    private enum CodingKeys: String, CodingKey {
        case requiresApproval, actionParameter, nonSensitiveActions, scopeParameters
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requiresApproval = try values.decodeIfPresent(Bool.self, forKey: .requiresApproval) ?? true
        actionParameter = try values.decodeIfPresent(String.self, forKey: .actionParameter)
        nonSensitiveActions = try values.decodeIfPresent([String].self, forKey: .nonSensitiveActions) ?? []
        scopeParameters = try values.decodeIfPresent([String].self, forKey: .scopeParameters) ?? []
    }
}

extension HanlinToolDescriptor {
    public var approvalPolicy: HanlinToolApprovalDescriptor {
        approval ?? .init(requiresApproval: ![HanlinRiskLevel.passive, .read].contains(risk))
    }
}
