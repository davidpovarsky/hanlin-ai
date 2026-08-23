import HanlinScriptStore
import SwiftUI

struct ScriptingPackageCardView: View {
    let package: HanlinStoredPackageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: package.manifest?.icon ?? "curlybraces.square")
                .font(.largeTitle)
                .frame(width: 56, height: 56)
                .background(.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            Text(package.manifest?.name ?? package.record.packageID.rawValue)
                .font(.headline)
                .lineLimit(2)
            Text(package.manifest?.description ?? "Scripting package")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Label(package.enabled ? "Enabled" : "Disabled", systemImage: package.enabled ? "checkmark.circle" : "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
