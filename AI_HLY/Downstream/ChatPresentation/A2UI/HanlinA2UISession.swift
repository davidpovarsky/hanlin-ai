// Enable only in the isolated exact-pin SDK harness. App wiring is a separate lease.
#if HANLIN_A2UI_POC
import A2UICore
import BasicCatalog
import Foundation
import Observation

/// One transient owner per rich result. The caller owns transcript identity and transport.
/// All graph resolution, data models, stable node identity and actions belong to upstream.
@MainActor
@Observable
final class HanlinA2UISession {
    private let processor: MessageProcessor
    private var acceptedBytes = 0
    private(set) var isClosed = false
    private(set) var surfaceIDs: [String] = []
    private(set) var failures: [String: HanlinA2UIIngress.Failure] = [:]
    private(set) var unroutedFailure: HanlinA2UIIngress.Failure?

    static let maximumSurfaces = 4
    static let maximumSessionBytes = 1_048_576

    /// Events are emitted by the official processor. No app services or tool execution are wired.
    init(onEvent: @escaping @Sendable (RendererToAgentMessage) -> Void) {
        processor = MessageProcessor(
            catalog: BasicCatalog.makeCatalog(version: .v10),
            validationConfig: ValidationConfig(
                allowOrphanComponents: true,
                allowDanglingReferences: true,
                allowMissingRoot: true,
                allowUnknownElements: false,
                protocolVersion: .v10
            )
        )
        processor.outboundListener = onEvent
    }

    func surface(_ id: String) -> SurfaceViewModel? {
        processor.surfaceGroupModel[id]
    }

    /// Consumes a complete message without changing any persisted chat schema or replay order.
    /// Rejection hides the target surface's controls until a valid update or deletion arrives.
    @discardableResult
    func receive(_ json: String) -> Result<Void, HanlinA2UIIngress.Rejection> {
        guard !isClosed else { return .failure(.init(.closed)) }
        let data = Data(json.utf8)
        var frame: HanlinA2UIIngress.Frame?
        do {
            let inspected = try HanlinA2UIIngress.inspect(data)
            frame = inspected
            guard acceptedBytes <= Self.maximumSessionBytes - data.count else {
                throw HanlinA2UIIngress.Rejection(.sessionBudget, surfaceID: inspected.surfaceID)
            }
            if inspected.operation == .createSurface,
               processor.surfaceGroupModel[inspected.surfaceID] == nil,
               processor.surfaceGroupModel.surfacesMap.count >= Self.maximumSurfaces {
                throw HanlinA2UIIngress.Rejection(.surfaceLimit, surfaceID: inspected.surfaceID)
            }
            // Contextual JSONValue.parse and processMessages are upstream APIs. Processing throws
            // after reporting errors; process(message:) alone would swallow validation failures.
            try processor.processMessages(try .parse(json))
            acceptedBytes += data.count
            failures.removeValue(forKey: inspected.surfaceID)
            unroutedFailure = nil
            refreshSurfaceIDs()
            return .success(())
        } catch {
            let rejection = (error as? HanlinA2UIIngress.Rejection)
                ?? .init(.sdkValidation, surfaceID: frame?.surfaceID)
            if let id = rejection.surfaceID,
               processor.surfaceGroupModel[id] != nil || failures[id] != nil || failures.count < Self.maximumSurfaces {
                failures[id] = rejection.failure
            } else {
                unroutedFailure = rejection.failure
            }
            refreshSurfaceIDs()
            return .failure(rejection)
        }
    }

    /// Called by the owner when the result is discarded. Old model subscriptions are disposed.
    /// Closed sessions cannot be reanimated by late stream frames.
    func close() {
        processor.outboundListener = nil
        for id in Array(processor.surfaceGroupModel.surfacesMap.keys) {
            processor.surfaceGroupModel.removeSurface(id: id)
        }
        failures.removeAll()
        unroutedFailure = nil
        surfaceIDs.removeAll()
        isClosed = true
    }

    private func refreshSurfaceIDs() {
        // Stable deterministic POC ordering only; integration must use existing transcript order.
        surfaceIDs = Set(processor.surfaceGroupModel.surfacesMap.keys)
            .union(failures.keys).sorted()
    }
}
#endif
