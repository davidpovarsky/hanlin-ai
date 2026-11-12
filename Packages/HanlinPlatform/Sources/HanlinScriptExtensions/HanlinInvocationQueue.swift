import Foundation
import HanlinPlatformContracts
#if canImport(Darwin)
import Darwin
#endif

extension HanlinScriptExtensionStore {
    // Explicit ingress/result budgets; attachments belong in owned artifact
    // storage. Rejection is visible and never truncates an accepted value.
    private static let maximumCommandBytes = 256 * 1_024
    private static let maximumReceiptBytes = 4 * 1_024 * 1_024

    public func enqueue(_ command: HanlinScriptResumeCommand) throws {
        try withLock {
            try validateCommand(command)
            if let existing = try readCommand(command.id) {
                guard try Self.encoded(existing.command) == Self.encoded(command) else {
                    throw HanlinInvocationQueueError.duplicateIdentity
                }
                return // A repeated delivery cannot clear a lease or receipt.
            }
            let active = try commandURLs().reduce(0) { count, url in
                count + ((try readCommandURL(url)).currentReceipt.status.isTerminal ? 0 : 1)
            }
            guard active < 128 else { throw HanlinInvocationQueueError.queueFull }
            try writeCommand(.init(command))
        }
    }

    public func pendingCommands(limit: Int = 64) throws -> [HanlinScriptResumeCommand] {
        try withLock {
            try commandURLs().map { try readCommandURL($0) }
                .filter { !$0.currentReceipt.status.isTerminal }
                .map(\.command).sorted {
                    $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
                }.prefix(max(0, limit)).map { $0 }
        }
    }

    public func receipt(for invocationID: UUID) throws -> HanlinInvocationReceipt? {
        try withLock { try readCommand(invocationID)?.currentReceipt }
    }

    /// Claim and completion use the same per-ID record and existing App Group
    /// transaction lock. A stale process cannot overwrite a new owner's result.
    public func claim(_ invocationID: UUID, now: Date = .now, leaseSeconds: TimeInterval = 30,
                      registeredActionIsIdempotent: Bool = false) throws -> HanlinInvocationClaim? {
        try withLock {
            guard leaseSeconds.isFinite, (1...60).contains(leaseSeconds) else { throw HanlinInvocationQueueError.invalidEnvelope }
            guard var record = try readCommand(invocationID) else { throw HanlinInvocationQueueError.missingCommand }
            var receipt = record.currentReceipt
            guard !receipt.status.isTerminal else { return nil }
            let expiresAt = record.invocation.delivery?.expiresAt ?? record.createdAt.addingTimeInterval(86_400)
            if receipt.status == .running {
                guard let expiry = receipt.leaseExpiresAt, expiry <= now else { return nil }
                // Loss of a process does not prove its side effect did not run.
                guard registeredActionIsIdempotent, record.invocation.delivery?.idempotent == true else {
                    receipt.status = .deferred; receipt.failure = .interruptedOutcomeUnknown
                    receipt.updatedAt = now; receipt.leaseID = nil; receipt.leaseExpiresAt = nil
                    record.receipt = receipt; try writeCommand(record); return nil
                }
            }
            if receipt.cancellationRequested || expiresAt <= now {
                receipt.status = receipt.cancellationRequested ? .cancelled : .expired
                receipt.updatedAt = now; receipt.leaseID = nil; receipt.leaseExpiresAt = nil
                record.receipt = receipt; try writeCommand(record); return nil
            }
            let maximumAttempts = record.invocation.delivery?.maximumAttempts ?? 1
            guard receipt.attempt < maximumAttempts else {
                receipt.status = .failed; receipt.failure = .attemptsExhausted; receipt.updatedAt = now
                receipt.leaseID = nil; receipt.leaseExpiresAt = nil
                record.receipt = receipt; try writeCommand(record); return nil
            }
            let token = UUID()
            receipt.status = .running; receipt.attempt += 1; receipt.updatedAt = now
            receipt.leaseID = token; receipt.leaseExpiresAt = min(expiresAt, now.addingTimeInterval(leaseSeconds))
            record.receipt = receipt; try writeCommand(record)
            return .init(command: record.command, leaseID: token)
        }
    }

