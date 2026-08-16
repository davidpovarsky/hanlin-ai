import Foundation
import HanlinPlatformContracts
import IOSSystemLite

#if targetEnvironment(simulator)
struct ShellRuntimeAcceptanceResult: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let passed: Bool
    let snapshot: RuntimeSnapshot
    let registration: IOSSystemRegistrationReport?
    let smoke: ShellRuntimeSmokeReport?
    let canonicalShadow: CanonicalShadowReport?
    let failureCode: String?
    let failureMessage: String?
}

enum ShellRuntimeAcceptance {
    static let resultFileName = "shell-acceptance.json"

    static func run(core: AppRuntimeCore = .shared, fileLayout: RuntimeFileLayout = .default) async {
        let result: ShellRuntimeAcceptanceResult
        do {
            try await core.prepareStorage()
            let smoke = try await core.shell.runSmokeSuite()
            let snapshot = await core.shell.snapshot()
            let registration = try IOSSystemRunner.registrationReport()
            let canonicalShadow = await canonicalShadowReport(snapshot: snapshot)
            result = ShellRuntimeAcceptanceResult(
                schemaVersion: 1,
                generatedAt: .now,
                passed: smoke.passed && snapshot.state == .ready,
                snapshot: snapshot,
                registration: registration,
                smoke: smoke,
                canonicalShadow: canonicalShadow,
                failureCode: smoke.passed ? nil : "smoke_suite_failed",
                failureMessage: smoke.passed ? nil : "One or more shell acceptance checks failed."
            )
        } catch {
            let snapshot = await core.shell.snapshot()
            let canonicalShadow = await canonicalShadowReport(snapshot: snapshot)
            result = ShellRuntimeAcceptanceResult(
                schemaVersion: 1,
                generatedAt: .now,
                passed: false,
                snapshot: snapshot,
                registration: try? IOSSystemRunner.registrationReport(),
                smoke: nil,
                canonicalShadow: canonicalShadow,
                failureCode: (error as? IOSSystemRegistrationError)?.code ?? "acceptance_failed",
                failureMessage: error.localizedDescription
            )
        }

        do {
            try fileLayout.prepareIfNeeded()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(
                to: fileLayout.logs.appending(path: resultFileName),
                options: .atomic
            )
        } catch {
            preconditionFailure("Could not persist shell acceptance result: \(error.localizedDescription)")
        }

        if !result.passed {
            try? await Task.sleep(for: .seconds(5))
            preconditionFailure(result.failureMessage ?? "Shell acceptance failed.")
        }
    }

    private static func canonicalShadowReport(
        snapshot: RuntimeSnapshot
    ) async -> CanonicalShadowReport? {
        await MainActor.run {
            guard HanlinCanonicalShadowCoordinator.isEnabled,
                  let sessionID = try? HanlinRuntimeSessionID(
                    validating: "runtime.acceptance.shell"
                  ),
                  let providerID = try? HanlinProviderInstanceID(
                    validating: "runtime.shell"
                  ) else {
                return nil
            }
            let observedAt = Date()
            return HanlinCanonicalShadowCoordinator.runIfEnabled(
                sources: .init(runtimeCore: [
                    .init(
                        snapshot: snapshot,
                        sessionID: sessionID,
                        providerInstanceID: providerID,
                        createdAt: observedAt,
                        observedAt: observedAt
                    )
                ])
            )
        }
    }
}
#endif
