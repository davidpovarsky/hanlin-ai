import Foundation

enum RuntimePolicy {
    static func validateEnvironmentName(_ name: String) throws -> String {
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
            throw RuntimeCoreError.invalidEnvironmentName
        }
        return name
    }

    static func validatedEnvironment(_ values: [String: String]) throws -> [String: String] {
        for (name, value) in values {
            _ = try validateEnvironmentName(name)
            guard !value.contains("\0") else {
                throw RuntimeCoreError.invalidRequest("Environment values cannot contain a NUL byte.")
            }
        }
        return values
    }

    static func validateRemoteArchiveURL(_ url: URL, requiredExtension: String? = nil) throws -> URL {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw RuntimeCoreError.invalidPath
        }
        if let requiredExtension,
           url.pathExtension.lowercased() != requiredExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
            throw RuntimeCoreError.invalidPath
        }
        return url
    }

    static func systemEnvironment(workspace: URL, cache: URL, prefix: URL, temporary: URL) -> [String: String] {
        [
            "HOME": workspace.path,
            "USERPROFILE": workspace.path,
            "TMPDIR": temporary.path,
            "TMP": temporary.path,
            "TEMP": temporary.path,
            "XDG_CACHE_HOME": cache.path,
            "npm_config_cache": cache.path,
            "NPM_CONFIG_CACHE": cache.path,
            "npm_config_prefix": prefix.path,
            "NPM_CONFIG_PREFIX": prefix.path
        ]
    }
}
