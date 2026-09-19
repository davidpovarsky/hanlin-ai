import HanlinPlatformContracts
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    @ViewBuilder
    private var iconView: some View {
        switch descriptor.icon {
        case let .systemSymbol(name):
            Image(systemName: name)
                .font(.system(size: 27, weight: .semibold))
        case let .asset(name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 27, height: 27)
        case let .packageResource(path):
            #if canImport(UIKit)
            let imageURL: URL? = {
                switch descriptor.implementation {
                case let .nativeScript(pkgID), let .script(pkgID), let .hybrid(_, pkgID):
                    return HanlinScriptingPlatform.shared.resolveResourceURL(packageID: pkgID, relativePath: path)
                case .native:
                    return nil
                }
            }()
            let uiImage = imageURL.flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
                ?? UIImage(contentsOfFile: path)
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 27, height: 27)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 27, weight: .semibold))
            }
            #else
            Image(systemName: "app.dashed")
                .font(.system(size: 27, weight: .semibold))
            #endif
        }
    }

    private var accent: Color {
        Color(nativeAppHex: descriptor.appearance.accentHex?.replacingOccurrences(of: "#", with: "") ?? "5CB88A")
    }

    private var isBeta: Bool {
        descriptor.appearance.isBeta
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
                    iconView
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .opacity(0.82)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 168)
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
    }
}
