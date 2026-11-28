import Foundation
import HanlinPlatformContracts
import HanlinSkillFormat

/// Invocation metadata is not an execution permission. The original Host approval
/// and Runtime05 ExecutionPlan still own all effects and readiness.
enum SkillInvocationSource: Sendable { case user, model }

struct SkillInvocationPolicyCache {
    struct Entry {
        let source: Data
        let report: SkillRuntimeOpenClaw.Report
    }
    var signature: String?
    var entries: [HanlinSkillID: Entry] = [:]
}

extension HanlinSkillCatalog {
    /// Refresh only on an explicit chat/Skill action. Management lists and passive
    /// compatibility plans continue to render without starting an engine.
    func refreshInvocationPolicies(store: SkillStore = .shared) async throws {
        let descriptors = allSkills()
        let documents = descriptors.compactMap { descriptor -> (HanlinSkillID, SkillMarkdownDocument)? in
            guard let document = markdownDocument(for: descriptor.id),
                  SkillRuntimeOpenClaw.requiresPolicy(document)
                    || SkillRuntimeOpenClaw.hasInvocationMetadata(document) else { return nil }
            return (descriptor.id, document)
        }
        guard !documents.isEmpty else {
            invocationPolicyCache = .init()
            return
        }
        let service = SkillRuntimeService.shared
        let initial = await service.policyEnvironmentSignature(store: store)
        if invocationPolicyCache.signature == initial,
           documents.allSatisfy({ invocationPolicyCache.entries[$0.0]?.source == $0.1.originalSource }) { return }
        _ = try await AppRuntimeCore.shared.ensureStarted(.node)
        let signature = await service.policyEnvironmentSignature(store: store)
        let reports = try await SkillRuntimeOpenClaw.inspectPolicies(
            documents.map(\.1), enabled: documents.map { store.isSkillEnabled(id: $0.0) })
        try Task.checkCancellation()
        guard reports.count == documents.count,
              signature == (await service.policyEnvironmentSignature(store: store)),
              documents.allSatisfy({ markdownDocument(for: $0.0)?.originalSource == $0.1.originalSource }) else {
            throw RuntimeCoreError.invalidRequest("Skill source or environment changed during policy inspection")
        }
        invocationPolicyCache = .init(signature: signature, entries: Dictionary(uniqueKeysWithValues:
            zip(documents, reports).map { pair in
                (pair.0.0, SkillInvocationPolicyCache.Entry(source: pair.0.1.originalSource, report: pair.1))
            }))
    }

    func permitsInvocation(_ id: HanlinSkillID, source: SkillInvocationSource,
                           store: SkillStore = .shared) async throws -> Bool {
        guard resolve(id: id) != nil, store.isSkillEnabled(id: id) else { return false }
        guard let document = markdownDocument(for: id) else { return true }
        guard document.findings.isEmpty else { return false }
        // Ordinary instructions have no original-policy dependency. An unrelated
        // policy failure must not start an engine or block their explicit load.
        guard SkillRuntimeOpenClaw.requiresPolicy(document)
                || SkillRuntimeOpenClaw.hasInvocationMetadata(document) else { return true }
        try await refreshInvocationPolicies(store: store)
        return cachedInvocationPermitted(id, source: source)
    }

    func modelVisibleSkills(store: SkillStore = .shared) async -> [HanlinSkillDescriptor] {
        do {
            try await refreshInvocationPolicies(store: store)
            invocationPolicyError = nil
        } catch {
            invocationPolicyCache = .init()
            invocationPolicyError = error.localizedDescription
        }
        return allSkills().filter { store.isSkillEnabled(id: $0.id) && cachedInvocationPermitted($0.id, source: .model) }
    }

    private func cachedInvocationPermitted(_ id: HanlinSkillID, source: SkillInvocationSource) -> Bool {
        guard let document = markdownDocument(for: id) else { return resolve(id: id) != nil }
        guard document.findings.isEmpty else { return false }
        guard SkillRuntimeOpenClaw.requiresPolicy(document)
                || SkillRuntimeOpenClaw.hasInvocationMetadata(document) else { return true }
        guard let cached = invocationPolicyCache.entries[id], cached.source == document.originalSource,
              cached.report.known, cached.report.rawUpstreamResult?.eligible == true else { return false }
        switch source {
        case .user: return cached.report.invocation.userInvocable
        case .model: return !cached.report.invocation.disableModelInvocation
        }
    }
}
