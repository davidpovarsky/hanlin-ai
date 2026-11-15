import HanlinPlatformContracts

/// Canonical descriptor authorization shared by both application hosts.
public actor HanlinMiniAppAuthorizationPolicy {
    public init() {}
    private var descriptors: [HanlinAppID: HanlinAppDescriptor] = [:]

    public func replace(with items: [HanlinMiniAppCatalogItem]) {
        descriptors = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.descriptor) })
    }

    public func authorize(_ request: HanlinMiniAppRequest) -> Bool {
        if request.caller.rawValue == "hanlin.host" {
            guard let target = descriptors[request.target] else { return false }
            let targetCapabilities = Set(target.capabilities.map(\.id))
            return targetCapabilities.contains(request.capability)
        }
        guard request.caller != request.target,
              let caller = descriptors[request.caller],
              let target = descriptors[request.target] else { return false }
        let callerCapabilities = Set(caller.capabilities.map(\.id))
        let targetCapabilities = Set(target.capabilities.map(\.id))
        return callerCapabilities.contains(request.capability)
            && targetCapabilities.contains(request.capability)
    }
}

