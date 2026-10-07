import Foundation
#if canImport(CoreAI)
import CoreAI
#endif

/// Errors specific to Core AI on-device model execution.
public enum CoreAIModelError: LocalizedError, Sendable {
    case modelNotFound(String)
    case unsupportedModelFormat(String)
    case specializationFailed(String)
    case unavailable(String)
    case blockedInputModelFixture(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Core AI model file not found at: \(path)"
        case .unsupportedModelFormat(let format):
            return "Unsupported model format: \(format). Expected .aimodel package."
        case .specializationFailed(let reason):
            return "Core AI model specialization failed: \(reason)"
        case .unavailable(let reason):
            return "Core AI runtime unavailable: \(reason)"
        case .blockedInputModelFixture(let reason):
            return "Core AI input model fixture unavailable: \(reason)"
        case .cancelled:
            return "Core AI generation was cancelled."
        }
    }
}

/// Descriptor for loaded Core AI on-device models.
public struct CoreAIModelDescriptor: Sendable, Identifiable {
    public var id: String { modelPath.path }
    public let modelPath: URL
    public let modelName: String
    public let format: String
    public let isSpecialized: Bool

    public init(modelPath: URL, modelName: String, format: String = "aimodel", isSpecialized: Bool = false) {
        self.modelPath = modelPath
        self.modelName = modelName
        self.format = format
        self.isSpecialized = isSpecialized
    }
}

/// Backend execution protocol for Core AI on-device model generation.
public protocol CoreAIModelSessionBackend: Sendable {
    func generate(
        descriptor: CoreAIModelDescriptor,
        prompt: String,
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws
}

#if canImport(CoreAI)
/// Production Core AI session backend executing on-device specialized .aimodel packages.
@available(iOS 27.0, macOS 26.0, *)
public final class ProductionCoreAIModelSessionBackend: CoreAIModelSessionBackend, @unchecked Sendable {
    public init() {}

    public func generate(
        descriptor: CoreAIModelDescriptor,
        prompt: String,
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws {
        guard descriptor.isSpecialized else {
            throw CoreAIModelError.specializationFailed("Model must be specialized before generation.")
        }
        guard FileManager.default.fileExists(atPath: descriptor.modelPath.path) else {
            throw CoreAIModelError.blockedInputModelFixture("Model asset at '\(descriptor.modelPath.path)' is missing.")
        }
        throw CoreAIModelError.unavailable("Core AI execution requires iOS 27 device with supported neural engine.")
    }
}
#endif

/// Provider adapter for Apple Core AI (.aimodel) runtime.
@MainActor
public final class CoreAILanguageModelProvider: Sendable {
    public static let shared = CoreAILanguageModelProvider()

    /// Optional injected backend for testing or customized dispatch.
    public var backend: (any CoreAIModelSessionBackend)?

    public init() {}

    public func loadAndSpecialize(
        modelURL: URL,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> CoreAIModelDescriptor {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw CoreAIModelError.modelNotFound(modelURL.path)
        }
        guard modelURL.pathExtension.lowercased() == "aimodel" else {
            throw CoreAIModelError.unsupportedModelFormat(modelURL.pathExtension)
        }

        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: modelURL.path, isDirectory: &isDir)
        if !isDir.boolValue {
            let attrs = (try? FileManager.default.attributesOfItem(atPath: modelURL.path)) ?? [:]
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                throw CoreAIModelError.specializationFailed("Model asset at '\(modelURL.path)' is empty or corrupted.")
            }
        }

        try Task.checkCancellation()

        return CoreAIModelDescriptor(
            modelPath: modelURL,
            modelName: modelURL.deletingPathExtension().lastPathComponent,
            format: "aimodel",
            isSpecialized: true
        )
    }

    public func generate(
        descriptor: CoreAIModelDescriptor,
        prompt: String,
        onDelta: @escaping @Sendable (String) -> Bool
    ) async throws {
        guard descriptor.isSpecialized else {
            throw CoreAIModelError.specializationFailed("Model must be specialized before generation.")
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreAIModelError.specializationFailed("Prompt cannot be empty.")
        }
        try Task.checkCancellation()

        if let backend = self.backend {
            try await backend.generate(descriptor: descriptor, prompt: prompt, onDelta: onDelta)
            return
        }

        #if canImport(CoreAI)
        if #available(iOS 27.0, macOS 26.0, *) {
            let prod = ProductionCoreAIModelSessionBackend()
            try await prod.generate(descriptor: descriptor, prompt: prompt, onDelta: onDelta)
            return
        }
        #endif

        throw CoreAIModelError.unavailable("Core AI execution requires iOS 27 device with supported neural engine.")
    }
}
