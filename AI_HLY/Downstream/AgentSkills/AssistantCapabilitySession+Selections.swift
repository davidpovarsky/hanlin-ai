import Foundation
import HanlinPlatformContracts

extension AssistantCapabilitySession {
    #if !HANLIN_ASSISTANT_CAPABILITIES_SDK
    /// Resolve provider identities once per request and refresh the same snapshot
    /// after a catalog refresh. No tool executes while preparing these selections.
    @MainActor
    func prepareExplicitSelections(using prepared: AssistantToolBridge.PreparedTools,
                                   catalog: HanlinSkillCatalog = .shared,
                                   store: SkillStore = .shared,
                                   capabilityCatalog: [HanlinComposerCapabilityDescriptor]? = nil) async throws {
        try await prepareExplicitSelections(availableAliases: Set(prepared.authority.schemasByAlias.keys),
            resolveAliases: { attachment in
            let names = HanlinComposerCapabilities.explicitNativeNames(in: [attachment])
            let miniAppNames: Set<String>
            if attachment.reference.kind == .miniApp && attachment.reference.capabilityID != "assistantTools",
               let descriptor = HanlinMiniAppAssistantToolExports.descriptors()
                    .first(where: { $0.reference == attachment.reference }) {
                miniAppNames = Set(descriptor.actions.filter {
                    attachment.actionID == nil || attachment.actionID == $0.id
                }.map { HanlinMiniAppAssistantToolExports.toolName(
                    installedPackageID: attachment.reference.sourceID,
                    entrypointID: attachment.reference.capabilityID, actionID: $0.id) })
            } else { miniAppNames = [] }
            return prepared.authority.backendRoutes.compactMap { entry -> String? in
                switch entry.backend {
                case .native(_, let name):
                    return names.contains(name) || miniAppNames.contains(name) ? entry.route.alias : nil
                case .mcp(let serverID, let name):
                    guard attachment.reference.kind == .mcp,
                          serverID.uuidString.lowercased() == attachment.reference.sourceID.lowercased(),
                          attachment.reference.capabilityID == "*" || attachment.reference.capabilityID == name else { return nil }
                    return entry.route.alias
                case .legacy(let name):
                    return attachment.reference.kind == .tool
                        && attachment.reference.sourceID == LegacyToolCanonicalAdapter.providerInstanceIDString
                        && attachment.reference.capabilityID == name ? entry.route.alias : nil
                default: return nil
                }
            }.sorted()
            }, catalog: catalog, store: store, capabilityCatalog: capabilityCatalog)
    }
    #endif

    @MainActor
    func prepareExplicitSelections(availableAliases: Set<String>,
                                   resolveAliases: @MainActor (HanlinCapabilityAttachment) throws -> [String],
                                   catalog: HanlinSkillCatalog = .shared,
                                   store: SkillStore = .shared,
                                   capabilityCatalog: [HanlinComposerCapabilityDescriptor]? = nil) async throws {
        guard !capabilityAttachments.isEmpty else { return }
        try HanlinComposerCapabilities.validate(capabilityAttachments, catalog: capabilityCatalog)
        var aliasesByAttachment: [UUID: [String]] = [:]
        for attachment in capabilityAttachments {
            if attachment.reference.kind == .skill {
                guard let skill = catalog.resolve(rawID: attachment.reference.capabilityID),
                      try await catalog.permitsInvocation(skill.id, source: .user, store: store) else {
                    throw HanlinComposerCapabilityError.unavailable(attachment.title)
                }
                try Task.checkCancellation()
                if !isSkillLoaded(skill.id) {
                    let instructions = await catalog.loadInstructions(for: skill)
                    try Task.checkCancellation()
                    recordSkillLoaded(id: skill.id, instructionText: instructions,
                                      preferredToolIDs: skill.preferredToolIDs)
                }
                recordExplicitSkill(skill.id)
                let hints = skill.preferredToolIDs.filter { availableAliases.contains($0) }
                exposeTools(aliases: hints)
                aliasesByAttachment[attachment.id] = hints
                continue
            }
            let aliases = try resolveAliases(attachment)
            guard !aliases.isEmpty else { throw HanlinComposerCapabilityError.unavailable(attachment.title) }
            aliasesByAttachment[attachment.id] = aliases
        }
        try bindExplicitTools(aliasesByAttachment)
    }

    @MainActor
    func retainCurrentlyEligibleSkills(modelSkills: [HanlinSkillDescriptor],
                                      catalog: HanlinSkillCatalog = .shared,
                                      store: SkillStore = .shared) async {
        var allowed = Set(modelSkills.map(\.id))
        for id in explicitlySelectedSkillIDs {
            if (try? await catalog.permitsInvocation(id, source: .user, store: store)) == true {
                allowed.insert(id)
            }
        }
        retainLoadedSkills(allowedIDs: allowed)
    }
}
