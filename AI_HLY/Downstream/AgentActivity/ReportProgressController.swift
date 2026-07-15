//
//  ReportProgressController.swift
//  AI_HLY
//

import Foundation

struct ReportProgressController {
    private(set) var deliveredMessages: [String] = []
    private var lastDelivery: Date?
    private let minimumInterval: TimeInterval = 2
    private let maximumMessages = 8

    mutating func accept(_ message: String?, latestToolSummary: String?) -> String? {
        guard let message = ProgressSummarySanitizer.sanitize(message),
              deliveredMessages.count < maximumMessages,
              !deliveredMessages.contains(message),
              message != latestToolSummary else { return nil }
        if let lastDelivery, Date().timeIntervalSince(lastDelivery) < minimumInterval { return nil }
        deliveredMessages.append(message)
        lastDelivery = Date()
        return message
    }
}
