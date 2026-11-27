import Foundation

/// Counts UTF8 bytes in original renderer-issued HTML/CSS/display HTML while
/// any payload copy owns them. This is not a WebKit/RSS or transient-JS metric.
/// One quota covers all engine instances, cached and inline/expanded payloads.
/// The existing serialized work queue independently bounds pending input and
/// one in-flight render; no completed result is published without this lease.
final class ChatCodeFencePayloadRetention: @unchecked Sendable {
    static let shared = ChatCodeFencePayloadRetention(maximumBytes: 48 * 1_048_576, maximumPayloads: 64)

    struct Snapshot: Equatable, Sendable {
        let bytes: Int
        let payloads: Int
    }

    final class Lease: Sendable {
        let owner: ChatCodeFencePayloadRetention
        let bytes: Int
        fileprivate init(owner: ChatCodeFencePayloadRetention, bytes: Int) {
            self.owner = owner; self.bytes = bytes
        }
        deinit { owner.release(bytes: bytes) }
    }

    private let lock = NSLock()
    private let maximumBytes: Int
    private let maximumPayloads: Int
    private var retainedBytes = 0
    private var retainedPayloads = 0

    init(maximumBytes: Int, maximumPayloads: Int) {
        precondition(maximumBytes > 0 && maximumPayloads > 0)
        self.maximumBytes = maximumBytes; self.maximumPayloads = maximumPayloads
    }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(bytes: retainedBytes, payloads: retainedPayloads)
    }

    func acquire(bytes: Int) -> Lease? {
        lock.lock(); defer { lock.unlock() }
        guard bytes > 0, bytes <= maximumBytes, retainedPayloads < maximumPayloads,
              retainedBytes <= maximumBytes - bytes else { return nil }
        retainedBytes += bytes; retainedPayloads += 1
        return Lease(owner: self, bytes: bytes)
    }

    private func release(bytes: Int) {
        lock.lock(); defer { lock.unlock() }
        precondition(retainedPayloads > 0 && retainedBytes >= bytes)
        retainedBytes -= bytes; retainedPayloads -= 1
    }
}
