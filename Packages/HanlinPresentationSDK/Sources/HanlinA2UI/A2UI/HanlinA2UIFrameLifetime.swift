#if canImport(SwiftUI)
import Foundation

/// Shared presentation lifetime policy for live owners and effect-free scratch validation.
/// Schema, graph and binding validation remain entirely in the official processor.
@MainActor
public struct HanlinA2UIFrameLifetime {
    private var retiredSurfaceIDs: Set<String> = []

    public init() {}

    public mutating func receive(_ json: String, in session: HanlinA2UISession) -> Result<Void, HanlinA2UIResultAdmissionError> {
        let frame = try? HanlinA2UIIngress.inspect(Data(json.utf8))
        if let frame, retiredSurfaceIDs.contains(frame.surfaceID) { return .failure(.retiredSurfaceID) }
        let deletingOwnedSurface = frame.map {
            $0.operation == .deleteSurface && session.surface($0.surfaceID) != nil
        } ?? false
        let result = session.receive(json).mapError(HanlinA2UIResultAdmissionError.rejected)
        if let frame, deletingOwnedSurface, session.surface(frame.surfaceID) == nil {
            retiredSurfaceIDs.insert(frame.surfaceID)
        }
        return result
    }
}
#endif
