import Foundation
import ExpoModulesCore

public final class HanlinHostServicesModule: Module, @unchecked Sendable {
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

        AsyncFunction("executeRuntime") { [weak self, weak moduleAppContext] (kind: String, source: String) -> String in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=executeRuntime kind=\(kind)")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executeRuntime: missing provider")
                throw Self.missingProviderError()
            }
            do {
                return try await provider.executeRuntime(kind: kind, source: source)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executeRuntime: \(error)")
                throw error
            }
        }

        AsyncFunction("executeNode") { [weak self, weak moduleAppContext] (source: String) -> String in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=executeNode")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executeNode: missing provider")
                throw Self.missingProviderError()
            }
            do {
                return try await provider.executeNode(source: source)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executeNode: \(error)")
                throw error
            }
        }

        AsyncFunction("executePython") { [weak self, weak moduleAppContext] (source: String) -> String in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=executePython")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executePython: missing provider")
                throw Self.missingProviderError()
            }
            do {
                return try await provider.executePython(source: source)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executePython: \(error)")
                throw error
            }
        }

        AsyncFunction("readFile") { [weak self, weak moduleAppContext] (path: String, area: String) -> String in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=readFile path=\(path) area=\(area)")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=readFile: missing provider")
                throw Self.missingProviderError()
            }
            do {
                return try await provider.readFile(path: path, area: area)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=readFile: \(error)")
                throw error
            }
        }

        AsyncFunction("writeFile") { [weak self, weak moduleAppContext] (path: String, content: String, area: String) in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=writeFile path=\(path) area=\(area)")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=writeFile: missing provider")
                throw Self.missingProviderError()
            }
            do {
                try await provider.writeFile(path: path, content: content, area: area)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=writeFile: \(error)")
                throw error
            }
        }

        AsyncFunction("executeSQLite") { [weak self, weak moduleAppContext] (sql: String, params: [String]?) -> String in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=executeSQLite sql=\(sql)")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executeSQLite: missing provider")
                throw Self.missingProviderError()
            }
            do {
                return try await provider.executeSQLite(sql: sql, params: params)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=executeSQLite: \(error)")
                throw error
            }
        }

        AsyncFunction("fetchURL") { [weak self, weak moduleAppContext] (urlString: String) -> String in
            NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_INVOKE method=fetchURL url=\(urlString)")
            let context = self?.appContext ?? moduleAppContext
            let provider = (context != nil ? HanlinExpoHostServicesBridge.provider(forAppContext: context!) : nil)
                ?? HanlinExpoHostServicesBridge.currentProvider
            guard let provider else {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=fetchURL: missing provider")
                throw Self.missingProviderError()
            }
            do {
                return try await provider.fetchURL(urlString: urlString)
            } catch {
                NSLog("%@", "HANLIN_EXPO_HOSTSERVICES_ERROR method=fetchURL: \(error)")
                throw error
            }
        }
    }
}
