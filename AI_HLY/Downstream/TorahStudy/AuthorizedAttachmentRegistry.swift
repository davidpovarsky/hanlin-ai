import Foundation
import HanlinPlatformContracts
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
public actor AuthorizedAttachmentRegistry {
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
    }

    private var records: [String: Record] = [:]
    private let maxRecords = 500

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
    ) -> String {
        cleanExpired()
        if records.count >= maxRecords {
            if let oldest = records.values.min(by: { $0.createdAt < $1.createdAt }) {
                records.removeValue(forKey: oldest.handle)
            }
        }

        let randomHex = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let randomSuffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let handle = "att_\(randomHex)\(randomSuffix)"

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

    /// Resolves image data strictly scoped to the requesting chat identity.
    /// Throws explicit errors on access violation, expiration, or invalid handle format.
    public func resolve(
        handle: String,
        chatID: String,
        requestID: String? = nil
    ) throws -> Data {
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

        guard let record = records[handle] else {
            throw HanlinHostServiceError.invalidRequest("Attachment handle '\(handle)' not found or expired.")
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

        guard record.data.count <= 20 * 1024 * 1024 else {
            throw HanlinHostServiceError.invalidRequest("Attachment exceeds maximum allowed image size of 20MB.")
        }

        // Verify image decodability
        guard Self.isValidImageData(record.data) else {
            throw HanlinHostServiceError.invalidRequest("Attachment handle '\(handle)' contains invalid or undecodable image data.")
        }

        return record.data
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
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
        #elseif canImport(UIKit)
        return UIImage(data: data) != nil
        #else
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
        #endif
    }
}
