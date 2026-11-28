// HanlinScriptPackageDiscovery.swift
// HanlinScriptStore
//
// Conforms script package storage to the canonical HanlinMiniAppDiscovery protocol,
// allowing installed Scripting and NativeScript packages to be discovered alongside
// native Swift Mini Apps through a single unified catalog abstraction.

import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public struct HanlinScriptPackageDiscovery: HanlinMiniAppDiscovery, Sendable {
    private let packagesProvider: @Sendable () async throws -> [HanlinStoredPackageSnapshot]

    public init(store: HanlinAtomicScriptStore) {
        self.packagesProvider = {
            try await store.restore()
        }
    }

    public init(snapshots: [HanlinStoredPackageSnapshot]) {
        self.packagesProvider = { snapshots }
    }

    public func registrations() async throws -> [any HanlinMiniAppRegistration] {
        let snapshots = try await packagesProvider()
        return snapshots.filter(\.enabled)
    }

    public func registration(
        for appID: HanlinAppID
    ) async throws -> (any HanlinMiniAppRegistration)? {
        let all = try await registrations()
        return all.first { $0.appID == appID }
    }

    public func catalogSnapshot(
        revision: HanlinCatalogRevision = .init(1)
    ) async throws -> HanlinCatalogSnapshot {
        let regs = try await registrations()
        let descriptors = try regs.map { try $0.appDescriptor() }
        return HanlinCatalogSnapshot(
            revision: revision,
            generatedAt: .now,
            apps: descriptors
        )
    }
}
