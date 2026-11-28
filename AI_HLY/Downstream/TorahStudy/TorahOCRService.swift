import Foundation
import TorahLibraryKit
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UIKit) && canImport(ImageIO)
extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif

public enum TorahOCRService {
    /// Performs local OCR on an image data using Apple Vision framework.
    public static func performLocalOCR(
        imageData: Data,
        region: (x: Double, y: Double, width: Double, height: Double)? = nil
    ) async throws -> (rawText: String, lines: [(text: String, box: (x: Double, y: Double, width: Double, height: Double), confidence: Double)]) {
        #if canImport(Vision) && canImport(UIKit)
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else {
            throw ITorahSharedStorageError.directoryNotFound("Invalid image data")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ("", []))
                    return
                }

                var lines: [(text: String, box: (x: Double, y: Double, width: Double, height: Double), confidence: Double)] = []
                var fullText: [String] = []

                for obs in observations {
                    guard let topCandidate = obs.topCandidates(1).first else { continue }
                    // Convert bounding box from Vision coordinates (origin bottom-left) to top-left coordinates
                    let box = (
                        x: Double(obs.boundingBox.origin.x),
                        y: Double(1.0 - (obs.boundingBox.origin.y + obs.boundingBox.size.height)),
                        width: Double(obs.boundingBox.size.width),
                        height: Double(obs.boundingBox.size.height)
                    )
                    lines.append((
                        text: topCandidate.string,
                        box: box,
                        confidence: Double(topCandidate.confidence)
                    ))
                    fullText.append(topCandidate.string)
                }

                continuation.resume(returning: (fullText.joined(separator: "\n"), lines))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["he-IL", "he", "en-US"]
            request.usesLanguageCorrection = false // Preserve exact rabbinic / acronym spelling

            if let r = region {
                // Coordinate transform: SwiftUI/UIKit has (0,0) at top-left, Vision has (0,0) at bottom-left
                let clampedX = max(0.0, min(1.0, r.x))
                let clampedW = max(0.0, min(1.0 - clampedX, r.width))
                let clampedTopY = max(0.0, min(1.0, r.y))
                let clampedH = max(0.0, min(1.0 - clampedTopY, r.height))
                let visionY = max(0.0, min(1.0, 1.0 - (clampedTopY + clampedH)))
                request.regionOfInterest = CGRect(x: clampedX, y: visionY, width: clampedW, height: clampedH)
            }

            let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        throw ITorahSharedStorageError.directoryNotFound("Apple Vision framework is unavailable in this environment")
        #endif
    }
}
