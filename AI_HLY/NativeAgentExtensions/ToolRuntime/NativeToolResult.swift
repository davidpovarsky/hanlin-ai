//
//  NativeToolResult.swift
//  AI_HLY
//

import Foundation

struct NativeToolResult {
    var modelText: String
    var userText: String?
    var uiBlocks: [NativeUIBlock]

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
