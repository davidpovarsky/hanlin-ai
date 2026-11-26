import CryptoKit
import CoreFoundation
import Darwin
import Foundation
import WidgetKit

/// Atomic, installation-qualified state for the original Expo widget engine.
/// The original timeline wire remains visible through WidgetsStorage. A verified
/// file is authoritative for concurrent extension/app read-modify-write actions.
enum HanlinExpoWidgetState {
  struct Rendered {
    let node: [String: Any]
    let retained: Bool
  }
  private struct Record: Codable {
    var version = 1
    let name: String
    let generation: UInt64
    let layoutSHA256: String
    var timeline: Data
    var rendered: [String: Data] = [:]
  }
  private struct Envelope: Codable {
    let sha256: String
    let payload: Data
  }
  private enum Failure: Error {
    case unavailable, invalidTimeline, invalidState, staleEntry, missingCallback
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func layoutRevision(_ name: String) -> String? {
    WidgetsLayoutRegistry.layout(for: name).map { digest(Data($0.utf8)) }
  }

  private static func checkedTimeline(_ entries: [[String: Any]]) throws -> Data {
    guard !entries.isEmpty, JSONSerialization.isValidJSONObject(entries) else { throw Failure.invalidTimeline }
    var last = -Double.infinity
    for entry in entries {
      guard let timestamp = entry["timestamp"] as? NSNumber,
            CFGetTypeID(timestamp) != CFBooleanGetTypeID(),
            timestamp.doubleValue.isFinite, timestamp.doubleValue.rounded() == timestamp.doubleValue,
            timestamp.doubleValue >= last, entry["props"] is [String: Any] else { throw Failure.invalidTimeline }
      last = timestamp.doubleValue
    }
    return try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
  }

