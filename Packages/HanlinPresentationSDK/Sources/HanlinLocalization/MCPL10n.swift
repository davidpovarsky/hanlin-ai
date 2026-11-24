import Foundation

public enum MCPL10n {
    public static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: "MCPLocalizable", bundle: HanlinLocalization.bundle, value: key, comment: "")
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
