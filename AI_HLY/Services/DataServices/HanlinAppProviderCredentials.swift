import Foundation
import HanlinScriptExtensions
import SwiftData

/// The original host owns credential policy. Neither an SDK namespace nor a
/// fabricated account identifier grants Keychain access.
struct HanlinAppProviderCredentials: Sendable {
    /// The original record's container chooses the credential service. A shared
    /// helper must not redirect another account when a second SDK view mounts.
    static let shared = HanlinAppProviderCredentials()

    enum Failure: LocalizedError {
        case staleRecord, commitVerificationFailed, migrationUnavailable

        var errorDescription: String? {
            switch self {
            case .staleRecord:
                "The credential record changed. Reopen its settings before saving."
            case .commitVerificationFailed:
                "The saved key could not be verified. Reopen these settings before trying again."
            case .migrationUnavailable:
                "This key is not eligible for migration. Reopen its settings before trying again."
            }
        }
    }

    static func userMessage(for error: Error) -> String {
        if let error = error as? HanlinKeychainCredentialStore.Failure { return error.localizedDescription }
        if let error = error as? Failure { return error.localizedDescription }
        // Core Data / provider errors can carry object values in their descriptions.
        return String(localized: "The key could not be saved or verified. Reopen its settings and try again.")
    }

    private let configuredKeychain: HanlinKeychainCredentialStore?

    init(keychain: HanlinKeychainCredentialStore? = nil) {
        configuredKeychain = keychain
    }

    /// Retains the explicit-store API used by existing host/test integrations.
    var keychain: HanlinKeychainCredentialStore {
        configuredKeychain ?? HanlinApplicationCredentials.currentHost.store
    }

    private func keychain(for container: ModelContainer?) -> HanlinKeychainCredentialStore {
        configuredKeychain ?? HanlinApplicationCredentialRegistry.shared.credentials(for: container).store
    }

    func resolve<Record: HanlinProviderCredentialRecord>(_ record: Record) throws -> String? {
        try keychain(for: record.modelContext?.container).resolve(record.storedCredential, kind: Record.credentialKind)
    }

    func matches<Record: HanlinProviderCredentialRecord>(_ value: String, for record: Record) throws -> Bool {
        guard let stored = try resolve(record) else { return false }
        return stored.utf8.elementsEqual(value.utf8)
    }

    private static func sameStoredValue(_ lhs: String?, _ rhs: String?) -> Bool {
        lhs.map { Data($0.utf8) } == rhs.map { Data($0.utf8) }
    }

    /// A settings-only save must not rewrite an unchanged credential or create a
    /// Keychain generation. The original representation, including nil, is preserved.
    @MainActor
    func saveMetadata<Record: HanlinProviderCredentialRecord>(
        for record: Record, expectedStoredValue: String?, in context: ModelContext,
        update: (Record) -> Void = { _ in }
    ) throws {
        try requireCurrent(record, expectedStoredValue: expectedStoredValue, in: context)
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        if context.hasChanges { try context.save() }
        try requireCurrent(record, expectedStoredValue: expectedStoredValue, in: context)
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        update(record)
        guard Self.sameStoredValue(record.storedCredential, expectedStoredValue) else {
            context.rollback()
            throw Failure.staleRecord
        }
        do { try context.save() }
        catch { context.rollback(); throw error }
        try verifyCommit(record, expectedStoredValue: expectedStoredValue, in: context)
    }

