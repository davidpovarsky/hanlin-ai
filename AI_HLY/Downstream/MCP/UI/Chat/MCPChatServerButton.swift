import SwiftUI

struct MCPChatServerButton: View {
    let chatID: UUID
    let temporary: Bool
    let toolUseSupported: Bool
    let disabled: Bool
    @Binding var ifToolUse: Bool
    @State private var showingSheet = false
    @State private var selectedCount = 0

    var body: some View {
        Button { showingSheet = true } label: {
            Image(systemName: "server.rack")
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.red, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .disabled(disabled || !toolUseSupported)
        .accessibilityLabel(MCPL10n.string("MCP servers for this chat"))
        .accessibilityHint(toolUseSupported ? MCPL10n.string("Choose which installed MCP servers the assistant may use.") : MCPL10n.string("The selected model does not support tool calling."))
        .sheet(isPresented: $showingSheet) {
            MCPChatServerSheet(chatID: chatID, temporary: temporary) { count in
                selectedCount = count
                if count > 0 { ifToolUse = true }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { selectedCount = await MCPRuntimeProvider.shared.selection(chatID: chatID, temporary: temporary).count }
    }
}