  private static func withRecord<T>(_ name: String, _ body: (inout Record) throws -> T) throws -> T {
    guard let owner = HanlinExpoWidgetsIntegration.storageOwner(name),
          let layout = layoutRevision(name), let group = WidgetsStorage.appGroupIdentifier,
          let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
      throw Failure.unavailable
    }
    let directory = container.appendingPathComponent("ExpoWidgets", isDirectory: true)
      .appendingPathComponent(owner.namespace, isDirectory: true)
      .appendingPathComponent("WidgetState-v1", isDirectory: true)
      .appendingPathComponent(digest(Data(name.utf8)), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let descriptor = open(directory.appendingPathComponent("state.lock").path,
                          O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw Failure.unavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw Failure.unavailable }
    defer { flock(descriptor, LOCK_UN) }
    // Recheck after waiting for another app/extension transaction.
    guard HanlinExpoWidgetsIntegration.storageOwner(name)?.generation == owner.generation,
          layoutRevision(name) == layout else { throw Failure.unavailable }
    let currentURL = directory.appendingPathComponent("state.json")
    let previousURL = directory.appendingPathComponent("previous.json")
    func decode(_ url: URL) -> Record? {
      guard let data = try? Data(contentsOf: url),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            digest(envelope.payload) == envelope.sha256,
            let record = try? JSONDecoder().decode(Record.self, from: envelope.payload),
            record.version == 1, record.name == name, record.generation == owner.generation,
            record.layoutSHA256 == layout,
            let timeline = try? JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]],
            (try? checkedTimeline(timeline)) != nil else { return nil }
      return record
    }
    var record: Record
    if let valid = decode(currentURL) ?? decode(previousURL) { record = valid }
    else {
      let previous = WidgetsStorage.getArray(forKey: "__expo_widgets_\(name)_timeline") as? [[String: Any]]
      let entries = previous.flatMap { (try? checkedTimeline($0)) != nil ? $0 : nil }
        ?? [["timestamp": Int(Date.now.timeIntervalSince1970 * 1_000),
             "props": WidgetsLayoutRegistry.initialProps(for: name) ?? [:]]]
      record = Record(name: name, generation: owner.generation, layoutSHA256: layout,
                      timeline: try checkedTimeline(entries))
    }
    let before = try JSONEncoder().encode(record)
    let result = try body(&record)
    // If a package was disabled/updated during script execution, do not commit.
    guard HanlinExpoWidgetsIntegration.storageOwner(name)?.generation == owner.generation,
          layoutRevision(name) == layout else { throw Failure.unavailable }
    let payload = try JSONEncoder().encode(record)
    if payload != before || !FileManager.default.fileExists(atPath: currentURL.path) || decode(currentURL) == nil {
      if let previous = decode(currentURL) {
        let prior = try JSONEncoder().encode(previous)
        try JSONEncoder().encode(Envelope(sha256: digest(prior), payload: prior))
          .write(to: previousURL, options: .atomic)
      }
      try JSONEncoder().encode(Envelope(sha256: digest(payload), payload: payload))
        .write(to: currentURL, options: .atomic)
    }
    if let entries = try JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]] {
      WidgetsStorage.set(entries, forKey: "__expo_widgets_\(name)_timeline")
    }
    return result
  }

  static func updateTimeline(_ entries: [[String: Any]], name: String) throws {
    let data = try checkedTimeline(entries)
    try withRecord(name) { $0.timeline = data }

  }

  static func timeline(_ name: String) -> [[String: Any]]? {
    try? withRecord(name) { record in
      guard let entries = try JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]] else {
        throw Failure.invalidState
      }
      return entries
    }
  }

  static func performInteraction(source: String?, target: String?, entryIndex: Int?,
                                 environmentString: String?, desiredValue: Bool? = nil) throws {
    guard let source else { throw Failure.unavailable }
    defer { HanlinExpoWidgetsIntegration.reload(source) }
    guard let target, let entryIndex, let bytes = environmentString?.data(using: .utf8),
          var environment = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
      throw Failure.staleEntry
    }
    try withRecord(source) { record in
      guard environment["__hanlinLayoutRevision"] as? String == record.layoutSHA256,
            var entries = try JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]],
            entries.indices.contains(entryIndex),
            let expectedTimestamp = environment["timestamp"] as? NSNumber,
            let actualTimestamp = entries[entryIndex]["timestamp"] as? NSNumber,
            expectedTimestamp == actualTimestamp,
            let props = entries[entryIndex]["props"] as? [String: Any],
            let layout = WidgetsLayoutRegistry.layout(for: source) else { throw Failure.staleEntry }
      environment["target"] = target
      environment["__hanlinToggleValue"] = desiredValue
      let next: [String: Any]
      switch evaluateWidgetButtonPress(layout: layout, props: props, environment: environment) {
      case .success(let value):
        guard let value else { throw Failure.missingCallback }
        next = value
      case .failure(let error): throw error
      }
      entries[entryIndex]["props"] = props.merging(next) { _, new in new }
      record.timeline = try checkedTimeline(entries)
    }
    var event: [String: Any] = ["source": source, "target": target,
                               "timestamp": Int(Date.now.timeIntervalSince1970 * 1_000)]
    if let desiredValue { event["value"] = desiredValue; event["isOn"] = desiredValue }
    WidgetsEvents.shared.sendNotification(type: .userEvent, data: event)
  }

  /// Retain the last actual successful render for the same source/generation,
  /// family, appearance and user configuration. Never reuse across installations.
  static func render(name: String, layout: String, props: [String: Any]?,
                     environment: [String: Any]) -> Rendered {
    let appearanceKeys = ["widgetFamily", "configuration", "colorScheme", "widgetRenderingMode",
                          "showsContainerBackground", "isLuminanceReduced", "widgetContentMargins",
                          "levelOfDetail", "showsWidgetLabel"]
    let appearance = environment.filter { appearanceKeys.contains($0.key) }
    let key = (try? JSONSerialization.data(withJSONObject: appearance, options: [.sortedKeys])).map(digest)
    switch evaluateWidgetLayout(layout: layout, props: props, environment: environment) {
    case .success(let node):
      if let key, JSONSerialization.isValidJSONObject(node),
         let data = try? JSONSerialization.data(withJSONObject: node, options: [.sortedKeys]) {
        try? withRecord(name) { $0.rendered[key] = data }
      }
      return .init(node: node, retained: false)
    case .failure(let error):
      if let key, let data = try? withRecord(name, { $0.rendered[key] }),
         let node = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        // The retained view remains readable; stale controls are disabled by its host.
        return .init(node: node, retained: true)
      }
      return .init(node: createRedBox(message: error.message), retained: false)
    }
  }
}
