import SwiftUI

struct NativeAppDetailView: View {
    let module: NativeAppModule
    let context: NativeAppContext

    var body: some View {
        List {
            Section {
                Label(module.manifest.title, systemImage: module.manifest.systemImage)
                    .font(.title3.weight(.semibold))
                Text(module.manifest.description)
                    .foregroundStyle(.secondary)
            }

            Section("Entry Points") {
                ForEach(module.manifest.entryPoints.map { $0 }.sorted { $0.rawValue < $1.rawValue }, id: \.self) { entry in
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

            Section("Open") {
                NavigationLink("Open full app") {
                    module.makeRootView(context: context)
                }
            }
        }
        .navigationTitle(module.manifest.title)
    }
}
