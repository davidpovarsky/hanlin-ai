// Source: expo/expo@917a61b581baeb852aa4fe331da2c1395d824351
// Hanlin: injected native intent button; widget-only context; visible diagnostics.
import SwiftUI
import ExpoModulesCore
import ExpoUI

@MainActor
struct WidgetsViewRenderer {
  let name: String
  let buttonBuilder: (String, SwiftUI.ButtonRole?, AnyView) -> AnyView
  let node: [String: Any]

  func render() -> any ExpoSwiftUI.AnyChild {
    switch node["type"] as? String {
    case "TextView":
      // TextView applies common modifiers internally so concatenated text keeps
      // its SwiftUI.Text representation. Avoid applying those modifiers again.
      return render(TextView.self, TextViewProps.self, updateProps: updateChildren)
    case "SlotView":
      return render(SlotView.self, SlotViewProps.self, updateProps: updateChildren)
    case "HStackView":
      return renderWithModifiers(HStackView.self, HStackViewProps.self, updateProps: updateChildren)
    case "VStackView":
      return renderWithModifiers(VStackView.self, VStackViewProps.self, updateProps: updateChildren)
    case "ZStackView":
      return renderWithModifiers(ZStackView.self, ZStackViewProps.self, updateProps: updateChildren)
    case "OverlayView":
      return renderWithModifiers(OverlayView.self, OverlayViewProps.self, updateProps: updateChildren)
    case "BackgroundView":
      return renderWithModifiers(BackgroundView.self, BackgroundViewProps.self, updateProps: updateChildren)
    case "MaskView":
      return renderWithModifiers(MaskView.self, MaskViewProps.self, updateProps: updateChildren)
    case "RectangleView":
      return renderWithModifiers(RectangleView.self, RectangleViewProps.self)
    case "RoundedRectangleView":
      return renderWithModifiers(RoundedRectangleView.self, RoundedRectangleViewProps.self)
    case "CapsuleView":
      return renderWithModifiers(CapsuleView.self, CapsuleViewProps.self)
    case "CircleView":
      return renderWithModifiers(CircleView.self, CircleViewProps.self)
    case "ImageView":
      return renderWithModifiers(ImageView.self, ImageViewProps.self)
    case "AccessoryWidgetBackgroundView":
      return renderWithModifiers(AccessoryWidgetBackgroundView.self, AccessoryWidgetBackgroundProps.self)
    case "DividerView":
      return renderWithModifiers(DividerView.self, DividerProps.self)
    case "EllipseView":
      return renderWithModifiers(EllipseView.self, EllipseViewProps.self)
    case "LabelView":
      return renderWithModifiers(LabelView.self, LabelViewProps.self)
    case "ProgressView":
      return renderWithModifiers(ProgressView.self, ProgressViewProps.self)
    case "SpacerView":
      return renderWithModifiers(SpacerView.self, SpacerViewProps.self)
    case "UnevenRoundedRectangleView":
      return renderWithModifiers(UnevenRoundedRectangleView.self, UnevenRoundedRectangleViewProps.self)
    case "GaugeView":
      return renderWithModifiers(GaugeView.self, GaugeProps.self)
    case "ChartView":
      return renderWithModifiers(ChartView.self, ChartProps.self)
    case "Button":
      return renderWithModifiers(WidgetButtonView.self, ButtonProps.self) { props in
        try updateChildren(props)
        guard let target = props.target, !target.isEmpty else { throw NativeWidgetError.missingTarget }
        props.nativeButton = buttonBuilder(target, props.role?.toNativeRole(), AnyView(WidgetButtonLabel(props: props)))
      }
    case "react.fragment":
      return renderWithModifiers(FragmentView.self, FragmentProps.self, updateProps: updateChildren)
    case "LinkView":
      return renderWithModifiers(LinkView.self, LinkViewProps.self, updateProps: updateChildren)
    default:
      return makeChild(Text("Unsupported Expo widget view: \(node["type"] as? String ?? "undefined")"))

    }
  }

  // MARK: - Render Method

  private func renderWithModifiers<P, V>(
    _ viewType: V.Type,
    _ propsType: P.Type,
    updateProps: ((_ initialProps: P) throws -> Void)? = nil
  ) -> any ExpoSwiftUI.AnyChild
  where P: UIBaseViewProps, V: ExpoSwiftUI.View, V.Props == P {
    render(UIBaseView<P, V>.self, propsType, updateProps: updateProps)
  }

  private func render<P, V>(
    _ viewType: V.Type,
    _ propsType: P.Type,
    updateProps: ((_ initialProps: P) throws -> Void)? = nil
  ) -> any ExpoSwiftUI.AnyChild
  where P: ExpoSwiftUI.ViewProps, V: ExpoSwiftUI.View, V.Props == P {
    do {
      guard let rawProps = node["props"] as? [String: Any] else {
        return makeChild(Text("Missing Expo widget props"))
      }
      let props = try propsType.init(rawProps: rawProps, context: WidgetsContext.shared.context)
      try updateProps?(props)
      return makeChild(V(props: props))
    } catch {
      return makeChild(Text("Invalid Expo widget props: \(error.localizedDescription)"))
    }
  }

  // MARK: - Child Views

  private func updateChildren<P>(_ initialProps: P) throws
  where P: ExpoSwiftUI.ViewProps {
    if let props = node["props"] as? [String: Any] {
      if let children = props["children"] as? [Any] {
        let validChildren = flattenChildNodes(children)
        initialProps.children = validChildren.map {
          WidgetsViewRenderer(name: name, buttonBuilder: buttonBuilder, node: $0).render()
        }
      } else if let child = props["children"] as? [String: Any] {
        initialProps.children = [
          WidgetsViewRenderer(name: name, buttonBuilder: buttonBuilder, node: child).render()
        ]
      }
    }
  }

  private func makeChild<Content: View>(_ view: Content) -> any ExpoSwiftUI.AnyChild {
    // Preserve the native view type for ExpoUI's slot and text inspection.
    WidgetsChildView(childView: view, stringIdentity: node["__expoWidgetIdentity"] as? String)
  }

  private func flattenChildNodes(_ children: [Any]) -> [[String: Any]] {
    return children.flatMap { child -> [[String: Any]] in
      if let node = child as? [String: Any] {
        return [node]
      }
      if let nested = child as? [Any] {
        return flattenChildNodes(nested)
      }
      return []
    }
  }
}
