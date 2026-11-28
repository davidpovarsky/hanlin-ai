import Foundation

/// Compatibility of prepared, already-bundled runtime metadata. This is not
/// npm range resolution; actual dependency versions still come from the lock.
public enum HanlinPreparedRuntimeVersion {
    /// A JavaScript package built for an older patch can use the same major/minor
    /// native runtime. This does not relax the exact embedded native-plugin versions.
    public static func supportsCompatiblePatch(_ declared: String, installed: String) -> Bool {
        guard let required = HanlinPackageVersion(rawValue: declared.trimmingCharacters(in: .whitespacesAndNewlines)),
              let actual = HanlinPackageVersion(rawValue: installed),
              required.major > 0, actual.major == required.major, actual.minor == required.minor,
              required.prerelease.isEmpty, actual.prerelease.isEmpty else { return false }
        return actual.patch >= required.patch
    }

    public static func supportsMinimum(_ declared: String, installed: String, requireSameMajor: Bool = true) -> Bool {
        var value = declared.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = value.first, ["^", "~", "=", "v"].contains(first) { value.removeFirst() }
        guard let required = HanlinPackageVersion(rawValue: value), required.major > 0, required.prerelease.isEmpty,
              let actual = HanlinPackageVersion(rawValue: installed), actual.major > 0, actual.prerelease.isEmpty,
              !requireSameMajor || required.major == actual.major else { return false }
        // Build metadata labels identify builds; they do not raise a required
        // runtime API version. Do not change the package type's total ordering.
        return (required.major, required.minor, required.patch) <= (actual.major, actual.minor, actual.patch)
    }
}
