//
//  ChatHostPresentationPolicy.swift
//  AI_HLY
//
//  Centralized host presentation policy governing transcript geometry,
//  embedded result sizing, execution timeline constraints, and responsive
//  iPhone / iPad adaptations.
//

import SwiftUI

@MainActor
enum ChatHostPresentationPolicy {

  // MARK: - Transcript & Layout Insets

  static func transcriptHorizontalPadding(isRegularWidth: Bool) -> CGFloat {
    isRegularWidth ? 32 : 16
  }

  static func maxTranscriptContentWidth(isRegularWidth: Bool) -> CGFloat {
    isRegularWidth ? 768 : .infinity
  }

  // MARK: - User Message Sizing

  static func maxUserMessageWidth(containerWidth: CGFloat, isRegularWidth: Bool) -> CGFloat {
    if isRegularWidth {
      return min(containerWidth * 0.70, 540)
    } else {
      return min(containerWidth * 0.82, 380)
    }
  }

  // MARK: - Embedded Result Sizing

  static func maxEmbeddedResultWidth(containerWidth: CGFloat, isRegularWidth: Bool) -> CGFloat {
    if isRegularWidth {
      return min(containerWidth, 720)
    } else {
      return containerWidth
    }
  }

  /// Hard upper maximum height for any embedded result in the transcript.
  /// Results must never expand beyond this without using full-screen or sheet expansion.
  static func maxEmbeddedResultHeight(isRegularWidth: Bool) -> CGFloat {
    isRegularWidth ? 540 : 420
  }

  /// Preset heights for embedded results.
  static func height(for preset: ChatHostSizePreset, isRegularWidth: Bool) -> CGFloat {
    switch preset {
    case .compact:
      return isRegularWidth ? 160 : 140
    case .standard:
      return isRegularWidth ? 260 : 220
    case .tall:
      return isRegularWidth ? 400 : 320
    case .expanded:
      return maxEmbeddedResultHeight(isRegularWidth: isRegularWidth)
    }
  }

  // MARK: - Execution UI Sizing

  /// Maximum vertical height for tool execution timeline items.
  /// Execution UI must remain compact and subordinate to content.
  static let maxExecutionHeight: CGFloat = 160
  static let standardExecutionRowHeight: CGFloat = 36

  // MARK: - Spacing & Visual Geometry

  static let messageSpacing: CGFloat = 14
  static let consecutiveAssistantSpacing: CGFloat = 8
  static let executionToResultSpacing: CGFloat = 8
  static let resultToProseSpacing: CGFloat = 10
  static let userBubbleCornerRadius: CGFloat = 18
  static let resultContainerCornerRadius: CGFloat = 16
}
