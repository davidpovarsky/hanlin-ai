import Foundation
import ZIPFoundation

/// The containing application already links original ZIPFoundation. These two
/// native archive operations adapt the original ScriptWidget importer/exporter
/// to that dependency; no JS provider or source parser is replaced.
enum SSZipArchive {
    static func createZipFile(atPath path: String, withContentsOfDirectory directory: String, keepParentDirectory: Bool) -> Bool {
        do {
            try FileManager.default.zipItem(at: URL(fileURLWithPath: directory),
                                           to: URL(fileURLWithPath: path),
                                           shouldKeepParent: keepParentDirectory)
            return true
        } catch { return false }
    }
    static func unzipFile(atPath path: String, toDestination destination: String) -> Bool {
        do {
            try FileManager.default.unzipItem(at: URL(fileURLWithPath: path),
                                             to: URL(fileURLWithPath: destination))
            return true
        } catch { return false }
    }
}
