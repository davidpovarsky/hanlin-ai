//
//  ChatMessages+NativeUI.swift
//  AI_HLY
//
//  Requires one stored property to be added to ChatMessages in the original model:
//      var nativeUIBlocksJSON: String?
//  This extension keeps the decoding/encoding and downstream compatibility logic
//  outside the original model file.
//

import Foundation

extension ChatMessages {
    private var storedNativeUIBlocks: [NativeUIBlock] {
        [NativeUIBlock].decode(from: nativeUIBlocksJSON)
    }

    var nativeUIBlocks: [NativeUIBlock] {
        get {
            LegacyToolActivityAdapter.blocks(
                for: self,
                storedBlocks: storedNativeUIBlocks
            )
        }
        set {
            nativeUIBlocksJSON = newValue.encodedJSONString()
        }
    }

    func appendNativeUIBlocks(_ blocks: [NativeUIBlock]) {
        guard !blocks.isEmpty else { return }
        let merged = LegacyToolActivityAdapter.merging(
            existing: storedNativeUIBlocks,
            appended: blocks
        )
        nativeUIBlocksJSON = merged.encodedJSONString()
    }
}