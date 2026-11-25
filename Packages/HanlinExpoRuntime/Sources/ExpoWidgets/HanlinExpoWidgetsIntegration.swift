import Foundation
import CryptoKit
import ExpoModulesCore
import ActivityKit
import WidgetKit

public struct HanlinExpoWidgetDescriptor: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let packageID: String
    public let installedPackageID: String
    public let generation: UInt64
    public let productIdentifier: String
    public let sessionID: String
    public let kind: String
    public let isActive: Bool
}

/// Installation ownership and SwiftPM resource binding around the original API.
public enum HanlinExpoWidgetsIntegration {
    public static let genericWidgetKind = "HanlinOriginalExpoWidget"
    private static let registryPrefix = "__hanlin_expo_widget_registration_v1."
    private static let activityPrefix = "__hanlin_expo_activity_registration_v1."
    private static let generationsPrefix = "__hanlin_expo_widget_active_generations_v1."
    private struct Binding {
        let packageID: String
        let installedPackageID: String
        let generation: UInt64
        let productIdentifier: String
        let sessionID: String
    }
    private static let lock = NSLock()
    private static var bindings: [ObjectIdentifier: Binding] = [:]

    public static var productIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "HanlinExpoWidgetsProductIdentifier") as? String)
            ?? Bundle.main.bundleIdentifier ?? "Hanlin"
    }

    public static func bind(appContext: AnyObject, packageID: String, installedPackageID: String,
                            generation: UInt64, sessionID: String, productIdentifier: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        bindings[ObjectIdentifier(appContext)] = Binding(packageID: packageID,
            installedPackageID: installedPackageID, generation: generation,
            productIdentifier: productIdentifier ?? Self.productIdentifier, sessionID: sessionID)
    }

    public static func unbind(appContext: AnyObject) {
        lock.lock()
        defer { lock.unlock() }
        bindings.removeValue(forKey: ObjectIdentifier(appContext))
    }

    private static func binding(for appContext: AnyObject?) -> Binding? {
        guard let appContext else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return bindings[ObjectIdentifier(appContext)]
    }

    private static func digest(_ parts: [String]) -> String {
        SHA256.hash(data: Data(parts.joined(separator: "\0").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "HanlinExpoWidgets", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func generations(for product: String) -> [String: UInt64]? {
        guard let data = WidgetsStorage.defaults?.data(forKey: generationsPrefix + digest([product])) else { return nil }
        return try? JSONDecoder().decode([String: UInt64].self, from: data)
    }

    private static func isCurrent(_ descriptor: HanlinExpoWidgetDescriptor) -> Bool {
        guard descriptor.isActive else { return false }
        guard let active = generations(for: descriptor.productIdentifier) else { return true }
        return active[descriptor.installedPackageID] == descriptor.generation
    }

    private static func descriptor(for id: String, prefix: String = registryPrefix) -> HanlinExpoWidgetDescriptor? {
        guard let data = WidgetsStorage.defaults?.data(forKey: prefix + id) else { return nil }
        return try? JSONDecoder().decode(HanlinExpoWidgetDescriptor.self, from: data)
    }

    private static func allDescriptors(prefix: String = registryPrefix) -> [HanlinExpoWidgetDescriptor] {
        (WidgetsStorage.defaults?.dictionaryRepresentation() ?? [:]).compactMap { key, value in
            guard key.hasPrefix(prefix), let data = value as? Data else { return nil }
            return try? JSONDecoder().decode(HanlinExpoWidgetDescriptor.self, from: data)
        }
    }

    /// The ID excludes generation so updates retain the user's WidgetKit choice.
    /// Separate installations of the same author's package retain separate state.
    public static func qualifiedName(_ name: String, kind: String, appContext: AnyObject?) throws -> String {
        guard let owner = binding(for: appContext) else { throw failure("Expo Widgets has no bound MiniApp session.") }
        guard let group = WidgetsStorage.appGroupIdentifier, !group.isEmpty,
              let defaults = WidgetsStorage.defaults else {
            throw failure("The host is missing its Expo Widgets App Group configuration.")
        }
        if let active = generations(for: owner.productIdentifier), active[owner.installedPackageID] != owner.generation {
            throw failure("This MiniApp session's installed generation is no longer active.")
        }
        let id = "hanlin." + digest([owner.productIdentifier, owner.installedPackageID, kind, name])
        let value = HanlinExpoWidgetDescriptor(id: id, name: name, packageID: owner.packageID,
            installedPackageID: owner.installedPackageID, generation: owner.generation,
            productIdentifier: owner.productIdentifier, sessionID: owner.sessionID, kind: kind, isActive: true)
        // Independent keys prevent lost registrations between the two app processes.
        defaults.set(try JSONEncoder().encode(value), forKey: registryPrefix + id)
        return id
    }

    public static func registeredWidgets(productIdentifier: String? = nil,
                                          includeInactive: Bool = false) -> [HanlinExpoWidgetDescriptor] {
        let product = productIdentifier ?? Self.productIdentifier
        return allDescriptors().filter {
            $0.kind == "widget" && $0.productIdentifier == product && (includeInactive || isCurrent($0))
        }.sorted { ($0.packageID, $0.name, $0.id) < ($1.packageID, $1.name, $1.id) }
    }

    public static func registeredWidgetNames() -> [String] { registeredWidgets().map(\.id) }

    static func directoryNamespace(appContext: AnyObject?) -> String? {
        guard let owner = binding(for: appContext) else { return nil }
        return digest([owner.productIdentifier, owner.installedPackageID])
    }

    static func requireActive(name: String, appContext: AnyObject?) throws {
        guard let owner = binding(for: appContext), let record = descriptor(for: name), isCurrent(record),
              record.productIdentifier == owner.productIdentifier,
              record.installedPackageID == owner.installedPackageID,
              record.generation == owner.generation else {
            throw failure("This Expo widget belongs to a different or inactive installation generation.")
        }
    }

    static func isRegistrationActive(_ name: String) -> Bool {
        // Original build-time embedded layouts remain supported as well.
        guard name.hasPrefix("hanlin.") else { return true }
        guard let value = descriptor(for: name), value.productIdentifier == productIdentifier else { return false }
        return isCurrent(value)
    }

    static func recordActivity(id: String, name: String, appContext: AnyObject?) throws {
        try requireActive(name: name, appContext: appContext)
        guard let record = descriptor(for: name) else { return }
        WidgetsStorage.defaults?.set(try JSONEncoder().encode(record), forKey: activityPrefix + id)
    }

    static func isActivityCurrent(id: String, name: String, appContext: AnyObject?) -> Bool {
        guard (try? requireActive(name: name, appContext: appContext)) != nil else { return false }
        // A native push-to-start activity has no local creation receipt until it is adopted.
        guard let activity = descriptor(for: id, prefix: activityPrefix) else { return true }
        guard let current = descriptor(for: name) else { return false }
        return activity.installedPackageID == current.installedPackageID && activity.generation == current.generation
            && activity.productIdentifier == current.productIdentifier
    }

    /// Filter real native notifications by actual owner; preserve original public names/IDs.
    static func eventData(_ data: [String: Any], appContext: AnyObject?) -> [String: Any]? {
        guard let source = data["source"] as? String else { return nil }
        var result = data
        if let widget = descriptor(for: source), widget.kind == "widget" {
            guard (try? requireActive(name: source, appContext: appContext)) != nil else { return nil }
            result["source"] = widget.name
        } else if let activity = Activity<LiveActivityAttributes>.activities.first(where: { $0.id == source }) {
            guard isActivityCurrent(id: source, name: activity.content.state.name, appContext: appContext) else { return nil }
        } else { return nil }
        return result
    }

    /// Disable preserves selection/state; uninstall removes only this installation's data.
    /// Old generation layouts cannot execute until the updated package registers them again.
    @discardableResult
    public static func reconcileRegistrations(installedIDs: Set<String>, activeGenerations: [String: UInt64],
                                              productIdentifier: String? = nil) -> Bool {
        guard let defaults = WidgetsStorage.defaults else { return false }
        let product = productIdentifier ?? Self.productIdentifier
        let currentGenerationKey = generationsPrefix + digest([product])
        let oldGenerations = generations(for: product)
        if let data = try? JSONEncoder().encode(activeGenerations) { defaults.set(data, forKey: currentGenerationKey) }
        var changed = oldGenerations != activeGenerations
        var invalidNames = Set<String>()
        for record in allDescriptors() where record.productIdentifier == product {
            guard installedIDs.contains(record.installedPackageID) else {
                defaults.removeObject(forKey: registryPrefix + record.id)
                for key in defaults.dictionaryRepresentation().keys where
                    key.hasPrefix("__expo_widgets_\(record.id)_") || key.hasPrefix("__expo_widgets_live_activity_\(record.id)_") {
                    defaults.removeObject(forKey: key)
                }
                if let group = WidgetsStorage.appGroupIdentifier,
                   let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                    let directory = container.appendingPathComponent("ExpoWidgets", isDirectory: true)
                        .appendingPathComponent(digest([product, record.installedPackageID]), isDirectory: true)
                    try? FileManager.default.removeItem(at: directory)
                }
                invalidNames.insert(record.id)
                changed = true
                continue
            }
            let active = activeGenerations[record.installedPackageID] == record.generation
            if !active { invalidNames.insert(record.id) }
            if active != record.isActive {
                let updated = HanlinExpoWidgetDescriptor(id: record.id, name: record.name, packageID: record.packageID,
                    installedPackageID: record.installedPackageID, generation: record.generation,
                    productIdentifier: record.productIdentifier, sessionID: record.sessionID, kind: record.kind, isActive: active)
                if let data = try? JSONEncoder().encode(updated) { defaults.set(data, forKey: registryPrefix + record.id) }
                changed = true
            }
        }
        // Snapshot first: a new activity from the new generation must not be ended by this task.
        let staleActivities = Activity<LiveActivityAttributes>.activities.filter { invalidNames.contains($0.content.state.name) }
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(activityPrefix) {
            guard let data = value as? Data,
                  let owner = try? JSONDecoder().decode(HanlinExpoWidgetDescriptor.self, from: data),
                  owner.productIdentifier == product else { continue }
            if !installedIDs.contains(owner.installedPackageID) { defaults.removeObject(forKey: key) }
        }
        if !staleActivities.isEmpty {
            Task { for activity in staleActivities { await activity.end(nil, dismissalPolicy: .immediate) } }
        }
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: genericWidgetKind) }
        return changed
    }

    static func reload(_ name: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: name)
        WidgetCenter.shared.reloadTimelines(ofKind: genericWidgetKind)
    }

    static var resourceBundleURL: URL? {
        Bundle.module.url(forResource: "ExpoWidgets", withExtension: "bundle")
            ?? Bundle.main.url(forResource: "ExpoWidgets", withExtension: "bundle")
    }

    public static var isOriginalRuntimeAvailable: Bool {
        guard let url = resourceBundleURL, let bundle = Bundle(url: url),
              let runtime = bundle.url(forResource: "ExpoWidgets", withExtension: "bundle") else { return false }
        return FileManager.default.fileExists(atPath: runtime.path)
    }

    public static func placeholder(named name: String) -> WidgetsTimelineEntry {
        WidgetsTimelineEntry(date: Date(), name: name,
            props: isRegistrationActive(name) ? WidgetsLayoutRegistry.initialProps(for: name) : nil, entryIndex: nil)
    }

    public static func timeline(named name: String, family: WidgetFamily) -> Timeline<WidgetsTimelineEntry> {
        guard isRegistrationActive(name), let identifier = WidgetsStorage.appGroupIdentifier else {
            return Timeline(entries: [placeholder(named: name)], policy: .never)
        }
        return Timeline(entries: parseTimeline(identifier: identifier, name: name, family: family), policy: .atEnd)
    }
}
