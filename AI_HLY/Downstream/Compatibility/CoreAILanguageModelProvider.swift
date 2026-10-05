import Foundation

/// Errors specific to Core AI on-device model execution.
public enum CoreAIModelError: LocalizedError, Sendable {
    case modelNotFound(String)
    case unsupportedModelFormat(String)
    case specializationFailed(String)
    case unavailable(String)
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

/// Provider adapter for Apple Core AI (.aimodel) runtime.
@MainActor
public final class CoreAILanguageModelProvider: Sendable {
    public static let shared = CoreAILanguageModelProvider()

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

        progressHandler?(0.5)
        try Task.checkCancellation()
        progressHandler?(1.0)

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
        throw CoreAIModelError.unavailable("Core AI execution requires iOS 27 device with supported neural engine.")
    }
}
