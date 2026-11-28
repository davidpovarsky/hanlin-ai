// Copyright 2015-present 650 Industries. All rights reserved.

import SwiftUI

public final class EllipseViewProps: UIBaseViewProps {}

public struct EllipseView: ExpoSwiftUI.View {
  @ObservedObject public var props: EllipseViewProps

  public init(props: EllipseViewProps) {
    self.props = props
  }

  public var body: some View {
    Ellipse()
  }
}
