import Foundation
import Testing

@MainActor
@Suite struct MiniAppsBootstrapTests {
    @Test func failureIsVisibleAndRetryReexecutesPreparation() async {
        var attempts = 0
        let bootstrap = HanlinMiniAppsBootstrap {
            attempts += 1
            if attempts == 1 {
                throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue,
                              userInfo: [NSFilePathErrorKey: "PRIVATE_PATH_CANARY"])
            }
        }
        await bootstrap.prepare()
        #expect(bootstrap.phase == .failed(.init(NSError(domain: NSCocoaErrorDomain,
                                                        code: CocoaError.fileWriteNoPermission.rawValue))))
        #expect(!String(describing: bootstrap.phase).contains("PRIVATE_PATH_CANARY"))
        await bootstrap.prepare()
        #expect(bootstrap.phase == .ready)
        #expect(attempts == 2)
    }

    @Test func concurrentPreparationDoesNotDuplicateTheBoundary() async {
        let (entered, signalEntry) = AsyncStream<Void>.makeStream()
        let (release, signalRelease) = AsyncStream<Void>.makeStream()
        var attempts = 0
        let bootstrap = HanlinMiniAppsBootstrap {
            attempts += 1
            signalEntry.yield(())
            var iterator = release.makeAsyncIterator()
            _ = await iterator.next()
        }
        let first = Task { await bootstrap.prepare() }
        var entry = entered.makeAsyncIterator()
        _ = await entry.next()
        await bootstrap.prepare()
        #expect(bootstrap.phase == .preparing)
        #expect(attempts == 1)
        signalRelease.yield(())
        await first.value
        #expect(bootstrap.phase == .ready)
        signalEntry.finish()
        signalRelease.finish()
    }

    @Test func successfulPreparationIsNotRepeated() async {
        var attempts = 0
        let bootstrap = HanlinMiniAppsBootstrap { attempts += 1 }
        await bootstrap.prepare()
        await bootstrap.prepare()
        #expect(bootstrap.phase == .ready)
        #expect(attempts == 1)
    }
}
