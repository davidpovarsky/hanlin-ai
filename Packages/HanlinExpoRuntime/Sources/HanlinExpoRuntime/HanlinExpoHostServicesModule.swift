import ExpoModulesCore
import Foundation

public struct HanlinExpoHostServicesBinding: @unchecked Sendable {
    public typealias CapabilityHandler = @MainActor @Sendable (String) -> Bool
    public typealias InvocationHandler = @MainActor @Sendable (String, String) async throws -> String

    let hasCapability: CapabilityHandler
    let invoke: InvocationHandler

    public init(
        hasCapability: @escaping CapabilityHandler,
        invoke: @escaping InvocationHandler
    ) {
        self.hasCapability = hasCapability
        self.invoke = invoke
    }
}

@MainActor
public enum HanlinExpoHostServicesRuntime {
    private static var binding: HanlinExpoHostServicesBinding?

    public static func install(_ binding: HanlinExpoHostServicesBinding) {
        self.binding = binding
    }

    public static func uninstall() {
        binding = nil
    }

    static func hasCapability(_ capability: String) -> Bool {
        binding?.hasCapability(capability) ?? false
    }

    static func invoke(operation: String, payloadJSON: String) async throws -> String {
        guard let binding else {
            throw HanlinExpoError.bootstrapFailed("Hanlin Host Services are not bound to the active Expo session.")
        }
        return try await binding.invoke(operation, payloadJSON)
    }
}

public final class HanlinExpoHostServicesModule: Module {
    public func definition() -> ModuleDefinition {
        Name("HanlinHostServices")

        AsyncFunction("hasCapability") { (capability: String) async -> Bool in
            await HanlinExpoHostServicesRuntime.hasCapability(capability)
        }

        AsyncFunction("invoke") { (operation: String, payloadJSON: String) async throws -> String in
            try await HanlinExpoHostServicesRuntime.invoke(operation: operation, payloadJSON: payloadJSON)
        }
    }
}
