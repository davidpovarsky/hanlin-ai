import HanlinLocalization
import SwiftUI

@MainActor
struct HanlinToolPermissionsView: View {
    @State private var grants: [HanlinToolApprovalStore.Grant] = []
    @State private var saveFailed = false

    var body: some View {
        Form {
            Section {
                if grants.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No remembered tool permissions", bundle: HanlinLocalization.bundle),
                        systemImage: "hand.raised",
                        description: Text(String(localized: "Sensitive tools will ask before their first use.", bundle: HanlinLocalization.bundle))
                    )
                    .accessibilityIdentifier("hanlin-tool-permissions-empty")
                } else {
                    ForEach(grants) { grant in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(grant.toolTitle)
                                Text(grant.createdAt, style: .date)
                                    .font(HanlinTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                saveFailed = !HanlinToolApprovalStore.shared.revoke(id: grant.id)
                                reload()
                            } label: {
                                Label(String(localized: "Revoke permission", bundle: HanlinLocalization.bundle), systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(String(format: String(localized: "Revoke permission for %@", bundle: HanlinLocalization.bundle), grant.toolTitle))
                        }
                    }
                }
            } footer: {
                Text(String(localized: "Remembered permissions apply across your conversations on this device. System permissions remain controlled in Settings.", bundle: HanlinLocalization.bundle))
            }
            if !grants.isEmpty {
                Section {
                    Button(String(localized: "Revoke all tool permissions", bundle: HanlinLocalization.bundle), role: .destructive) {
                        saveFailed = !HanlinToolApprovalStore.shared.revokeAll()
                        reload()
                    }
                    .accessibilityIdentifier("hanlin-tool-permissions-revoke-all")
                }
            }
            if saveFailed {
                Section {
                    Text(String(localized: "The permission change could not be saved. Please try again.", bundle: HanlinLocalization.bundle))
                        .foregroundStyle(.red)
                }
            }
        }
        .accessibilityIdentifier("hanlin-tool-permissions-list")
        .navigationTitle(String(localized: "Tool permissions", bundle: HanlinLocalization.bundle))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in reload() }
    }

    private func reload() { grants = HanlinToolApprovalStore.shared.grants }
}
