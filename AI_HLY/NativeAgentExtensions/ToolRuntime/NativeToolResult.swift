//
//  NativeToolResult.swift
//  AI_HLY
//

import Foundation

struct NativeToolResult {
    var modelText: String
    var userText: String?
    var uiBlocks: [NativeUIBlock]

    var isError: Bool {
        uiBlocks.contains { $0.type == .error }
    }

    init(
        modelText: String,
        userText: String? = nil,
        uiBlocks: [NativeUIBlock] = []
    ) {
        self.modelText = modelText
        self.userText = userText
        self.uiBlocks = uiBlocks
    }
}
