import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public protocol TextStudioStorage {
    func persistentString(forKey key: String) -> String?
    func setPersistentString(_ value: String, forKey key: String)
    func persistentData(forKey key: String) -> Data?
    func setPersistentData(_ value: Data, forKey key: String)
    func removePersistentValue(forKey key: String)
}

@MainActor
public final class UserDefaultsTextStudioStorage: TextStudioStorage {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func persistentString(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func setPersistentString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func persistentData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func setPersistentData(_ value: Data, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func removePersistentValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
public protocol TextStudioPasteboard {
    func readString() -> String?
    func writeString(_ string: String)
}

@MainActor
public struct StandardTextStudioPasteboard: TextStudioPasteboard {
    public init() {}

    public func readString() -> String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }

    public func writeString(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
