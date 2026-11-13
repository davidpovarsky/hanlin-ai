import Foundation

/// Compatibility of prepared, already-bundled runtime metadata. This is not
/// npm range resolution; actual dependency versions still come from the lock.
public enum HanlinPreparedRuntimeVersion {
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
