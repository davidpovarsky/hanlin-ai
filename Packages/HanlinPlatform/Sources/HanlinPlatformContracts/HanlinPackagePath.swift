import Foundation

/// Package-relative path rules shared by archive import and native presentation compilation.
public enum HanlinPackagePath {
    public static func normalizedRelativePath(_ value: String) -> String? {
        var path = value.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        if path.hasSuffix("/") {
            path.removeLast()
        }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0"),
              !hasDrivePrefix(path)
        else {
            return nil
        }
        let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false)
        var stack: [String] = []
        for component in rawComponents {
            if component.isEmpty {
                return nil
            }
            if component == "." {
                continue
            }
            if component == ".." {
                guard !stack.isEmpty else {
                    return nil
                }
                stack.removeLast()
            } else {
                stack.append(String(component))
            }
        }
        guard !stack.isEmpty else { return nil }
        return stack.joined(separator: "/").precomposedStringWithCanonicalMapping
    }

    public static func hasDrivePrefix(_ path: String) -> Bool {
        let scalars = Array(path.unicodeScalars.prefix(3))
        guard scalars.count >= 2 else { return false }
        return CharacterSet.letters.contains(scalars[0]) && scalars[1].value == 58
    }
}
