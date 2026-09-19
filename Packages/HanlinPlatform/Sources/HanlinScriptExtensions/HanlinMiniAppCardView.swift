// HanlinMiniAppCardView.swift
// HanlinScriptExtensions
//
// Canonical reusable Mini App card view providing identical outer geometry
// for every active Mini App engine across both the main Apps Hub (regular)
// and the compact Translation UI Provider (compact).

import HanlinPlatformContracts
import SwiftUI

public enum MiniAppCardStyle: String, Sendable, CaseIterable {
    case regular
    case compact

    public var height: CGFloat {
        switch self {
        case .regular: 168
        case .compact: 112
        }
    }

    public var cornerRadius: CGFloat {
        switch self {
        case .regular: 27
        case .compact: 18
        }
    }

    public var padding: CGFloat {
        switch self {
        case .regular: 18
        case .compact: 12
        }
    }

    public var iconSize: CGFloat {
        switch self {
        case .regular: 27
        case .compact: 22
        }
    }

    public var titleFont: Font {
        switch self {
        case .regular: .title3.weight(.semibold)
        case .compact: .subheadline.weight(.semibold)
        }
    }

    public var subtitleFont: Font {
        switch self {
        case .regular: .caption
        case .compact: .caption2
        }
    }

    public var titleLineLimit: Int {
        switch self {
        case .regular: 2
        case .compact: 1
        }
    }

    public var subtitleLineLimit: Int {
        switch self {
        case .regular: 2
        case .compact: 1
        }
    }
}

public struct HanlinMiniAppCardView<IconContent: View>: View {
    public let title: String
    public let subtitle: String
    public let accentHex: String?
    public let isBeta: Bool
    public let style: MiniAppCardStyle
    public let isEditing: Bool
    @ViewBuilder public let iconContent: () -> IconContent

    public init(
        title: String,
        subtitle: String,
        accentHex: String? = nil,
        isBeta: Bool = false,
        style: MiniAppCardStyle = .regular,
        isEditing: Bool = false,
        @ViewBuilder iconContent: @escaping () -> IconContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accentHex = accentHex
        self.isBeta = isBeta
        self.style = style
        self.isEditing = isEditing
        self.iconContent = iconContent
    }

    private var accentColor: Color {
        let cleanHex = accentHex?.replacingOccurrences(of: "#", with: "") ?? "5CB88A"
        return Self.parseColor(hex: cleanHex)
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor.opacity(0.96), accentColor.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: style == .regular ? 12 : 8) {
                HStack(alignment: .top) {
                    if isBeta {
                        Text("BETA")
                            .font(style == .regular ? .caption2.weight(.bold) : .system(size: 9, weight: .bold))
                            .padding(.horizontal, style == .regular ? 7 : 5)
                            .padding(.vertical, style == .regular ? 4 : 2)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    iconContent()
                }

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: style == .regular ? 4 : 2) {
                    Text(title)
                        .font(style.titleFont)
                        .lineLimit(style.titleLineLimit)
                        .truncationMode(.tail)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(style.subtitleFont)
                            .lineLimit(style.subtitleLineLimit)
                            .truncationMode(.tail)
                            .opacity(0.82)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(style.padding)
        }
        .frame(height: style.height)
        .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.17), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: style == .regular ? 12 : 8, y: style == .regular ? 6 : 4)
        .rotationEffect(.degrees(isEditing ? -0.45 : 0))
        .animation(
            isEditing
                ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                : .default,
            value: isEditing
        )
    }

    public static func parseColor(hex: String) -> Color {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        switch normalized.count {
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        default:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        }
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension HanlinMiniAppCardView where IconContent == AnyView {
    public init(
        title: String,
        subtitle: String,
        accentHex: String? = nil,
        isBeta: Bool = false,
        iconSymbol: String? = nil,
        style: MiniAppCardStyle = .regular,
        isEditing: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            accentHex: accentHex,
            isBeta: isBeta,
            style: style,
            isEditing: isEditing
        ) {
            AnyView(
                Image(systemName: iconSymbol ?? "app.dashed")
                    .font(.system(size: style.iconSize, weight: .semibold))
            )
        }
    }
}
