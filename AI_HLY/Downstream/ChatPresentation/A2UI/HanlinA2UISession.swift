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
    private let eventRelay: HanlinA2UIEventRelay
    private var acceptedBytes = 0
    private(set) var isClosed = false
    private(set) var surfaceIDs: [String] = []
    private(set) var failures: [String: HanlinA2UIIngress.Failure] = [:]
    private(set) var unroutedFailure: HanlinA2UIIngress.Failure?

    static let maximumSurfaces = 4
    static let maximumSessionBytes = 1_048_576

    /// Only resolved user events and renderer errors leave this POC. RPC stays disabled by the
    /// SDK's absent-listener policy; installing an outboundListener would enable agent calls.
    init(onEvent: @escaping @Sendable (RendererToAgentMessage) -> Void) {
        let relay = HanlinA2UIEventRelay(onEvent: onEvent)
        eventRelay = relay
        processor = MessageProcessor(
            catalog: BasicCatalog.makeCatalog(version: .v10),
            actionHandler: relay,
            validationConfig: ValidationConfig(
                allowOrphanComponents: true,
                allowDanglingReferences: true,
                allowMissingRoot: true,
                allowUnknownElements: false,
                protocolVersion: .v10
            )
        )
        relay.processor = processor
        // Deliberately leave outboundListener nil, including on every created surface.
    }

    func surface(_ id: String) -> SurfaceViewModel? {
        processor.surfaceGroupModel[id]
    }

    /// Consumes a complete message without changing any persisted chat schema or replay order.
    /// Only a validated update/delete frame targeting an SDK-owned surface can hide its controls.
    /// Uncorrelated input is returned as an error without changing existing surface presentation.
    @discardableResult
    func receive(_ json: String) -> Result<Void, HanlinA2UIIngress.Rejection> {
        guard !isClosed else { return .failure(.init(.closed)) }
        let data = Data(json.utf8)
        var frame: HanlinA2UIIngress.Frame?
        do {
            let inspected = try HanlinA2UIIngress.inspect(data)
            frame = inspected
            guard acceptedBytes <= Self.maximumSessionBytes - data.count else {
                throw HanlinA2UIIngress.Rejection(.sessionBudget)
            }
            if inspected.operation == .createSurface,
               processor.surfaceGroupModel[inspected.surfaceID] == nil,
               processor.surfaceGroupModel.surfacesMap.count >= Self.maximumSurfaces {
                throw HanlinA2UIIngress.Rejection(.surfaceLimit)
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
            let failure = (error as? HanlinA2UIIngress.Rejection)?.failure ?? .sdkValidation
            let sdkError = error as? any A2UIError
            let diagnostics = sdkError?.details.prefix(8).map {
                HanlinA2UIIngress.SDKDiagnostic(code: $0.code)
            } ?? []
            var correlatedID: String?
            // SDK ownership is the only source of surface membership. Raw IDs in an error,
            // a rejected create request, or failure bookkeeping never grant target authority.
            if let frame, frame.operation != .createSurface,
               processor.surfaceGroupModel[frame.surfaceID] != nil {
                correlatedID = frame.surfaceID
                failures[frame.surfaceID] = failure
            } else if failure == .malformedEnvelope,
                      processor.surfaceGroupModel.surfacesMap.isEmpty {
                // Result-level malformed content may replace an empty placeholder, not live UI.
                unroutedFailure = failure
            }
            refreshSurfaceIDs()
            return .failure(.init(
                failure, surfaceID: correlatedID,
                sdkErrorType: sdkError.map { String(reflecting: type(of: $0)) },
                diagnostics: diagnostics
            ))
        }
    }

    /// Called by the owner when the result is discarded. Old model subscriptions are disposed.
    /// Closed sessions cannot be reanimated by late stream frames.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        eventRelay.close()
        processor.outboundListener = nil
        processor.dispose()
        failures.removeAll()
        unroutedFailure = nil
        surfaceIDs.removeAll()
    }

    #if DEBUG
    /// Exact-pin tests seed a real pending SDK call to verify defensive disposal. Not transport API.
    var sdkProcessorForLifecycleTests: MessageProcessor { processor }
    #endif

    private func refreshSurfaceIDs() {
        // Stable deterministic POC ordering only; integration must use existing transcript order.
        let ownedIDs = Set(processor.surfaceGroupModel.surfacesMap.keys)
        failures = failures.filter { ownedIDs.contains($0.key) }
        surfaceIDs = ownedIDs.sorted()
    }
}

/// The official ActionHandling hook delivers already-resolved events without enabling RPC.
/// Its nonisolated callbacks cross to the UI actor; close revokes even callbacks already queued.
@MainActor
private final class HanlinA2UIEventRelay: ActionHandling {
    private var onEvent: (@Sendable (RendererToAgentMessage) -> Void)?
    weak var processor: MessageProcessor?

    init(onEvent: @escaping @Sendable (RendererToAgentMessage) -> Void) {
        self.onEvent = onEvent
    }

    func close() { onEvent = nil }

    nonisolated func handle(action: ResolvedAction, from surfaceID: String) {
        Task { @MainActor [weak self] in
            guard let callback = self?.onEvent,
                  case .event(let name, let context, let userMessage) = action.identity else { return }
            callback(.action(RendererAction(
                name: name,
                surfaceID: surfaceID,
                sourceComponentID: action.sourceComponentID ?? "",
                timestamp: ISO8601DateFormatter().string(from: Date()),
                context: context ?? [:],
                userMessage: userMessage,
                metadata: action.metadata,
                version: .v10
            )))
        }
    }

    nonisolated func handle(error: RendererError, from surfaceID: String) {
        // Do not capture the raw SDK error in the queued callback: it can contain payload paths,
        // messages and expressions. Only a finite code crosses to the UI actor.
        let code: String
        switch error {
        case .validationFailed(let failure):
            code = HanlinA2UIIngress.SDKDiagnostic(code: failure.code.rawValue).code
        case .generic(let failure):
            code = HanlinA2UIIngress.SDKDiagnostic(code: failure.code).code
        }
        Task { @MainActor [weak self] in
            guard let self, let callback = self.onEvent,
                  self.processor?.surfaceGroupModel[surfaceID] != nil else { return }
            let safe: RendererError
            if let validationCode = A2UICore.ValidationFailedError.Code(rawValue: code) {
                // This official wire model requires a path. Use one fixed category, no SDK path.
                safe = .validationFailed(A2UICore.ValidationFailedError(
                    code: validationCode, surfaceID: surfaceID, path: "validation",
                    message: "Content could not be processed.", version: .v10
                ))
            } else {
                safe = .generic(A2UICore.GenericError(
                    code: code, surfaceID: surfaceID,
                    message: "Content could not be processed.", version: .v10
                ))
            }
            callback(.error(safe))
        }
    }
}
#endif
