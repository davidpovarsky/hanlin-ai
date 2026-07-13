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
    case activityTimeline
}

enum NativeUIActivityStatus: String, Codable, Hashable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}

enum NativeUIActivityDetailStyle: String, Codable, Hashable {
    case plain
    case markdown
    case code
    case search
    case keyValue
    case richResult
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

    var activityStatus: NativeUIActivityStatus?
    var activityDetailStyle: NativeUIActivityDetailStyle?
    var startedAt: Date?
    var completedAt: Date?
    var input: String?
    var output: String?
    var queryItems: [String]

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
        activityStatus: NativeUIActivityStatus? = nil,
        activityDetailStyle: NativeUIActivityDetailStyle? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        input: String? = nil,
        output: String? = nil,
        queryItems: [String] = []
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
        self.activityStatus = activityStatus
        self.activityDetailStyle = activityDetailStyle
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.input = input
        self.output = output
        self.queryItems = queryItems
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case subtitle
        case body
        case footnote
        case systemImage
        case imageURL
        case url
        case items
        case keyValues
        case actions
        case children
        case activityStatus
        case activityDetailStyle
        case startedAt
        case completedAt
        case input
        case output
        case queryItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(NativeUIBlockType.self, forKey: .type)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        footnote = try container.decodeIfPresent(String.self, forKey: .footnote)
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        items = try container.decodeIfPresent([NativeUIListItem].self, forKey: .items) ?? []
        keyValues = try container.decodeIfPresent([NativeUIKeyValue].self, forKey: .keyValues) ?? []
        actions = try container.decodeIfPresent([NativeUIAction].self, forKey: .actions) ?? []
        children = try container.decodeIfPresent([NativeUIBlock].self, forKey: .children) ?? []
        activityStatus = try container.decodeIfPresent(NativeUIActivityStatus.self, forKey: .activityStatus)
        activityDetailStyle = try container.decodeIfPresent(NativeUIActivityDetailStyle.self, forKey: .activityDetailStyle)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        input = try container.decodeIfPresent(String.self, forKey: .input)
        output = try container.decodeIfPresent(String.self, forKey: .output)
        queryItems = try container.decodeIfPresent([String].self, forKey: .queryItems) ?? []
    }
}

extension Array where Element == NativeUIBlock {
    func encodedJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> [NativeUIBlock] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([NativeUIBlock].self, from: data)) ?? []
    }
}