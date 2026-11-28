//
//  ChatMessages+NativeUI.swift
//  AI_HLY
//
//  Requires one stored property to be added to ChatMessages in the original model:
//      var nativeUIBlocksJSON: String?
//  This extension keeps the decoding/encoding logic outside the original model file.
//

import Foundation

extension ChatMessages {
    var nativeUIBlocks: [NativeUIBlock] {
        get { [NativeUIBlock].decode(from: nativeUIBlocksJSON) }
        set { nativeUIBlocksJSON = newValue.encodedJSONString() }
    }

    func appendNativeUIBlocks(_ blocks: [NativeUIBlock]) {
        guard !blocks.isEmpty else { return }
        var existing = nativeUIBlocks
        existing.append(contentsOf: blocks)
        nativeUIBlocks = existing
    }
}
