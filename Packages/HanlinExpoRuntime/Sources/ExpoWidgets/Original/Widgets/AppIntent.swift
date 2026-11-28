import Foundation
import AppIntents
import WidgetKit

struct WidgetReload: AppIntent {
  // title is not used for non-discoverable intents, but it is required
  static var title: LocalizedStringResource = "Reload widget"
  static var isDiscoverable: Bool = false
  @Parameter(title: "source")
  var source: String?

  init() {}
  init(source: String?) {
    self.source = source
  }

  func perform() async throws -> some IntentResult {
    guard let source else {
      return .result()
    }

    HanlinExpoWidgetsIntegration.reload(source)
    return .result()
  }
}

struct WidgetUserInteraction: AppIntent {
  // title is not used for non-discoverable intents, but it is required
  static var title: LocalizedStringResource = "User Interaction"
  static var isDiscoverable: Bool = false
  @Parameter(title: "source")
  var source: String?

  @Parameter(title: "target")
  var target: String?

  @Parameter(title: "entryIndex")
  var entryIndex: Int?

  @Parameter(title: "environmentString")
  var environmentString: String?

  init() {}
  init(source: String?, target: String?, entryIndex: Int?, environmentString: String?) {
    self.source = source
    self.target = target
    self.entryIndex = entryIndex
    self.environmentString = environmentString
  }

  func perform() async throws -> some IntentResult {
    try HanlinExpoWidgetState.performInteraction(source: source, target: target,
      entryIndex: entryIndex, environmentString: environmentString)
    return .result()
  }

}

struct LiveActivityUserInteraction: LiveActivityIntent {
  // title is not used for non-discoverable intents, but it is required
  static var title: LocalizedStringResource = "User Interaction"
  static var isDiscoverable: Bool = false

  @Parameter(title: "source")
  var source: String?

  @Parameter(title: "target")
  var target: String?

  init() {}
  init(source: String?, target: String?) {
    self.source = source
    self.target = target
  }

  func perform() async throws -> some IntentResult {
    WidgetsEvents.shared.sendNotification(type: .userEvent, data: [
      "source": source as Any,
      "target": target as Any,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ])

    return .result()
  }
}
