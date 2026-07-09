//
//  NativeToolResult.swift
//  AI_HLY
//

import Foundation

struct NativeToolResult {
    var modelText: String
    var userText: String?
    var uiBlocks: [NativeUIBlock]

    /// Used by tool_search. The next model request should load full schemas for these tools.
    var deferredToolNames: [String]

    init(
        modelText: String,
        userText: String? = nil,
        uiBlocks: [NativeUIBlock] = [],
        deferredToolNames: [String] = []
    ) {
        self.modelText = modelText
        self.userText = userText
        self.uiBlocks = uiBlocks
        self.deferredToolNames = deferredToolNames
    }
}
