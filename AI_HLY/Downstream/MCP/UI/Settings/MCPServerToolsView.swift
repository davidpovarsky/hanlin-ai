import SwiftUI

struct MCPServerToolsView: View {
    @State private var provider = MCPRuntimeProvider.shared
    @State private var tools: [MCPToolDescriptor] = []
    @State private var loading = true

    let server: MCPServerDescriptor

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else if tools.isEmpty {
                ContentUnavailableView(
                    MCPL10n.string("No tools"),
                    systemImage: "wrench.and.screwdriver"
                )
            } else {
                ForEach(tools) { tool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tool.title ?? tool.originalName)
                            .font(.headline)
                        Text(tool.exposedName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if let summary = tool.summary, !summary.isEmpty {
                            Text(summary).font(.callout)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(MCPL10n.string("Tools"))
        .task { await loadTools() }
        .refreshable { await loadTools() }
    }

    private func loadTools() async {
        loading = true
        tools = await provider.tools(for: server)
        loading = false
    }
}