    /// Retained for explicit legacy-compatibility callers. Settings use protected
    /// writes for replacements and saveMetadata for unchanged credentials.
    /// A row already using a supported handle must never be downgraded to plaintext.
    @MainActor
    func saveCompatible<Record: HanlinProviderCredentialRecord>(
        _ value: String, for record: Record, expectedStoredValue: String?,
        in context: ModelContext, update: (Record) -> Void = { _ in }
    ) throws {
        if expectedStoredValue.map(HanlinKeychainCredentialStore.isReference) ?? false {
            try save(value, for: record, expectedStoredValue: expectedStoredValue, in: context, update: update)
            return
        }
        guard !HanlinKeychainCredentialStore.isReference(value) else {
            throw HanlinKeychainCredentialStore.Failure.invalidReference
        }
        try requireCurrent(record, expectedStoredValue: expectedStoredValue, in: context)
        // Check the original durable row before checkpointing unrelated UI edits.
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        if context.hasChanges { try context.save() }
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        record.storedCredential = value
        update(record)
        do { try context.save() }
        catch { context.rollback(); throw error }
        try verifyCommit(record, expectedStoredValue: value, in: context)
    }

    @MainActor
    func insertCompatible<Record: HanlinProviderCredentialRecord>(
        _ record: Record, value: String, in context: ModelContext
    ) throws {
        guard record.modelContext == nil else { throw Failure.staleRecord }
        guard !HanlinKeychainCredentialStore.isReference(value) else {
            throw HanlinKeychainCredentialStore.Failure.invalidReference
        }
        if context.hasChanges { try context.save() }
        record.storedCredential = value
        context.insert(record)
        do { try context.save() }
        catch { context.rollback(); throw error }
        try verifyCommit(record, expectedStoredValue: value, in: context)
    }

    /// The caller supplies the exact stored value observed when opening the editor.
    /// Keychain generations contain their predecessor; no old secret is deleted.
    @MainActor
    func save<Record: HanlinProviderCredentialRecord>(
        _ value: String, for record: Record, expectedStoredValue: String?,
        in context: ModelContext, update: (Record) -> Void = { _ in }
    ) throws {
        try requireCurrent(record, expectedStoredValue: expectedStoredValue, in: context)
        // Check the original durable row before checkpointing unrelated UI edits.
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        if context.hasChanges { try context.save() }
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        let reference = try keychain(for: context.container).stage(value, kind: Record.credentialKind,
                                           previousStoredValue: expectedStoredValue)
        try requireCurrent(record, expectedStoredValue: expectedStoredValue, in: context)
        try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        record.storedCredential = reference
        update(record)
        do {
            try context.save()
        } catch {
            context.rollback()
            // A failed/uncertain commit never authorizes deleting this generation.
            throw error
        }
        try verifyCommit(record, expectedStoredValue: reference, in: context)
        guard try matches(value, for: record) else { throw Failure.commitVerificationFailed }
    }

    /// A custom provider is not inserted with plaintext while waiting for Save.
    @MainActor
    func insert<Record: HanlinProviderCredentialRecord>(
        _ record: Record, value: String, in context: ModelContext
    ) throws {
        guard record.modelContext == nil else { throw Failure.staleRecord }
        if context.hasChanges { try context.save() }
        let reference = try keychain(for: context.container).stage(value, kind: Record.credentialKind,
                                           previousStoredValue: record.storedCredential)
        record.storedCredential = reference
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        try verifyCommit(record, expectedStoredValue: reference, in: context)
        guard try matches(value, for: record) else { throw Failure.commitVerificationFailed }
    }

    /// Explicit recovery only: never runs at startup or on a normal read.
    /// Restoring a legacy representation deliberately restores that compatibility;
    /// it is not a claim that historical CloudKit/SQLite copies were erased.
    @MainActor
    func restorePrevious<Record: HanlinProviderCredentialRecord>(
        for record: Record, expectedReference: String, in context: ModelContext
    ) throws {
        try requireCurrent(record, expectedStoredValue: expectedReference, in: context)
        try requireDurableValue(record, expectedStoredValue: expectedReference, in: context)
        if context.hasChanges { try context.save() }
        try requireDurableValue(record, expectedStoredValue: expectedReference, in: context)
        let previous = try keychain(for: context.container).previousStoredValue(for: expectedReference, kind: Record.credentialKind)
        record.storedCredential = previous
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        try verifyCommit(record, expectedStoredValue: previous, in: context)
    }

