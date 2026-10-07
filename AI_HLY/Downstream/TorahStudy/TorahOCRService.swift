import Foundation
import TorahLibraryKit
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
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
                    let box = (
                        x: Double(obs.boundingBox.origin.x),
                        y: Double(obs.boundingBox.origin.y),
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
                request.regionOfInterest = CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        // Fallback for non-Apple test environments
        return ("", [])
        #endif
    }
}