    public func renew(_ claim: HanlinInvocationClaim, now: Date = .now, leaseSeconds: TimeInterval = 30) throws {
        try withLock {
            guard leaseSeconds.isFinite, (1...60).contains(leaseSeconds) else { throw HanlinInvocationQueueError.invalidEnvelope }
            var record = try ownedRecord(claim, now: now)
            let expiresAt = record.invocation.delivery?.expiresAt ?? record.createdAt.addingTimeInterval(86_400)
            guard expiresAt > now else { throw HanlinInvocationQueueError.staleLease }
            record.receipt?.leaseExpiresAt = min(expiresAt, now.addingTimeInterval(leaseSeconds))
            record.receipt?.updatedAt = now
            try writeCommand(record)
        }
    }

    public func complete(_ claim: HanlinInvocationClaim, status: HanlinInvocationReceipt.Status,
                         value: HanlinValue? = nil, failure: HanlinInvocationReceipt.Failure? = nil,
                         now: Date = .now) throws {
        guard status.isTerminal, status != .acknowledged, status != .succeeded || failure == nil else { throw HanlinInvocationQueueError.invalidTransition }
        // Validate the original canonical value with its real depth/size limits.
        if let value { _ = try value.canonicalJSONData(limits: .init(maximumPayloadBytes: Self.maximumReceiptBytes)) }
        try withLock {
            // Completion may follow cooperative cancellation/draining after a
            // deadline. The token still fences out any replacement owner.
            var record = try ownedRecord(claim, now: now, requireLiveLease: false)
            record.receipt?.status = status; record.receipt?.value = value; record.receipt?.failure = failure
            record.receipt?.updatedAt = now; record.receipt?.leaseID = nil; record.receipt?.leaseExpiresAt = nil
            try writeCommand(record)
        }
    }

    /// Running cancellation is a request, not a fabricated terminal result.
    /// The executor must cancel its actual work and publish its real outcome.
    @discardableResult
    public func requestCancellation(_ invocationID: UUID, now: Date = .now) throws -> HanlinInvocationReceipt {
        try withLock {
            guard var record = try readCommand(invocationID) else { throw HanlinInvocationQueueError.missingCommand }
            var receipt = record.currentReceipt
            if !receipt.status.isTerminal {
                receipt.cancellationRequested = true; receipt.updatedAt = now
                if receipt.status == .queued { receipt.status = .cancelled }
                record.receipt = receipt; try writeCommand(record)
            }
            return receipt
        }
    }

    /// Legacy UI acknowledgement records only that fact, never success.
    public func acknowledge(_ commandID: UUID) throws {
        try withLock {
            guard var record = try readCommand(commandID) else { return }
            guard record.currentReceipt.status == .queued else { throw HanlinInvocationQueueError.invalidTransition }
            record.receipt = record.currentReceipt
            record.receipt?.status = .acknowledged; record.receipt?.updatedAt = .now
            try writeCommand(record)
        }
    }

    private func ownedRecord(_ claim: HanlinInvocationClaim, now: Date, requireLiveLease: Bool = true) throws -> HanlinInvocationRecord {
        guard let record = try readCommand(claim.command.id), record.currentReceipt.status == .running,
              record.currentReceipt.leaseID == claim.leaseID,
              let expiry = record.currentReceipt.leaseExpiresAt, !requireLiveLease || expiry > now else {
            throw HanlinInvocationQueueError.staleLease
        }
        return record
    }

    private func validateCommand(_ command: HanlinScriptResumeCommand) throws {
        guard command.createdAt.timeIntervalSince1970.isFinite,
              try Self.encoded(command).count <= Self.maximumCommandBytes else { throw HanlinInvocationQueueError.invalidEnvelope }
        _ = try command.invocation.parameters.canonicalJSONData(limits: .init(maximumPayloadBytes: Self.maximumCommandBytes))
        if let delivery = command.invocation.delivery {
            guard delivery.schemaVersion == 1, delivery.expiresAt.timeIntervalSince1970.isFinite,
                  delivery.expiresAt > command.createdAt,
                  delivery.expiresAt.timeIntervalSince(command.createdAt) <= 86_400,
                  (1...16).contains(delivery.maximumAttempts),
                  delivery.idempotent || delivery.maximumAttempts == 1,
                  let action = command.invocation.entityID, (try? HanlinActionID(validating: action)) != nil else {
                throw HanlinInvocationQueueError.invalidEnvelope
            }
        }
    }