    @MainActor
    private func requireCurrent<Record: HanlinProviderCredentialRecord>(
        _ record: Record, expectedStoredValue: String?, in context: ModelContext
    ) throws {
        guard record.modelContext === context, !record.isDeleted,
              Self.sameStoredValue(record.storedCredential, expectedStoredValue) else { throw Failure.staleRecord }
    }

    @MainActor
    private func requireDurableValue<Record: HanlinProviderCredentialRecord>(
        _ record: Record, expectedStoredValue: String?, in context: ModelContext
    ) throws {
        let reader = ModelContext(context.container)
        reader.autosaveEnabled = false
        let id = record.persistentModelID
        guard let stored = try reader.fetch(FetchDescriptor<Record>()).first(where: { $0.persistentModelID == id }),
              Self.sameStoredValue(stored.storedCredential, expectedStoredValue) else { throw Failure.staleRecord }
    }

    @MainActor
    private func verifyCommit<Record: HanlinProviderCredentialRecord>(
        _ record: Record, expectedStoredValue: String?, in context: ModelContext
    ) throws {
        do {
            try requireCurrent(record, expectedStoredValue: expectedStoredValue, in: context)
            try requireDurableValue(record, expectedStoredValue: expectedStoredValue, in: context)
        } catch {
            // Save may already be durable. Do not replace it with a guessed older
            // value or delete either immutable Keychain generation.
            throw Failure.commitVerificationFailed
        }
    }
}

protocol HanlinProviderCredentialRecord: PersistentModel {
    static var credentialKind: HanlinKeychainCredentialStore.Kind { get }
    var storedCredential: String? { get set }
    var isBuiltInCredentialMarker: Bool { get }
}

extension HanlinProviderCredentialRecord {
    /// A delayed/locked Keychain must not silently reset a user's chosen provider.
    /// Request-time resolution still fails closed until the actual secret is available.
    var preservesCredentialSelection: Bool {
        guard let storedCredential, !storedCredential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        do {
            let value = try HanlinAppProviderCredentials.shared.resolve(self)
            return !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        } catch {
            return HanlinKeychainCredentialStore.isReference(storedCredential)
        }
    }
}

extension APIKeys: HanlinProviderCredentialRecord {
    static var credentialKind: HanlinKeychainCredentialStore.Kind { .model }
    var isBuiltInCredentialMarker: Bool { ["LOCAL", "APPLE"].contains(company?.uppercased() ?? "") }
    var storedCredential: String? {
        get { key }
        set { key = newValue }
    }
    var resolvedKey: String? { try? HanlinAppProviderCredentials.shared.resolve(self) }
}

extension SearchKeys: HanlinProviderCredentialRecord {
    static var credentialKind: HanlinKeychainCredentialStore.Kind { .search }
    var isBuiltInCredentialMarker: Bool { company == "AUTOMATIC_KEYLESS" }
    var storedCredential: String? {
        get { key }
        set { key = newValue }
    }
    var resolvedKey: String? { try? HanlinAppProviderCredentials.shared.resolve(self) }
}

extension ToolKeys: HanlinProviderCredentialRecord {
    static var credentialKind: HanlinKeychainCredentialStore.Kind { .tool }
    var isBuiltInCredentialMarker: Bool { company.uppercased() == "APPLEMAP" }
    var storedCredential: String? {
        get { key }
        set { key = newValue ?? "" }
    }
    var resolvedKey: String? { try? HanlinAppProviderCredentials.shared.resolve(self) }
}

/// Secret edits remain transient until the original editor explicitly saves.
/// A failed initial read cannot turn an unavailable reference into an empty save.
struct HanlinCredentialEditDraft {
    private(set) var recordID: PersistentIdentifier?
    private(set) var expectedStoredValue: String?
    private(set) var text = ""
    private(set) var loaded = false
    private(set) var edited = false
    private var loadedText: String?

