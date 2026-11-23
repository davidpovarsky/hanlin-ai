import Foundation


public enum NativeUIBlockType: String, Codable, Hashable {
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

public enum NativeUIExpandedPresentation: String, Codable, Hashable {
    case sheet
    case fullScreen
}

public enum NativeUIActionType: String, Codable, Hashable {
    case openURL
    case copyText
    case nativeAppAction
    case openAppRoute
}

public struct NativeUIAction: Codable, Identifiable, Hashable {
    public var id: String
    public var type: NativeUIActionType
    public var title: String
    public var systemImage: String?
    public var url: String?
    public var text: String?
    public var nativeAction: NativeAppAction?
    public var route: NativeAppRoute?
    public var presentationStyle: NativeAppPresentationStyle?

    public init(
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

public struct NativeUIListItem: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var body: String?
    public var imageURL: String?
    public var url: String?
    public var actions: [NativeUIAction]

    public init(
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

public struct NativeUIKeyValue: Codable, Identifiable, Hashable {
    public var id: String
    public var key: String
    public var value: String

    public init(id: String = UUID().uuidString, key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct NativeUIBlock: Codable, Identifiable, Hashable, @unchecked Sendable {
    public var id: String
    public var type: NativeUIBlockType
    public var title: String?
    public var subtitle: String?
    public var body: String?
    public var footnote: String?
    public var systemImage: String?
    public var imageURL: String?
    public var embeddedImageBase64: String?
    public var embeddedImageMIMEType: String?
    public var url: String?
    public var items: [NativeUIListItem]
    public var keyValues: [NativeUIKeyValue]
    public var actions: [NativeUIAction]
    public var children: [NativeUIBlock]
    public var compactLineLimit: Int?
    public var compactItemLimit: Int?
    public var preferredExpandedPresentation: NativeUIExpandedPresentation?
    public var allowsExpansion: Bool?

    public init(
        id: String = UUID().uuidString,
        type: NativeUIBlockType,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        footnote: String? = nil,
        systemImage: String? = nil,
        imageURL: String? = nil,
        embeddedImageBase64: String? = nil,
        embeddedImageMIMEType: String? = nil,
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
        self.embeddedImageBase64 = embeddedImageBase64
        self.embeddedImageMIMEType = embeddedImageMIMEType
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
