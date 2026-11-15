import Foundation
import Observation

/// The single preparation boundary gates creation of the live provider. Tests
/// may inject this boundary; they do not replace any provider or runtime output.
@MainActor
@Observable
final class HanlinMiniAppsBootstrap {
    struct Failure: Equatable {
        let domain: String
        let code: Int

        init(_ error: any Error) {
            let error = error as NSError
            domain = [NSCocoaErrorDomain, NSPOSIXErrorDomain].contains(error.domain) ? error.domain : "StorageError"
            code = error.code
        }
    }

    enum Phase: Equatable {
        case idle, preparing, ready, failed(Failure)
    }

    private(set) var phase: Phase = .idle
    private let preparation: @MainActor () async throws -> Void

    init(preparation: @escaping @MainActor () async throws -> Void) {
        self.preparation = preparation
    }

    func prepare() async {
        switch phase {
        case .preparing, .ready: return
        case .idle, .failed: break
        }
        phase = .preparing
        do {
            try await preparation()
            phase = .ready
        } catch {
            // Retain actual system identity, never a path/payload/error message.
            phase = .failed(Failure(error))
        }
    }
}