    var isReadyToSave: Bool { recordID != nil && (loaded || edited) }

    var hasCredentialReplacement: Bool {
        guard edited else { return false }
        guard let loadedText else { return true }
        return !text.utf8.elementsEqual(loadedText.utf8)
    }

    func canMigrate<Record: HanlinProviderCredentialRecord>(_ record: Record) -> Bool {
        loaded && !hasCredentialReplacement && !text.isEmpty &&
            recordID == record.persistentModelID && !record.isBuiltInCredentialMarker &&
            !(expectedStoredValue.map(HanlinKeychainCredentialStore.isReference) ?? false)
    }

    mutating func load<Record: HanlinProviderCredentialRecord>(
        _ record: Record, credentials: HanlinAppProviderCredentials = .shared
    ) throws {
        recordID = record.persistentModelID
        expectedStoredValue = record.storedCredential
        text = ""
        loaded = false
        edited = false
        loadedText = nil
        text = try credentials.resolve(record) ?? ""
        loadedText = text
        loaded = true
    }

    mutating func replaceText(_ value: String) {
        text = value
        edited = true
    }

    @MainActor
    mutating func save<Record: HanlinProviderCredentialRecord>(
        to record: Record, in context: ModelContext,
        credentials: HanlinAppProviderCredentials = .shared,
        update: (Record) -> Void = { _ in }
    ) throws {
        guard isReadyToSave, recordID == record.persistentModelID else {
            throw HanlinAppProviderCredentials.Failure.staleRecord
        }
        if hasCredentialReplacement {
            try credentials.save(text, for: record, expectedStoredValue: expectedStoredValue,
                                 in: context, update: update)
        } else {
            try credentials.saveMetadata(for: record, expectedStoredValue: expectedStoredValue,
                                         in: context, update: update)
        }
        recordVerifiedCommit(record)
    }

    @MainActor
    mutating func migrate<Record: HanlinProviderCredentialRecord>(
        _ record: Record, in context: ModelContext,
        credentials: HanlinAppProviderCredentials = .shared,
        update: (Record) -> Void = { _ in }
    ) throws {
        guard canMigrate(record) else { throw HanlinAppProviderCredentials.Failure.migrationUnavailable }
        try credentials.save(text, for: record, expectedStoredValue: expectedStoredValue,
                             in: context, update: update)
        recordVerifiedCommit(record)
    }

    private mutating func recordVerifiedCommit<Record: HanlinProviderCredentialRecord>(_ record: Record) {
        // No second fallible Keychain read after the verified original-row commit.
        expectedStoredValue = record.storedCredential
        loadedText = text
        loaded = true
        edited = false
    }

    enum Publication: Equatable {
        case updated, needsRetry
    }

    @MainActor
    mutating func saveAndPublish(
        to record: APIKeys, in context: ModelContext,
        credentials: HanlinAppProviderCredentials = .shared,
        update: (APIKeys) -> Void = { _ in },
        publishCompactConfiguration: () throws -> Void
    ) throws -> Publication {
        try save(to: record, in: context, credentials: credentials, update: update)
        return Self.retryPublication(publishCompactConfiguration)
    }

    @MainActor
    mutating func migrateAndPublish(
        _ record: APIKeys, in context: ModelContext,
        credentials: HanlinAppProviderCredentials = .shared,
        update: (APIKeys) -> Void = { _ in },
        publishCompactConfiguration: () throws -> Void
    ) throws -> Publication {
        try migrate(record, in: context, credentials: credentials, update: update)
        return Self.retryPublication(publishCompactConfiguration)
    }

    /// Deliberately has no credential/context mutation argument: retry the file
    /// publication after a successful original-row commit, never save the key again.
    @MainActor
    static func retryPublication(_ publishCompactConfiguration: () throws -> Void) -> Publication {
        do {
            try publishCompactConfiguration()
            return .updated
        } catch {
            return .needsRetry
        }
    }
}
