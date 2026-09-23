//
//  NativeToolResult.swift
//  AI_HLY
//

import Foundation
import HanlinPlatformContracts

enum NativeToolExecutionOutcome: String, Codable, CaseIterable, Sendable {
    case succeeded
    case failed
    case invalidArguments
    case rejectedByCapability
    case rejectedByAvailability
    case timedOut
    case cancelled

    var isSuccess: Bool { self == .succeeded }
}

struct NativeToolExecutionDiagnostics: Sendable {
    var canonicalLogicalToolID: String?
    var modelFacingAlias: String?
    var backendRoute: String?
    var source: String?
    var runtimeKind: String?
    var failureCategory: String?
    var argumentKeys: [String] = []
    var capabilityDecision: String?
    var availabilityDecision: String?
    var runtimeStateBefore: String?
    var runtimeStateAfter: String?
    var exitCode: Int?
    var didTimeOut = false
    var wasCancelled = false
    var outputWasTruncated = false
    var stdoutByteCount = 0
    var stderrByteCount = 0
    var valueType: String?
    var modelResultByteCount = 0
    var userResultByteCount = 0
    var uiBlockTypes: [String] = []
    var callerIdentity: String?
}

struct NativeToolResult {
    var modelText: String
    var userText: String?
    var uiBlocks: [NativeUIBlock]
    var outcome: NativeToolExecutionOutcome
    var diagnostics: NativeToolExecutionDiagnostics
    var embeddedPayload: HanlinEmbeddedResultPayload?
    var isStoreEligible: Bool = false
    var fullResultPayload: String? = nil
    var fullResultMIMEType: String? = nil
    var resultReference: String? = nil

    var isError: Bool {
        !outcome.isSuccess
    }

    init(
        modelText: String,
        userText: String? = nil,
        uiBlocks: [NativeUIBlock] = [],
        outcome: NativeToolExecutionOutcome? = nil,
        diagnostics: NativeToolExecutionDiagnostics = .init(),
        embeddedPayload: HanlinEmbeddedResultPayload? = nil,
        isStoreEligible: Bool = false,
        fullResultPayload: String? = nil,
        fullResultMIMEType: String? = nil,
        resultReference: String? = nil
    ) {
        self.modelText = modelText
        self.userText = userText
        self.uiBlocks = uiBlocks
        self.outcome = outcome ?? (uiBlocks.contains { $0.type == .error } ? .failed : .succeeded)
        self.diagnostics = diagnostics
        self.diagnostics.modelResultByteCount = modelText.utf8.count
        self.diagnostics.userResultByteCount = userText?.utf8.count ?? 0
        self.diagnostics.uiBlockTypes = uiBlocks.map { String(describing: $0.type) }
        self.embeddedPayload = embeddedPayload
        self.isStoreEligible = isStoreEligible
        self.fullResultPayload = fullResultPayload
        self.fullResultMIMEType = fullResultMIMEType
        self.resultReference = resultReference
    }
}
