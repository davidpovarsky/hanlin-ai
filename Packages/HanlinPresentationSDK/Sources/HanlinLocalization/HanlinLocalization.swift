import Foundation

/// The original Hanlin translation tables and shared visual resources have one owner.
/// A host's bundle and localization tables never shadow the SDK's original labels.
public enum HanlinLocalization {
    public static var bundle: Bundle { .module }
}
