import HanlinPlatformContracts
import SwiftUI

/// The single Apps Hub card for every active Mini App engine.
///
/// Driven entirely by `HanlinAppDescriptor` so the same card component renders
/// both compiled Swift and NativeScript Mini Apps with identical geometry.
struct MiniAppCardView: View {
    let descriptor: HanlinAppDescriptor
    let isEditing: Bool

    private var title: String {
        descriptor.name.preferredValue(forLocale: Locale.current.identifier)
    }

    private var subtitle: String {
        descriptor.summary.preferredValue(forLocale: Locale.current.identifier)
    }

    private var systemImage: String {
        switch descriptor.icon {
        case let .systemSymbol(name), let .asset(name): name
        case .packageResource: "app.dashed"
        }
    }

    private var accent: Color {
        Color(nativeAppHex: descriptor.appearance.accentHex?.replacingOccurrences(of: "#", with: "") ?? "5CB88A")
    }

    private var isBeta: Bool {
        !descriptor.distribution.allowedModes.contains(.appStoreRestricted)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [accent.opacity(0.96), accent.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    if isBeta {
                        Text("BETA")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: systemImage)
                        .font(.system(size: 27, weight: .semibold))
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(2)
                        .opacity(0.82)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(minHeight: 150)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.17), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        .rotationEffect(.degrees(isEditing ? -0.45 : 0))
        .animation(
            isEditing
                ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                : .default,
            value: isEditing
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
