import SwiftUI

struct NativeAppCardView: View {
    let manifest: NativeAppManifest
    let isEditing: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nativeAppHex: manifest.appearance.startHex),
                    Color(nativeAppHex: manifest.appearance.endHex)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    if manifest.isExperimental {
                        Text("BETA")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: manifest.systemImage)
                        .font(.system(size: 27, weight: .semibold))
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(manifest.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(manifest.subtitle)
                        .font(.caption)
                        .lineLimit(2)
                        .opacity(0.82)
                }
            }
            .foregroundStyle(Color(nativeAppHex: manifest.appearance.foregroundHex))
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
        .accessibilityLabel("\(manifest.title), \(manifest.subtitle)")
    }
}
