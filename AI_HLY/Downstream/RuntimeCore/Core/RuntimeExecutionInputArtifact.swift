import CryptoKit
import Foundation

/// A transport threshold, not a workload limit. Large requests become owned
/// disk inputs; the original authenticated POST remains a small control packet.
struct RuntimeExecutionInputArtifact: Sendable {
    static let maximumInlineBytes = 1_048_576
    let controlBody: Data
    let file: URL?

    init(body: Data, executionID: UUID, layout: RuntimeFileLayout, traceWarnings: Bool = false) throws {
        guard body.count > Self.maximumInlineBytes else {
            controlBody = body
            file = nil
            return
        }
        let proposed = layout.nodeRuntime.appending(path: "requests", directoryHint: .isDirectory)
        let inbox = try layout.validatedDescendant(proposed, of: layout.nodeRuntime)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let target = inbox.appending(path: executionID.uuidString.lowercased() + ".json")
        // Never replace another submission, even one that has not reached HTTP.
        // A failed write is retained rather than deleting an uncertain owner.
        try body.write(to: target, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let sha256 = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        var envelope: [String: Any] = ["executionID": executionID.uuidString.lowercased(), "detached": true,
                                     "inputArtifact": ["bytes": body.count, "sha256": sha256]]
        if traceWarnings { envelope["environment"] = ["HANLIN_NODE_TRACE_WARNINGS": "1"] }
        controlBody = try JSONSerialization.data(withJSONObject: envelope)
        file = target
    }

    /// Only the submitting owner may discard an input before attempting POST.
    /// After an ambiguous request the Host/journal owns observation and recovery.
    func discardBeforeSubmission() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
