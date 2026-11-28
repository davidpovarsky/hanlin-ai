import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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
            let systemAvailable = SystemLanguageModel.default.isAvailable
            return AppleFoundationModelCapability(
                isAvailable: systemAvailable,
                supportsMultimodal: false,
                modelIdentifier: "apple.system.language-model",
                unavailabilityReason: systemAvailable ? nil : "SystemLanguageModel is present in SDK but on-device model weights are not loaded or device hardware is incompatible."
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

#if canImport(FoundationModels)
/// Official production Apple Foundation Models backend executing through SystemLanguageModel and LanguageModelSession.
@available(iOS 27.0, macOS 26.0, *)
public final class ProductionFoundationModelSessionBackend: AppleFoundationModelSessionBackend, @unchecked Sendable {
    public init() {}

    public func generate(
        prompt: String,
        images: [Data],
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws {
        guard SystemLanguageModel.default.isAvailable else {
            throw AppleFoundationModelError.unavailable("SystemLanguageModel is not ready or weights are not loaded on this device.")
        }
        let session = LanguageModelSession()
        let stream = session.streamResponse(to: prompt)
        var previousLength = 0
        for try await snapshot in stream {
            try Task.checkCancellation()
            let fullText = snapshot.content
            let delta: String
            if fullText.count >= previousLength {
                let startIndex = fullText.index(fullText.startIndex, offsetBy: previousLength)
                delta = String(fullText[startIndex...])
                previousLength = fullText.count
            } else {
                delta = fullText
                previousLength = fullText.count
            }
            guard !delta.isEmpty else { continue }
            let shouldContinue = onDelta(delta)
            if !shouldContinue {
                break
            }
        }
    }
}
#endif

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

        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 26.0, *) {
            let productionBackend = ProductionFoundationModelSessionBackend()
            try await productionBackend.generate(prompt: prompt, images: images, onDelta: onDelta)
            return
        }
        #endif

        throw AppleFoundationModelError.unavailable("On-device model weights not loaded on this host.")
    }
}
