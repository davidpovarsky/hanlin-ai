import HanlinExpoWidgetSubset
import SwiftUI

final class FragmentProps: HanlinExpoWidgetSubset.ButtonProps {}

struct FragmentView: ExpoSwiftUI.View {
  @ObservedObject var props: FragmentProps

  var body: some View {
    Children()
  }
}
