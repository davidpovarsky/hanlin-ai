import Foundation
import HanlinPlatformContracts

/// Original installed packages project their current skills into the one
/// catalog. Closures recheck enabled state and resolve through the owning store.
@MainActor
public struct HanlinInstalledSkillSource {
    public let descriptor: HanlinSkillDescriptor
    public let packageID: String
    public let instructionLoader: @MainActor @Sendable () async -> String
    public let resourceResolver: @MainActor @Sendable (String) -> URL?

    public init(descriptor: HanlinSkillDescriptor, packageID: String,
                instructionLoader: @escaping @MainActor @Sendable () async -> String,
                resourceResolver: @escaping @MainActor @Sendable (String) -> URL?) {
        self.descriptor = descriptor
        self.packageID = packageID
        self.instructionLoader = instructionLoader
        self.resourceResolver = resourceResolver
    }
}

@MainActor
enum HanlinProductionSkillSources {
    static func current() -> [HanlinInstalledSkillSource] {
        #if HANLIN_ASSISTANT_CAPABILITIES_SDK
        // A component host registers its actual installed-package owner with
        // useInstalledSkillProvider. No Expo runtime is implicitly constructed.
        return []
        #else
        var sources: [HanlinInstalledSkillSource] = []
        let resolvedPlatform = HanlinScriptingPlatform.shared
        for package in resolvedPlatform.installedPackages where package.enabled {
            guard let desc = try? package.appDescriptor() else { continue }
            let packageID = package.record.packageID
            for skill in desc.skills {
                sources.append(HanlinInstalledSkillSource(
                    descriptor: skill,
                    packageID: packageID.rawValue,
                    instructionLoader: { [weak resolvedPlatform] in
                        guard let currentPlatform = resolvedPlatform else {
                            return ""
                        }
                        guard let currentPackage = currentPlatform.installedPackages.first(where: { $0.record.packageID == packageID && $0.enabled }) else {
                            return ""
                        }
                        switch skill.instructions {
                        case .inline(let text):
                            return text
                        case .resource(let path):
                            if let artifactURL = currentPlatform.activeArtifactURL(for: currentPackage) {
                                let candidateURL = artifactURL.appending(path: path)
                                if let content = try? String(contentsOf: candidateURL, encoding: .utf8) {
                                    return content
                                }
                                let sourceCandidate = artifactURL.appending(path: "source/\(path)")
                                if let content = try? String(contentsOf: sourceCandidate, encoding: .utf8) {
                                    return content
                                }
                            }
                            if let resURL = currentPlatform.resolveResourceURL(packageID: packageID, relativePath: path),
                               let content = try? String(contentsOf: resURL, encoding: .utf8) {
                                return content
                            }
                            if let url = HanlinApplicationResources.bundle.url(forResource: path, withExtension: nil),
                               let content = try? String(contentsOf: url, encoding: .utf8) {
                                return content
                            }
                        }
                        return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
                    },
                    resourceResolver: { [weak resolvedPlatform] relPath in
                        guard let currentPlatform = resolvedPlatform else {
                            return nil
                        }
                        guard let currentPackage = currentPlatform.installedPackages.first(where: { $0.record.packageID == packageID && $0.enabled }) else {
                            return nil
                        }
                        let rawTrimmed = relPath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !rawTrimmed.isEmpty, !rawTrimmed.contains("\0"), !rawTrimmed.hasPrefix("/"),
                              let clean = SkillStore.normalizeRelativePath(rawTrimmed) else {
                            return nil
                        }
                        return currentPlatform.resolveResourceURL(packageID: currentPackage.record.packageID, relativePath: clean)
                    }
                ))
            }
        }

        return sources
        #endif
    }
}