    private func commandURL(_ id: UUID) -> URL { commandRoot.appending(path: "\(id.uuidString.lowercased()).json") }
    private var receiptRoot: URL { commandRoot.appending(path: "Receipts", directoryHint: .isDirectory) }
    private func receiptURL(_ id: UUID) -> URL { receiptRoot.appending(path: "\(id.uuidString.lowercased()).json") }

    private func commandURLs() throws -> [URL] {
        try rejectSymlinks(to: commandRoot, phase: .actionPerform)
        guard FileManager.default.fileExists(atPath: commandRoot.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: commandRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
    }

    private func readCommand(_ id: UUID) throws -> HanlinInvocationRecord? {
        let completed = receiptURL(id)
        try rejectSymlinks(to: completed, phase: .actionPerform)
        if FileManager.default.fileExists(atPath: completed.path(percentEncoded: false)) { return try readCommandURL(completed) }
        let url = commandURL(id)
        try rejectSymlinks(to: url, phase: .actionPerform)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try readCommandURL(url)
    }

    private func readCommandURL(_ url: URL) throws -> HanlinInvocationRecord {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw HanlinInvocationQueueError.invalidEnvelope }
        try rejectSymlinks(to: url, phase: .actionPerform)
#if canImport(Darwin)
        let fd = Darwin.open(url.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw HanlinScriptExtensionStoreError.invalidArtifactReference }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= Self.maximumReceiptBytes + Self.maximumCommandBytes, info.st_nlink == 1 else {
            throw HanlinInvocationQueueError.invalidEnvelope
        }
        let data = try handle.read(upToCount: Self.maximumReceiptBytes + Self.maximumCommandBytes + 1) ?? Data()
#else
        throw HanlinScriptExtensionStoreError.appGroupUnavailable
#endif
#if canImport(Darwin)
        guard data.count <= Self.maximumReceiptBytes + Self.maximumCommandBytes else { throw HanlinInvocationQueueError.invalidEnvelope }
        let record = try Self.decoded(HanlinInvocationRecord.self, from: data)
        guard record.id == id, record.deliverySchemaVersion == nil || record.deliverySchemaVersion == 1,
              record.deliverySchemaVersion == nil || record.receipt != nil,
              record.receipt == nil || record.receipt?.invocationID == id else { throw HanlinInvocationQueueError.invalidEnvelope }
        if let receipt = record.receipt {
            guard (0...16).contains(receipt.attempt), receipt.updatedAt.timeIntervalSince1970.isFinite,
                  receipt.status != .succeeded || receipt.failure == nil,
                  receipt.status != .running || (receipt.leaseID != nil && receipt.leaseExpiresAt != nil),
                  !receipt.status.isTerminal || (receipt.leaseID == nil && receipt.leaseExpiresAt == nil) else {
                throw HanlinInvocationQueueError.invalidEnvelope
            }
        }
        try validateCommand(record.command)
        return record
#endif
    }

    private func writeCommand(_ record: HanlinInvocationRecord) throws {
        try rejectSymlinks(to: commandRoot, phase: .actionPerform)
        try FileManager.default.createDirectory(at: commandRoot, withIntermediateDirectories: true)
        try rejectSymlinks(to: commandRoot, phase: .actionPerform)
        let url = commandURL(record.id)
        try rejectSymlinks(to: url, phase: .actionPerform)
        let data = try Self.encoded(record)
        guard data.count <= Self.maximumReceiptBytes + Self.maximumCommandBytes else { throw HanlinInvocationQueueError.invalidEnvelope }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if record.currentReceipt.status.isTerminal {
            try rejectSymlinks(to: receiptRoot, phase: .actionPerform)
            try FileManager.default.createDirectory(at: receiptRoot, withIntermediateDirectories: true)
            try rejectSymlinks(to: receiptRoot, phase: .actionPerform)
            let destination = receiptURL(record.id)
            try rejectSymlinks(to: destination, phase: .actionPerform)
#if canImport(Darwin)
            guard Darwin.rename(url.path(percentEncoded: false), destination.path(percentEncoded: false)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
#else
            throw HanlinScriptExtensionStoreError.appGroupUnavailable
#endif
        }
    }
}
