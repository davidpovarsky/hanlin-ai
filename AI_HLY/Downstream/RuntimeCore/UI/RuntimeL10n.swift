import Foundation

enum RuntimeL10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, tableName: "RuntimeLocalizable", bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
