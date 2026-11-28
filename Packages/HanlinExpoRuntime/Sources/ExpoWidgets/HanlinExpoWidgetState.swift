import CryptoKit
import CoreFoundation
import Darwin
import Foundation
import WidgetKit

/// Atomic, installation-qualified state for the original Expo widget engine.
/// The original timeline wire remains visible through WidgetsStorage. A verified
/// file is authoritative for concurrent extension/app read-modify-write actions.
package enum HanlinExpoWidgetState {
  struct Rendered {
    let node: [String: Any]
    let retained: Bool
  }
  struct Snapshot {
    let timeline: [[String: Any]]
    let proof: HanlinExpoWidgetTimelineProof
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

  private static func withRecord<T>(_ name: String, _ body: (inout Record, HanlinExpoWidgetTimelineProof) throws -> T) throws -> T {
    guard let owner = HanlinExpoWidgetsIntegration.storageOwner(name),
          let layout = layoutRevision(name), let group = WidgetsStorage.appGroupIdentifier,
          let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
      throw Failure.unavailable
    }
    // Walk from the OS-owned App Group descriptor. No ancestor, lock, state or
    // backup file can redirect reads/writes outside this installation namespace.
    var directoryFD = open(container.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard directoryFD >= 0 else { throw Failure.unavailable }
    defer { close(directoryFD) }
    for component in ["ExpoWidgets", owner.namespace, "WidgetState-v1", digest(Data(name.utf8))] {
      if mkdirat(directoryFD, component, S_IRWXU) != 0 && errno != EEXIST { throw Failure.unavailable }
      let child = openat(directoryFD, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
      guard child >= 0 else { throw Failure.unavailable }
      close(directoryFD)
      directoryFD = child
    }
    let descriptor = openat(directoryFD, "state.lock", O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                            S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw Failure.unavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw Failure.unavailable }
    defer { _ = flock(descriptor, LOCK_UN) }
    guard HanlinExpoWidgetsIntegration.storageOwner(name)?.generation == owner.generation,
          layoutRevision(name) == layout else { throw Failure.unavailable }
    func exists(_ filename: String) throws -> Bool {
      var info = stat()
      if fstatat(directoryFD, filename, &info, AT_SYMLINK_NOFOLLOW) != 0 {
        guard errno == ENOENT else { throw Failure.unavailable }
        return false
      }
      guard (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.invalidState }
      return true
    }
    func read(_ filename: String) -> Data? {
      let file = openat(directoryFD, filename, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
      guard file >= 0 else { return nil }
      defer { close(file) }
      var info = stat()
      guard fstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
      return try? FileHandle(fileDescriptor: file, closeOnDealloc: false).readToEnd()
    }
    func atomicWrite(_ data: Data, filename: String) throws {
      let temporary = ".pending-" + UUID().uuidString
      let file = openat(directoryFD, temporary, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW,
                        S_IRUSR | S_IWUSR)
      guard file >= 0 else { throw Failure.unavailable }
      defer { close(file); _ = unlinkat(directoryFD, temporary, 0) }
      try FileHandle(fileDescriptor: file, closeOnDealloc: false).write(contentsOf: data)
      guard fsync(file) == 0, renameat(directoryFD, temporary, directoryFD, filename) == 0 else {
        throw Failure.unavailable
      }
    }
    func decode(_ filename: String) -> Record? {
      guard let data = read(filename),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
            digest(envelope.payload) == envelope.sha256,
            let record = try? JSONDecoder().decode(Record.self, from: envelope.payload),
            record.version == 1, record.name == name, record.generation == owner.generation,
            record.layoutSHA256 == layout,
            let timeline = try? JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]],
            (try? checkedTimeline(timeline)) != nil else { return nil }
      return record
    }
    let hasCurrent = try exists("state.json")
    let hasPrevious = try exists("previous.json")
    var record: Record
    if let valid = decode("state.json") ?? decode("previous.json") { record = valid }
    else {
      // Legacy migration happens once, only for a first-generation registration.
      // A corrupt or superseded record cannot resurrect unqualified old props.
      let canMigrate = !hasCurrent && !hasPrevious && owner.generation <= 1
      let legacy = canMigrate
        ? WidgetsStorage.getArray(forKey: "__expo_widgets_\(name)_timeline") as? [[String: Any]] : nil
      let entries = legacy.flatMap { (try? checkedTimeline($0)) != nil ? $0 : nil }
        ?? [["timestamp": Int(Date.now.timeIntervalSince1970 * 1_000),
             "props": WidgetsLayoutRegistry.initialProps(for: name) ?? [:]]]
      record = Record(name: name, generation: owner.generation, layoutSHA256: layout,
                      timeline: try checkedTimeline(entries))
    }
    let before = try JSONEncoder().encode(record)
    let proof = HanlinExpoWidgetTimelineProof(namespace: owner.namespace, generation: record.generation,
                                             layoutSHA256: record.layoutSHA256)
    let result = try body(&record, proof)
    guard HanlinExpoWidgetsIntegration.storageOwner(name)?.generation == owner.generation,
          layoutRevision(name) == layout else { throw Failure.unavailable }
    let payload = try JSONEncoder().encode(record)
    if payload != before || !hasCurrent || decode("state.json") == nil {
      if let previous = decode("state.json") {
        let prior = try JSONEncoder().encode(previous)
        try atomicWrite(JSONEncoder().encode(Envelope(sha256: digest(prior), payload: prior)), filename: "previous.json")
      }
      try atomicWrite(JSONEncoder().encode(Envelope(sha256: digest(payload), payload: payload)), filename: "state.json")
    }
    if let entries = try JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]] {
      WidgetsStorage.set(entries, forKey: "__expo_widgets_\(name)_timeline")
    }
    return result
  }

  package static func updateTimeline(_ entries: [[String: Any]], name: String) throws {
    let data = try checkedTimeline(entries)
    try withRecord(name) { record, _ in record.timeline = data }

  }

  static func snapshot(_ name: String) -> Snapshot? {
    try? withRecord(name) { record, proof in
      guard let entries = try JSONSerialization.jsonObject(with: record.timeline) as? [[String: Any]] else {
        throw Failure.invalidState
      }
      return Snapshot(timeline: entries, proof: proof)
    }
  }

  package static func timeline(_ name: String) -> [[String: Any]]? { snapshot(name)?.timeline }

  static func placeholder(_ name: String) -> WidgetsTimelineEntry {
    let captured = snapshot(name)
    return WidgetsTimelineEntry(date: Date(), name: name,
      props: captured?.timeline.first?["props"] as? [String: Any], entryIndex: nil,
      snapshotProof: captured?.proof)
  }

  static func performInteraction(source: String?, target: String?, entryIndex: Int?,
                                 environmentString: String?, desiredValue: Bool? = nil) throws {
    guard let source else { throw Failure.unavailable }
    defer { HanlinExpoWidgetsIntegration.reload(source) }
    guard let target, let entryIndex, let bytes = environmentString?.data(using: .utf8),
          var environment = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
      throw Failure.staleEntry
    }
    try withRecord(source) { record, proof in
      guard environment["__hanlinNamespace"] as? String == proof.namespace,
            environment["__hanlinGeneration"] as? String == String(proof.generation),
            environment["__hanlinLayoutRevision"] as? String == proof.layoutSHA256,
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
        guard let value else {
          // Original Buttons may only emit an app listener event without
          // returning props. Preserve that original API; Toggles must commit.
          if desiredValue != nil { throw Failure.missingCallback }
          return
        }
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
                     environment: [String: Any], proof capturedProof: HanlinExpoWidgetTimelineProof?) -> Rendered {
    let appearanceKeys = ["widgetFamily", "configuration", "colorScheme", "widgetRenderingMode",
                          "showsContainerBackground", "isLuminanceReduced", "widgetContentMargins",
                          "levelOfDetail", "showsWidgetLabel"]
    let appearance = environment.filter { appearanceKeys.contains($0.key) }
    let key = (try? JSONSerialization.data(withJSONObject: appearance, options: [.sortedKeys])).map(digest)
    do {
      return try withRecord(name) { record, currentProof in
        // A timeline captured before a package upgrade must never execute or
        // populate a new generation's cache using its stale layout.
        guard capturedProof == currentProof,
              record.layoutSHA256 == digest(Data(layout.utf8)) else { throw Failure.staleEntry }
        switch evaluateWidgetLayout(layout: layout, props: props, environment: environment) {
        case .success(let node):
          if let key, JSONSerialization.isValidJSONObject(node),
             let data = try? JSONSerialization.data(withJSONObject: node, options: [.sortedKeys]) {
            record.rendered[key] = data
          }
          return .init(node: node, retained: false)
        case .failure(let error):
          if let key, let data = record.rendered[key],
             let node = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return .init(node: node, retained: true)
          }
          return .init(node: createRedBox(message: error.message), retained: false)
        }
      }
    } catch {
      return .init(node: createRedBox(message: "This widget's source or installation is no longer current."),
                   retained: false)
    }
  }
}
