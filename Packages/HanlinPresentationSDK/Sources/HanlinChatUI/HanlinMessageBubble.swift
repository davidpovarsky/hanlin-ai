#if canImport(UIKit)
import SwiftUI
import UIKit
import HanlinLocalization

/// Original Hanlin user-message chrome. The host supplies only its original
/// context-menu actions and measured transcript width; layout, shape and motion
/// are owned here by the same component used in Hanlin's ChatBubbleView.
public struct HanlinUserMessageBubble<Menu: View>: View {
    public let text: String
    public let containerWidth: CGFloat
    public let temporaryRecord: Bool
    private let menu: Menu

    public init(text: String, containerWidth: CGFloat, temporaryRecord: Bool = false,
                @ViewBuilder contextMenu: () -> Menu) {
        self.text = text; self.containerWidth = containerWidth
        self.temporaryRecord = temporaryRecord; menu = contextMenu()
    }

    public var body: some View {
        HStack {
            Text(text)
        }
        .padding(10)
        .background(temporaryRecord ? .primary : Color.hanlinHLBlue)
        .foregroundColor(temporaryRecord ? Color(.systemBackground) : .white)
        .contextMenu { menu }
        .clipShape(HanlinMessageCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: containerWidth * 0.75, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityIdentifier("hanlin-user-bubble")
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: text.isEmpty)
    }


}

public extension HanlinUserMessageBubble where Menu == EmptyView {
    init(text: String, containerWidth: CGFloat, temporaryRecord: Bool = false) {
        self.init(text: text, containerWidth: containerWidth, temporaryRecord: temporaryRecord) { EmptyView() }
    }
}

/// Original assistant-message stack, including its accessibility grouping and
/// entrance motion. Actual Markdown, sources, activity and rich payload views
/// remain the caller's canonical components inside the content slot.
public struct HanlinAssistantMessageBubble<Content: View>: View {
    public let isResponding: Bool
    private let content: Content

    public init(isResponding: Bool, @ViewBuilder content: () -> Content) {
        self.isResponding = isResponding; self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-assistant-bubble")
        .transition(.move(edge: .leading).combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.4),
                   value: isResponding)
    }
}

public struct HanlinMessageCorners: Shape {
    public var topLeft: CGFloat = 0
    public var topRight: CGFloat = 0
    public var bottomLeft: CGFloat = 0
    public var bottomRight: CGFloat = 0

    public init(topLeft: CGFloat = 0, topRight: CGFloat = 0,
                bottomLeft: CGFloat = 0, bottomRight: CGFloat = 0) {
        self.topLeft = topLeft; self.topRight = topRight
        self.bottomLeft = bottomLeft; self.bottomRight = bottomRight
    }

    public func path(in rect: CGRect) -> Path {
        // 限制半径不超过宽高一半
        let tl = min(min(topLeft, rect.width / 2), rect.height / 2)
        let tr = min(min(topRight, rect.width / 2), rect.height / 2)
        let bl = min(min(bottomLeft, rect.width / 2), rect.height / 2)
        let br = min(min(bottomRight, rect.width / 2), rect.height / 2)

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        let path = CGMutablePath()
        // 起点放在左上边，偏移 tl，使下段线、弧线自动衔接
        path.move(to: CGPoint(x: minX + tl, y: minY))

        // top edge → top-right corner
        path.addLine(to: CGPoint(x: maxX - tr, y: minY))
        path.addArc(tangent1End: CGPoint(x: maxX, y: minY),
                    tangent2End: CGPoint(x: maxX, y: minY + tr),
                    radius: tr)

        // right edge → bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: maxY - br))
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY),
                    tangent2End: CGPoint(x: maxX - br, y: maxY),
                    radius: br)

        // bottom edge → bottom-left corner
        path.addLine(to: CGPoint(x: minX + bl, y: maxY))
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY),
                    tangent2End: CGPoint(x: minX, y: maxY - bl),
                    radius: bl)

        // left edge → back to top-left corner
        path.addLine(to: CGPoint(x: minX, y: minY + tl))
        path.addArc(tangent1End: CGPoint(x: minX, y: minY),
                    tangent2End: CGPoint(x: minX + tl, y: minY),
                    radius: tl)

        path.closeSubpath()

        return Path(path)
    }
}
#endif
