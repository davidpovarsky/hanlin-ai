#if canImport(SwiftUI)
import SwiftUI
import HanlinPresentationKit

/// V17's hierarchy label. The disclosure affordance belongs beside its title,
/// before the flexible space, and fades away when the branch closes.
public struct HanlinActivityHierarchyHeader: View {
    public let title: String
    public let symbol: String
    public let depth: Int
    public let isExpanded: Bool
    public let isActive: Bool

    public init(title: String, symbol: String, depth: Int = 0,
                isExpanded: Bool, isActive: Bool) {
        self.title = title; self.symbol = symbol; self.depth = depth
        self.isExpanded = isExpanded; self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(HanlinTypography.body.weight(.medium))
                .foregroundStyle(.gray)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            HanlinActivityTitle(title,
                font: depth == 0 ? HanlinTypography.body.weight(.medium) : HanlinTypography.callout,
                baseColor: Color.primary.opacity(depth == 0 ? 0.88 : 0.73),
                isActive: isActive)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            HanlinActivityDisclosureArrow(isExpanded: isExpanded)
            Spacer(minLength: 0)
        }
        .frame(minHeight: depth == 0 ? 46 : 43)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

public struct HanlinActivityDisclosureArrow: View {
    public let isExpanded: Bool
    @Environment(\.chatMotion) private var motion
    @Environment(\.layoutDirection) private var direction

    public init(isExpanded: Bool) { self.isExpanded = isExpanded }

    public var body: some View {
        Image(systemName: "chevron.down")
            .font(HanlinTypography.caption2.weight(.semibold))
            .foregroundStyle(Color.gray.opacity(0.82))
            .rotationEffect(.degrees(isExpanded ? 0 : (direction == .rightToLeft ? 90 : -90)))
            .opacity(isExpanded ? 1 : 0)
            .frame(width: 12, height: 22)
            .animation(motion.disclosureAnimation(expanding: isExpanded), value: isExpanded)
            .accessibilityHidden(true)
    }
}

/// Native DisclosureGroup continues to own interaction and accessibility.
/// Its label supplies the adjacent arrow; only the approved V17 spacing/guide
/// is customized. Height reveal stays in the existing shared component.
public struct HanlinActivityDisclosureStyle: DisclosureGroupStyle {
    private let depth: Int
    private let isTool: Bool
    @Environment(\.hanlinActivityBranchVisible) private var branchIsVisible

    public init(depth: Int = 1, isTool: Bool = false) {
        self.depth = depth; self.isTool = isTool
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                configuration.label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, isTool ? 5 : 0)
            .accessibilityValue(configuration.isExpanded ? Text("Expanded") : Text("Collapsed"))

            HanlinAnimatedDisclosure(isExpanded: configuration.isExpanded, spacing: 0) {
                configuration.content
                    .environment(\.hanlinActivityBranchVisible, branchIsVisible && configuration.isExpanded)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 27)
                    .padding(.top, isTool ? 3 : 2)
                    .padding(.bottom, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(depth == 0 ? 0.14 : 0.10))
                            .frame(width: 1)
                            .padding(.leading, 10)
                            .padding(.bottom, isTool ? 3 : 4)
                            .accessibilityHidden(true)
                    }
            }
        }
    }
}
#endif
