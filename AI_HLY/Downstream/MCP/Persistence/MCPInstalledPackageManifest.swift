import Foundation

struct MCPInstalledPackageManifest: Codable, Hashable, Sendable {
    var packageName: String
    var requestedVersion: String?
    var resolvedVersion: String
    var integrity: String?
    var entryPoint: String
    var binName: String?
    var installedAt: Date
    var dependencyCount: Int
}
