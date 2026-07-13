//
//  NativeUIBlock.swift
//  AI_HLY
//
//  A small, Codable, provider-neutral native UI schema for chat tool results.
//  Keep this schema intentionally narrow. Tools may return these blocks; SwiftUI renders them natively.
//

import Foundation

enum NativeUIBlockType: String, Codable, Hashable {
    case text
    case markdown
    case card
    case searchResults
    case source
    case wikipediaSummary
    case calculation
    case keyValueList
    case error
}

enum NativeUIExpandedPresentation: String, Codable, Hashable {
    case sheet
    case fullScreen
}

enum NativeUIActionType: String, Codable, Hashable {
    case openURL
    case copyText
    case nativeAppAction
    case openAppRoute
}

struct NativeUIAction: Codable, Identifiable, Hashable {
    var id: String
    var type: NativeUIActionType
    var title: String
    var systemImage: String?
    var url: String?
    var text: String?
    var nativeAction: NativeAppAction?
    var route: NativeAppRoute?
    var presentationStyle: NativeAppPresentationStyle?

    init(
        id: String = UUID().uuidString,
        type: NativeUIActionType,
        title: String,
        systemImage: String? = nil,
        url: String? = nil,
        text: String? = nil,
        nativeAction: NativeAppAction? = nil,
        route: NativeAppRoute? = nil,
        presentationStyle: NativeAppPresentationStyle? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.systemImage = systemImage
        self.url = url
        self.text = text
        self.nativeAction = nativeAction
        self.route = route
        self.presentationStyle = presentationStyle
    }
}

struct NativeUIListItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String?
    var body: String?
    var imageURL: String?
    var url: String?
    var actions: [NativeUIAction]

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        imageURL: String? = nil,
        url: String? = nil,
        actions: [NativeUIAction] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.imageURL = imageURL
        self.url = url
        self.actions = actions
    }
}

struct NativeUIKeyValue: Codable, Identifiable, Hashable {
    var id: String
    var key: String
    var value: String

    init(id: String = UUID().uuidString, key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

struct NativeUIBlock: Codable, Identifiable, Hashable {
    var id: String
    var type: NativeUIBlockType
    var title: String?
    var subtitle: String?
    var body: String?
    var footnote: String?
    var systemImage: String?
    var imageURL: String?
    var url: String?
    var items: [NativeUIListItem]
    var keyValues: [NativeUIKeyValue]
    var actions: [NativeUIAction]
    var children: [NativeUIBlock]
    var compactLineLimit: Int?
    var compactItemLimit: Int?
    var preferredExpandedPresentation: NativeUIExpandedPresentation?
    var allowsExpansion: Bool?

    init(
        id: String = UUID().uuidString,
        type: NativeUIBlockType,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        footnote: String? = nil,
        systemImage: String? = nil,
        imageURL: String? = nil,
        url: String? = nil,
        items: [NativeUIListItem] = [],
        keyValues: [NativeUIKeyValue] = [],
        actions: [NativeUIAction] = [],
        children: [NativeUIBlock] = [],
        compactLineLimit: Int? = nil,
        compactItemLimit: Int? = nil,
        preferredExpandedPresentation: NativeUIExpandedPresentation? = nil,
        allowsExpansion: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.footnote = footnote
        self.systemImage = systemImage
        self.imageURL = imageURL
        self.url = url
        self.items = items
        self.keyValues = keyValues
        self.actions = actions
        self.children = children
        self.compactLineLimit = compactLineLimit
        self.compactItemLimit = compactItemLimit
        self.preferredExpandedPresentation = preferredExpandedPresentation
        self.allowsExpansion = allowsExpansion
    }
}

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
