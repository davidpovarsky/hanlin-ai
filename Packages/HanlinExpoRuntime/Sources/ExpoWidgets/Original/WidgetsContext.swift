import HanlinExpoWidgetSubset
import Foundation

// Shared AppContext for widgets
struct WidgetsContext {
  static let shared = WidgetsContext()
  let context: AppContext = AppContext(properties: .originalWidgets)

  private init() {
    registerWidgetModifiers()
  }
}
