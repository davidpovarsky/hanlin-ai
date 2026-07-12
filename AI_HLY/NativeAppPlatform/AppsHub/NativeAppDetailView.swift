import SwiftUI

struct NativeAppDetailView: View {
    let module: NativeAppModule
    let context: NativeAppContext

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    Color(nativeAppHex: module.manifest.appearance.startHex),
                                    Color(nativeAppHex: module.manifest.appearance.endHex)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: module.manifest.systemImage)
                                .font(.title)
                                .foregroundStyle(Color(nativeAppHex: module.manifest.appearance.foregroundHex))
                        }
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.manifest.title).font(.title3.weight(.semibold))
                            Text(module.manifest.subtitle).foregroundStyle(.secondary)
                        }
                    }
                    Text(module.manifest.description)
                        .foregroundStyle(.secondary)
                }

                Section("Entry Points") {
                    ForEach(module.manifest.entryPoints.sorted { $0.rawValue < $1.rawValue }, id: \.self) { entry in
                        LabeledContent(entry.title, value: entry.rawValue)
                    }
                }

                let capabilities = module.capabilities(context: context)
                if !capabilities.isEmpty {
                    Section("Capabilities") {
                        ForEach(capabilities) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(request.capability.title)
                                    Spacer()
                                    Text(context.capabilityRegistry.userFacingStatus(for: request))
                                        .foregroundStyle(.secondary)
                                }
                                if let domain = request.domain {
                                    Text(domain).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(request.reason).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("Assistant Tools") {
                    let tools = module.assistantTools(context: context)
                    if tools.isEmpty {
                        Text("No Assistant entry points")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.catalogEntry.title)
                                Text(tool.name)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

            }
            .navigationTitle(module.manifest.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
