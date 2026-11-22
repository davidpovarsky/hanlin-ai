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
                        String(localized: "No remembered tool permissions"),
                        systemImage: "hand.raised",
                        description: Text(String(localized: "Sensitive tools will ask before their first use."))
                    )
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
                                Label(String(localized: "Revoke permission"), systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(String(format: String(localized: "Revoke permission for %@"), grant.toolTitle))
                        }
                    }
                }
            } footer: {
                Text(String(localized: "Remembered permissions apply across your conversations on this device. System permissions remain controlled in Settings."))
            }
            if !grants.isEmpty {
                Section {
                    Button(String(localized: "Revoke all tool permissions"), role: .destructive) {
                        saveFailed = !HanlinToolApprovalStore.shared.revokeAll()
                        reload()
                    }
                }
            }
            if saveFailed {
                Section {
                    Text(String(localized: "The permission change could not be saved. Please try again."))
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(String(localized: "Tool permissions"))
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in reload() }
    }

    private func reload() { grants = HanlinToolApprovalStore.shared.grants }
}
