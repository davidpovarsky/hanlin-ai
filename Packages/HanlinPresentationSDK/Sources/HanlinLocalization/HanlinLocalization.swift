import Foundation

/// The original Hanlin translation tables and shared visual resources have one owner.
/// A host's bundle and localization tables never shadow the SDK's original labels.
public enum HanlinLocalization {
    public static var bundle: Bundle { .module }

    #if canImport(Darwin)
    /// Creates an original Hanlin title before deferred localization. Keep
    /// interpolation, the caller's table and locale in the resource itself.
    public static func resource(
        _ keyAndValue: String.LocalizationValue,
        table: String? = nil,
        locale: Locale = .current,
        comment: StaticString? = nil
    ) -> LocalizedStringResource {
        LocalizedStringResource(keyAndValue, table: table, locale: locale,
            bundle: .atURL(bundle.bundleURL), comment: comment)
    }
    #endif
}
