import Foundation

enum NativeAppJSON {
    static func decodeObject(from json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    static func string(_ object: [String: Any], _ key: String, default defaultValue: String = "") -> String {
        object[key] as? String ?? defaultValue
    }

    static func int(_ object: [String: Any], _ key: String, default defaultValue: Int) -> Int {
        if let int = object[key] as? Int { return int }
        if let double = object[key] as? Double { return Int(double) }
        if let string = object[key] as? String, let int = Int(string) { return int }
        return defaultValue
    }
}
