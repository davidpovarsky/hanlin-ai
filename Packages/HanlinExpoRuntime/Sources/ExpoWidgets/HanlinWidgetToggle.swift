import HanlinExpoWidgetSubset
import AppIntents
import SwiftUI

/// Widget-only specialization of the original Expo Toggle props. The native
/// SetValueIntent receives the intended value, including repeated on/off taps.
final class WidgetToggleProps: UIBaseViewProps {
  @Field var isOn: Bool = false
  @Field var label: String?
  @Field var systemImage: String?
  @Field var source: String?
  @Field var target: String?
  @Field var entryIndex: Int?
  @Field var environmentString: String?
}

struct WidgetToggleView: ExpoSwiftUI.View {
  @ObservedObject var props: WidgetToggleProps

  var body: some View {
    SwiftUI.Toggle(isOn: props.isOn, intent: WidgetSetValue(
      source: props.source, target: props.target, entryIndex: props.entryIndex,
      environmentString: props.environmentString, value: !props.isOn
    )) {
      if let label = props.label {
        if let systemImage = props.systemImage {
          Label(title: { Text(label) }, icon: { Image(systemName: systemImage) })
        } else { Text(label) }
      } else { Children() }
    }
  }
}

struct WidgetRefreshButtonView: ExpoSwiftUI.View {
  @ObservedObject var props: ButtonProps
  var body: some View {
    SwiftUI.Button(intent: WidgetReload(source: props.source)) {
      if let label = props.label {
        if let systemImage = props.systemImage {
          Label(title: { Text(label) }, icon: { Image(systemName: systemImage) })
        } else { Text(label) }
      } else { Children() }
    }
  }
}

struct WidgetSetValue: SetValueIntent {
  static let title: LocalizedStringResource = "Set widget value"
  static let isDiscoverable = false
  static var supportedModes: IntentModes { [.background] }
  @Parameter(title: "source") var source: String?
  @Parameter(title: "target") var target: String?
  @Parameter(title: "entryIndex") var entryIndex: Int?
  @Parameter(title: "environmentString") var environmentString: String?
  @Parameter(title: "value") var value: Bool

  init() { value = false }
  init(source: String?, target: String?, entryIndex: Int?, environmentString: String?, value: Bool) {
    self.source = source
    self.target = target
    self.entryIndex = entryIndex
    self.environmentString = environmentString
    self.value = value
  }

  func perform() async throws -> some IntentResult {
    try HanlinExpoWidgetState.performInteraction(source: source, target: target,
      entryIndex: entryIndex, environmentString: environmentString, desiredValue: value)
    return .result()
  }
}
