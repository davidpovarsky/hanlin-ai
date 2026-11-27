import Foundation
import HanlinPlatformContracts
import Testing
@testable import HanlinMiniAppCore

@Test
func cancelledNativeActionDoesNotStartOrAcceptALateSuccess() async {
    let completion = HanlinMiniAppActionCompletion()
    completion.resolve(.failure(CancellationError()))
    await #expect(throws: CancellationError.self) {
        try await withCheckedThrowingContinuation { continuation in
            #expect(!completion.install(continuation))
            completion.resolve(.success(.integer(42)))
        }
    }
}

@Test
func nativeActionIgnoresDuplicateCallbacksAndLateCancellation() async throws {
    let completion = HanlinMiniAppActionCompletion()
    let result = try await withCheckedThrowingContinuation { continuation in
        #expect(completion.install(continuation))
        completion.resolve(.success(.string("שלום")))
        completion.resolve(.success(.integer(42)))
        completion.resolve(.failure(CancellationError()))
    }
    #expect(result == .string("שלום"))
}

@Test
func waitingNativeActionResolvesOnCancellation() async {
    let completion = HanlinMiniAppActionCompletion()
    await #expect(throws: CancellationError.self) {
        try await withCheckedThrowingContinuation { continuation in
            #expect(completion.install(continuation))
            completion.resolve(.failure(CancellationError()))
            completion.resolve(.success(.null))
        }
    }
}
