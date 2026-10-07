import Foundation

/// Errors specific to Apple Foundation Models local provider execution.
public enum AppleFoundationModelError: LocalizedError, Sendable {
    case unavailable(String)
    case unsupportedModality(String)
    case cancelled
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return "Apple Foundation Models unavailable on this device/configuration: \(reason)"
        case .unsupportedModality(let modality):
            return "Unsupported modality for selected Apple Foundation Model: \(modality)"
        case .cancelled:
            return "Generation was cancelled."
        case .executionFailed(let reason):
            return "Apple Foundation Model execution failed: \(reason)"
        }
    }
}

/// Dynamic capability inspector for Apple Foundation Models (iOS 27 / macOS 26).
public struct AppleFoundationModelCapability: Sendable {
    public let isAvailable: Bool
    public let supportsMultimodal: Bool
    public let modelIdentifier: String
    public let unavailabilityReason: String?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var _overrideCapability: AppleFoundationModelCapability? = nil

    public static var overrideCapability: AppleFoundationModelCapability? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _overrideCapability
        }
        set {
            lock.lock()
            _overrideCapability = newValue
            lock.unlock()
        }
    }

    public static func current() -> AppleFoundationModelCapability {
        if let override = overrideCapability {
            return override
        }
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 26.0, *) {
            return AppleFoundationModelCapability(
                isAvailable: false,
                supportsMultimodal: false,
                modelIdentifier: "apple.system.language-model",
                unavailabilityReason: "Foundation Models system weights are not preloaded on this host."
            )
        }
        #endif
        return AppleFoundationModelCapability(
            isAvailable: false,
            supportsMultimodal: false,
            modelIdentifier: "apple.system.language-model",
            unavailabilityReason: "Apple Intelligence / Foundation Models requires supported Apple Silicon hardware (A17 Pro, M-series or newer) and iOS 27 / macOS 26."
        )
    }
}

/// Backend seam for Foundation Models generation.
public protocol AppleFoundationModelSessionBackend: Sendable {
    func generate(
        prompt: String,
        images: [Data],
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws
}

/// Thin local provider adapter for Apple Foundation Models feeding Hanlin's conversation
/// and canonical tool architecture without creating a parallel tool loop.
@MainActor
public final class AppleFoundationModelsProvider: Sendable {
    public static let shared = AppleFoundationModelsProvider()

    public var backend: (any AppleFoundationModelSessionBackend)? = nil

    public init() {}

    public func isAvailable() -> Bool {
        AppleFoundationModelCapability.current().isAvailable
    }

    public func generate(
        prompt: String,
        images: [Data] = [],
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws {
        let capability = AppleFoundationModelCapability.current()
        guard capability.isAvailable else {
            throw AppleFoundationModelError.unavailable(capability.unavailabilityReason ?? "Device does not support Apple Foundation Models.")
        }

        if !images.isEmpty && !capability.supportsMultimodal {
            throw AppleFoundationModelError.unsupportedModality("Images are not supported by the current model capability.")
        }

        try Task.checkCancellation()

        if let backend = self.backend {
            try await backend.generate(prompt: prompt, images: images, onDelta: onDelta)
            return
        }

        throw AppleFoundationModelError.unavailable("On-device model weights not loaded on this host.")
    }
}
