import Foundation

/// Immutable registrations supplied by RuntimeCore composition. Skill metadata
/// cannot register an engine or a trusted helper by decoding these descriptions.
struct SkillRuntimeRegistry: Sendable {
    typealias C = SkillRuntimeContract

    enum RegistrationError: Error, Equatable {
        case duplicateEngine(String)
        case duplicateHelper(String)
        case unknownHelper(String)
        case invalidHelper(String)
    }

    struct AnalysisHelperRegistration: Codable, Hashable, Sendable {
        let id: String
        let version: String
        let engineID: C.EngineID
        let relativePath: String
        let sourceSHA256: String
        let requirements: [C.SkillRequirement]
        /// The existing AST-owned SkillSyntaxReport is the output model. Its
        /// parser/scanner provenance stays there, without a second findings DTO.
        let outputContract: String
    }

    struct AnalysisInput: Codable, Hashable, Sendable {
        let schemaVersion: Int
        let file: String
        /// JSON Codable transports original bytes as base64, never escaped code
        /// interpolated into a shell/JS/Python source string.
        let utf8: Data
        let sourceSHA256: String

        init(file: String, utf8: Data, sourceSHA256: String) {
            schemaVersion = 1
            self.file = file
            self.utf8 = utf8
            self.sourceSHA256 = sourceSHA256
        }

        func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(self)
        }
    }

    struct PreparedAnalysis: Sendable {
        let registration: AnalysisHelperRegistration
        let input: AnalysisInput
        let plan: C.ExecutionPlan
    }

    private let providers: [C.EngineID: any SkillRuntimeCapabilityProvider]
    private let helpers: [String: AnalysisHelperRegistration]

    init(providers: [any SkillRuntimeCapabilityProvider],
         analysisHelpers: [AnalysisHelperRegistration] = []) throws {
        var providerIndex: [C.EngineID: any SkillRuntimeCapabilityProvider] = [:]
        for provider in providers {
            guard providerIndex.updateValue(provider, forKey: provider.engineID) == nil else {
                throw RegistrationError.duplicateEngine(provider.engineID.rawValue)
            }
        }
        var helperIndex: [String: AnalysisHelperRegistration] = [:]
        for helper in analysisHelpers {
            guard !helper.id.isEmpty, !helper.version.isEmpty,
                  !helper.relativePath.isEmpty, !helper.relativePath.hasPrefix("/"),
                  !helper.relativePath.contains("\\"), !helper.relativePath.contains("\0"),
                  !helper.relativePath.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  helper.sourceSHA256.utf8.count == 64,
                  helper.sourceSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  helper.outputContract == "SkillSyntaxReport" else {
                throw RegistrationError.invalidHelper(helper.id)
            }
            guard helperIndex.updateValue(helper, forKey: helper.id) == nil else {
                throw RegistrationError.duplicateHelper(helper.id)
            }
        }
        self.providers = providerIndex
        helpers = helperIndex
    }

    func plan(action: C.Action, lastTest: C.ExecutionTest? = nil,
              freshness: C.Freshness) async -> C.ExecutionPlan {
        let facts: C.EngineFacts?
        if action.kind != .instructions, let engine = action.engineID, let provider = providers[engine] {
            facts = await provider.snapshot(environmentID: action.environmentID)
        } else {
            facts = nil
        }
        return SkillRuntimePlanner.evaluate(action: action, engineFacts: facts,
                                            lastTest: lastTest, freshness: freshness)
    }

    /// Preparation only. RuntimeCore's existing execution route must validate
    /// the helper file hash and invocation digest again before reserving a job.
    /// No engine/helper is launched and no last-test result is invented here.
    func prepareAnalysis(helperID: String, input: AnalysisInput, invocationFingerprint: String,
                         environmentID: String, freshness: C.Freshness) async throws -> PreparedAnalysis {
        guard let helper = helpers[helperID] else { throw RegistrationError.unknownHelper(helperID) }
        let action = C.Action(id: "analysis/" + helper.id, kind: .analysisHelper,
                              skillID: helper.id, sourceFingerprint: helper.sourceSHA256,
                              actionFingerprint: helper.sourceSHA256, invocationFingerprint: invocationFingerprint,
                              relativePath: helper.relativePath, environmentID: environmentID,
                              engineID: helper.engineID, requirements: helper.requirements,
                              requirementsComplete: true)
        return PreparedAnalysis(registration: helper, input: input,
                                plan: await plan(action: action, freshness: freshness))
    }
}
