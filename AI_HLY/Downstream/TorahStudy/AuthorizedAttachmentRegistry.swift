import Foundation
import HanlinPlatformContracts
import HanlinHostContracts
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

/// Authoritative in-memory registry for authorized chat image attachments.
/// Guarantees that attachment handles are unguessable, scoped to a specific chat,
/// expire with time-to-live, and cannot be accessed across different conversations.
public actor AuthorizedAttachmentRegistry: HanlinAttachmentStore {
    public static let shared = AuthorizedAttachmentRegistry()

    public struct Record: Sendable {
        public let handle: String
        public let chatID: String
        public let requestID: String
        public let data: Data
        public let mimeType: String
        public let createdAt: Date
        public let expiresAt: Date
        public var isRevoked: Bool
        fileprivate var hostSession: HanlinHostSession? = nil
    }

    private var records: [String: Record] = [:]
    private let maxRecords = 500
    private let maxTotalBytes = 50 * 1024 * 1024 // 50 MiB total in-memory budget
    private let allowedMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/heic", "image/webp", "image/gif"
    ]

    public init() {}

    /// Registers authentic image data for a specific chat and request turn.
    /// Returns an unguessable opaque attachment handle.
    @discardableResult
    public func register(
        data: Data,
        mimeType: String = "image/jpeg",
        chatID: String,
        requestID: String,
        ttl: TimeInterval = 3600
    ) throws -> String {
        guard !chatID.isEmpty, chatID != "default_chat" else {
            throw HanlinHostServiceError.invalidRequest("Registration requires an authentic, non-default chat ID.")
        }
        guard !requestID.isEmpty, requestID != "default_request" else {
            throw HanlinHostServiceError.invalidRequest("Registration requires an authentic, non-default request ID.")
        }
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else {
            throw HanlinHostServiceError.invalidRequest("Image attachment exceeds maximum allowed size of 20MB.")
        }
        guard allowedMIMETypes.contains(mimeType.lowercased()) else {
            throw HanlinHostServiceError.invalidRequest("MIME type '\(mimeType)' is not permitted for image attachments.")
        }
        guard Self.isValidImageData(data) else {
            throw HanlinHostServiceError.invalidRequest("Attachment data is corrupted or undecodable as an image.")
        }
        guard ttl > 0 && ttl <= 86400 else {
            throw HanlinHostServiceError.invalidRequest("TTL must be positive and not exceed 24 hours.")
        }

        cleanExpired()

        // Enforce total byte budget & count limits by evicting oldest
        var currentBytes = records.values.reduce(0) { $0 + $1.data.count }
        while (records.count >= maxRecords || currentBytes + data.count > maxTotalBytes),
              let oldest = records.values.min(by: { $0.createdAt < $1.createdAt }) {
            currentBytes -= oldest.data.count
            records.removeValue(forKey: oldest.handle)
        }

        let fullUUID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let handle = "att_\(fullUUID)"

        let now = Date()
        let record = Record(
            handle: handle,
            chatID: chatID,
            requestID: requestID,
            data: data,
            mimeType: mimeType,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ttl),
            isRevoked: false
        )
        records[handle] = record
        return handle
    }

    /// Resolves image data strictly scoped to the requesting chat and request turn.
    /// Throws explicit errors on access violation, expiration, or invalid handle format.
    public func resolve(
        handle: String,
        chatID: String,
        requestID: String? = nil
    ) throws -> Data {
        try resolve(handle: handle, chatID: chatID, requestID: requestID, hostSession: nil)
    }

    private func resolve(handle: String, chatID: String, requestID: String?,
                         hostSession: HanlinHostSession?) throws -> Data {
        cleanExpired()

        // Strict syntactic rejection of directory traversal, absolute paths, URLs, null bytes
        guard !handle.isEmpty,
              !handle.hasPrefix("/"),
              !handle.contains("/"),
              !handle.contains("\\"),
              !handle.contains(".."),
              !handle.contains(":"),
              !handle.contains("\0") else {
            throw HanlinHostServiceError.invalidRequest("Invalid attachment handle: traversal, URLs, and separators are prohibited.")
        }

        guard !chatID.isEmpty, chatID != "default_chat" else {
            throw HanlinHostServiceError.capabilityNotGranted("Access denied: Attachment resolution requires an authentic chat scope.")
        }

        guard let record = records[handle] else {
            throw HanlinHostServiceError.invalidRequest("Attachment handle '\(handle)' not found or expired.")
        }

        if let bound = record.hostSession, bound != hostSession {
            throw HanlinHostError.staleContext
        }

        guard !record.isRevoked else {
            throw HanlinHostServiceError.invalidRequest("Attachment handle '\(handle)' has been revoked.")
        }

        guard record.expiresAt > Date() else {
            records.removeValue(forKey: handle)
            throw HanlinHostServiceError.invalidRequest("Attachment handle '\(handle)' has expired.")
        }

        guard record.chatID == chatID else {
            throw HanlinHostServiceError.capabilityNotGranted("Access denied: Attachment handle '\(handle)' belongs to another chat session.")
        }

        if let requestID, !requestID.isEmpty, requestID != "default_request" {
            guard record.requestID == requestID else {
                throw HanlinHostServiceError.capabilityNotGranted("Access denied: Attachment handle '\(handle)' belongs to another request turn.")
            }
        }

        guard record.data.count <= 20 * 1024 * 1024 else {
            throw HanlinHostServiceError.invalidRequest("Attachment exceeds maximum allowed image size of 20MB.")
        }

        // Verify image decodability
        guard Self.isValidImageData(record.data) else {
            throw HanlinHostServiceError.invalidRequest("Attachment handle '\(handle)' contains invalid or undecodable image data.")
        }

        return record.data
    }

    /// Adopt an already registered original-turn image without copying or registering its
    /// bytes again. Only the real HostSession plus the exact original turn can bind it.
    public func reference(forLegacyHandle handle: String, session: HanlinHostSession,
                          requestID: String) throws -> HanlinAttachmentReference {
        guard !requestID.isEmpty, requestID != "default_request",
              let uuid = Self.uuid(for: handle) else { throw HanlinHostError.invalidArguments }
        _ = try resolve(handle: handle, chatID: session.conversationID.uuidString,
            requestID: requestID, hostSession: session)
        guard var record = records[handle] else { throw HanlinHostError.staleContext }
        record.hostSession = session
        records[handle] = record
        return .init(handle: uuid, namespace: session.context.namespace,
            mediaType: record.mimeType, byteCount: record.data.count)
    }

    public func importData(_ data: Data, mediaType: String,
                           session: HanlinHostSession) throws -> HanlinAttachmentReference {
        let handle = try register(data: data, mimeType: mediaType, chatID: session.conversationID.uuidString,
            requestID: session.id.uuidString)
        return try reference(forLegacyHandle: handle, session: session, requestID: session.id.uuidString)
    }

    public func read(_ reference: HanlinAttachmentReference, session: HanlinHostSession) throws -> Data {
        guard reference.namespace == session.context.namespace else { throw HanlinHostError.staleContext }
        let handle = Self.handle(for: reference.handle)
        guard let record = records[handle], record.hostSession == session,
              record.mimeType == reference.mediaType, record.data.count == reference.byteCount else {
            throw HanlinHostError.staleContext
        }
        return try resolve(handle: handle, chatID: session.conversationID.uuidString,
            requestID: record.requestID, hostSession: session)
    }

    public func remove(_ reference: HanlinAttachmentReference, session: HanlinHostSession) throws {
        _ = try read(reference, session: session)
        revoke(handle: Self.handle(for: reference.handle))
    }

    private static func handle(for uuid: UUID) -> String {
        "att_" + uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func uuid(for handle: String) -> UUID? {
        guard handle.hasPrefix("att_"), handle.utf8.count == 36 else { return nil }
        let hex = String(handle.dropFirst(4))
        guard hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        let chars = Array(hex)
        let uuid = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-"
            + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: uuid)
    }

    public func revoke(handle: String) {
        records[handle]?.isRevoked = true
    }

    public func clearChat(chatID: String) {
        records = records.filter { $0.value.chatID != chatID }
    }

    public func clearAll() {
        records.removeAll()
    }

    private func cleanExpired() {
        let now = Date()
        records = records.filter { $0.value.expiresAt > now && !$0.value.isRevoked }
    }

    public static func isValidImageData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        #if canImport(ImageIO)
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 0 {
            return true
        }
        #endif
        #if canImport(UIKit)
        if UIImage(data: data) != nil {
            return true
        }
        #endif
        // Fallback magic byte detection for JPEG, PNG, HEIC, GIF, WebP
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return true } // JPEG
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true } // PNG
        if data.starts(with: [0x47, 0x49, 0x46]) { return true } // GIF
        if data.count >= 12,
           let str = String(data: data[4..<12], encoding: .ascii),
           str.contains("ftyp") { return true } // HEIC/MP4/AVIF
        if data.count >= 12,
           data.starts(with: [0x52, 0x49, 0x46, 0x46]) { return true } // RIFF/WebP
        return false
    }
}
