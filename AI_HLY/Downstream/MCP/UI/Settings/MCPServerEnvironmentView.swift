import SwiftUI

struct MCPServerEnvironmentView: View {
    @Binding var variables: [MCPEnvironmentDraft]

    var body: some View {
        List {
            ForEach($variables) { $variable in
                VStack(alignment: .leading, spacing: 8) {
                    TextField(MCPL10n.string("Variable name"), text: $variable.name)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if variable.isSecret {
                        SecureField(MCPL10n.string("Secret value"), text: $variable.value)
                    } else {
                        TextField(MCPL10n.string("Value"), text: $variable.value)
                    }
                    Toggle(MCPL10n.string("Store in Keychain"), isOn: $variable.isSecret)
                }
            }
            .onDelete { variables.remove(atOffsets: $0) }
            Button(MCPL10n.string("Add variable"), systemImage: "plus") {
                variables.append(.init(name: "", value: "", isSecret: false))
            }
        }
        .navigationTitle(MCPL10n.string("Environment"))
    }
}
