import Foundation
import ExpoModulesCore

public final class HanlinHostServicesModule: Module {
    public func definition() -> ModuleDefinition {
        Name("HanlinHostServices")

        AsyncFunction("executeRuntime") { (kind: String, source: String) -> String in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            return try await provider.executeRuntime(kind: kind, source: source)
        }

        AsyncFunction("executeNode") { (source: String) -> String in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            return try await provider.executeNode(source: source)
        }

        AsyncFunction("executePython") { (source: String) -> String in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            return try await provider.executePython(source: source)
        }

        AsyncFunction("readFile") { (path: String, area: String) -> String in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            return try await provider.readFile(path: path, area: area)
        }

        AsyncFunction("writeFile") { (path: String, content: String, area: String) in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            try await provider.writeFile(path: path, content: content, area: area)
        }

        AsyncFunction("executeSQLite") { (sql: String, params: [Any]?) -> [[String: Any]] in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            return try await provider.executeSQLite(sql: sql, params: params)
        }

        AsyncFunction("fetchURL") { (urlString: String) -> String in
            guard let provider = HanlinExpoHostServicesBridge.currentProvider else {
                throw NSError(
                    domain: "HanlinExpoHostServices",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "No active Hanlin Expo host services provider."]
                )
            }
            return try await provider.fetchURL(urlString: urlString)
        }
    }
}
