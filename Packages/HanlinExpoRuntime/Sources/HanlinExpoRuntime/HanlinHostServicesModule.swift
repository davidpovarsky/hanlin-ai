import Foundation
import ExpoModulesCore

public final class HanlinHostServicesModule: Module {
    private static func missingProviderError() -> NSError {
        NSError(
            domain: "HanlinExpoHostServices",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "No Host Services provider is bound to this Expo AppContext."]
        )
    }

    public func definition() -> ModuleDefinition {
        let moduleAppContext = appContext
        Name("HanlinHostServices")

        AsyncFunction("executeRuntime") { [weak moduleAppContext] (kind: String, source: String) -> String in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            return try await provider.executeRuntime(kind: kind, source: source)
        }

        AsyncFunction("executeNode") { [weak moduleAppContext] (source: String) -> String in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            return try await provider.executeNode(source: source)
        }

        AsyncFunction("executePython") { [weak moduleAppContext] (source: String) -> String in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            return try await provider.executePython(source: source)
        }

        AsyncFunction("readFile") { [weak moduleAppContext] (path: String, area: String) -> String in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            return try await provider.readFile(path: path, area: area)
        }

        AsyncFunction("writeFile") { [weak moduleAppContext] (path: String, content: String, area: String) in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            try await provider.writeFile(path: path, content: content, area: area)
        }

        AsyncFunction("executeSQLite") { [weak moduleAppContext] (sql: String, params: [String]?) -> String in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            return try await provider.executeSQLite(sql: sql, params: params)
        }

        AsyncFunction("fetchURL") { [weak moduleAppContext] (urlString: String) -> String in
            guard let moduleAppContext,
                  let provider = HanlinExpoHostServicesBridge.provider(forAppContext: moduleAppContext) else {
                throw Self.missingProviderError()
            }
            return try await provider.fetchURL(urlString: urlString)
        }
    }
}
