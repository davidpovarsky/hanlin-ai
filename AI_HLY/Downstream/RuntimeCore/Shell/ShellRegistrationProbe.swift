import Foundation
import IOSSystemLite

#if targetEnvironment(simulator)
enum ShellRegistrationProbe {
    static let resultFileName = "shell-registration-pre-repair.json"

    static func run(fileLayout: RuntimeFileLayout = .default) {
        do {
            try fileLayout.prepareIfNeeded()
            let report = IOSSystemRunner.legacyRegistrationProbe()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try data.write(to: fileLayout.logs.appending(path: resultFileName), options: .atomic)
        } catch {
            let fallback: [String: String] = [
                "probeError": error.localizedDescription
            ]
            if let data = try? JSONSerialization.data(withJSONObject: fallback, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: fileLayout.logs.appending(path: resultFileName), options: .atomic)
            }
        }
    }
}
#endif
