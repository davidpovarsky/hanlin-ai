// Original shared implementation is owned by the SDK.
import HanlinAgentActivityCore

typealias NativeUIBlockType = HanlinAgentActivityCore.NativeUIBlockType
typealias NativeUIExpandedPresentation = HanlinAgentActivityCore.NativeUIExpandedPresentation
typealias NativeUIActionType = HanlinAgentActivityCore.NativeUIActionType
typealias NativeUIAction = HanlinAgentActivityCore.NativeUIAction
typealias NativeUIListItem = HanlinAgentActivityCore.NativeUIListItem
typealias NativeUIKeyValue = HanlinAgentActivityCore.NativeUIKeyValue
typealias NativeUIBlock = HanlinAgentActivityCore.NativeUIBlock
//
//  NativeUIBlock.swift
//  AI_HLY
//
//  A small, Codable, provider-neutral native UI schema for chat tool results.
//  Keep this schema intentionally narrow. Tools may return these blocks; SwiftUI renders them natively.
//

import Foundation

extension Array where Element == NativeUIBlock {
    func encodedJSONString() -> String? {
        NativeToolTraceLogger.shared.log(
            "native_ui_encoding_started",
            [
                "blockCount": count,
                "actionCount": flatActionCount,
                "actionTypes": flatActionTypes.joined(separator: ",")
            ]
        )

        do {
            let data = try JSONEncoder().encode(self)
            NativeToolTraceLogger.shared.log(
                "native_ui_encoding_completed",
                [
                    "blockCount": count,
                    "byteCount": data.count
                ]
            )
            return String(data: data, encoding: .utf8)
        } catch {
            NativeToolTraceLogger.shared.logError(
                "native_ui_encoding_failed",
                error: error,
                fields: [
                    "blockCount": count,
                    "actionCount": flatActionCount,
                    "actionTypes": flatActionTypes.joined(separator: ",")
                ]
            )
            return nil
        }
    }

    static func decode(from json: String?) -> [NativeUIBlock] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode([NativeUIBlock].self, from: data)
        } catch {
            NativeToolTraceLogger.shared.logError(
                "native_ui_decoding_failed",
                error: error,
                fields: ["byteCount": data.count]
            )
            return []
        }
    }

    private var flatActionCount: Int {
        reduce(0) { $0 + $1.allActions.count }
    }

    private var flatActionTypes: [String] {
        flatMap { $0.allActions.map { $0.type.rawValue } }
    }
}

private extension NativeUIBlock {
    var allActions: [NativeUIAction] {
        actions + items.flatMap(\.actions) + children.flatMap(\.allActions)
    }
}
