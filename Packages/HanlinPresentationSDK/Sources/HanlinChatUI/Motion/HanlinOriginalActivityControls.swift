#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit
import HanlinPresentationKit

// Original Hanlin chat activity controls; app and acceptance hosts use these bodies.
public struct LoadingGradientText: View {
    public let text: String
    public var textColor: Color = .gray
    public var font: Font = HanlinTypography.body.weight(.medium)
    public var isActive: Bool = true

    public init(text: String, textColor: Color = .gray,
                font: Font = HanlinTypography.body.weight(.medium), isActive: Bool = true) {
        self.text = text
        self.textColor = textColor
        self.font = font
        self.isActive = isActive
    }

    public var body: some View {
        HanlinActivityTitle(text, font: font, baseColor: textColor, isActive: isActive)
    }
}

public struct HanlinActivityToggleButton: View {
    public let title: String
    public let timeText: String
    @Binding public var isExpanded: Bool
    public var isActive = false
    public var numericCount: Int? = nil
    public var usesAnimatedDisclosure = false
    @Environment(\.chatMotion) private var motion

    public init(title: String, timeText: String, isExpanded: Binding<Bool>,
                isActive: Bool = false, numericCount: Int? = nil,
                usesAnimatedDisclosure: Bool = false) {
        self.title = title
        self.timeText = timeText
        _isExpanded = isExpanded
        self.isActive = isActive
        self.numericCount = numericCount
        self.usesAnimatedDisclosure = usesAnimatedDisclosure
    }

    public var body: some View {
        Button(action: {
            if usesAnimatedDisclosure { isExpanded.toggle() }
            else { withAnimation { isExpanded.toggle() } }
        }) {
            HStack {
                if isActive {
                    LoadingGradientText(text: title, font: HanlinTypography.caption)
                } else {
                    Text(title).font(HanlinTypography.caption).foregroundColor(Color(.systemGray))
                }
                Spacer()
                if !timeText.isEmpty {
                    Text(timeText)
                        .font(HanlinTypography.caption)
                        .foregroundColor(.gray)
                        .contentTransition(motion.numericCounts && numericCount != nil
                            ? .numericText(value: Double(numericCount ?? 0)) : .opacity)
                        .animation(motion.updateAnimation, value: timeText)
                }
                Image(systemName: "chevron.down")
                    .foregroundColor(Color(.systemGray))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(motion.disclosureAnimation(expanding: isExpanded), value: isExpanded)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
    }
}
#endif
