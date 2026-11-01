//
//  HanlinPendingFirstTurn.swift
//  AI_HLY
//
//  Idempotent first-turn handoff state machine for the compact Home composer (§4.4).
//  Guarantees that typing on the compact Home screen never creates an empty persisted
//  ChatRecords row, that tapping Send / Return creates at most one ChatRecords via
//  ListView's canonical record factory, and that the payload is transferred and sent
//  at most once when the target ChatView finishes handleOnAppear() and registers its live endpoint.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct HanlinPendingFirstTurn: Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case created
        case awaitingEndpoint(targetChatID: UUID)
        case dispatched(targetChatID: UUID)
        case cancelled(reason: String)
        case failed(reason: String)
    }

    let submissionID: UUID
    let text: String
    let images: [UIImage]
    let documentURLs: [URL]
    let selectedURLs: [String]
    let prompts: [PromptRepo]
    let selectedModelIndex: Int
    let ifSearch: Bool
    let ifKnowledge: Bool
    let ifToolUse: Bool
    let ifThink: Bool
    let thinkingLength: Int
    let ifPlanning: Bool
    let ifAudio: Bool
    let selectedImageSize: String
    let imageReversePrompt: String
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    let maxMessagesNum: Int

    var status: Status

    var id: UUID { submissionID }

    var targetChatID: UUID? {
        switch status {
        case .awaitingEndpoint(let id), .dispatched(let id):
            return id
        default:
            return nil
        }
    }

    var isPendingHandoff: Bool {
        switch status {
        case .created, .awaitingEndpoint:
            return true
        case .dispatched, .cancelled, .failed:
            return false
        }
    }
}
