import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptStore

struct ChavrusaShareActionTarget: Hashable, Identifiable {
    let identity: HanlinScriptExtensionIdentity
    let appID: HanlinAppID
    let actionID: HanlinActionID
    let title: String
    var id: String {
        "\(identity.installedPackageID.rawValue)/\(identity.generation)/\(identity.entrypointID)/\(actionID.rawValue)"
    }
}

extension HanlinScriptingPlatform {
    var shareActionTargets: [ChavrusaShareActionTarget] {
        installedPackages.filter(\.enabled).flatMap { package -> [ChavrusaShareActionTarget] in
            guard let descriptor = try? package.appDescriptor() else { return [] }
            return descriptor.actions.compactMap { action in
                guard action.capabilities.contains(where: { $0.rawValue == "inter-app.share" }),
                      let entry = package.entrypoints.first(where: {
                          ($0.kind == .app || $0.kind == .share) && $0.runtimeProfile == .hanlinNativeScript
                              && $0.sourcePath == action.handler
                      }) else { return nil }
                return .init(identity: .init(installedPackageID: package.record.installedPackageID,
                    packageID: package.record.packageID, generation: package.record.activeGeneration,
                    entrypointID: entry.id), appID: package.appID, actionID: action.id,
                    title: "\(descriptor.name.resolved(locale: .current)) — \(action.title.resolved(locale: .current))")
            }
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func submitShareBatch(_ batchID: UUID, to target: ChavrusaShareActionTarget) async throws {
        guard shareActionTargets.contains(target) else {
            throw HanlinInvocationDispatchError(.stale, .invalidTarget)
        }
        let batch = try await ChavrusaShareInbox.shared.batch(batchID)
        // The durable command binds this exact generation. Dispatch revalidates
        // it after restore; installation changes cannot silently retarget it.
        try submitResumeCommand(HanlinShareInvocation.command(batch: batch, identity: target.identity,
            appID: target.appID, actionID: target.actionID))
    }
}
