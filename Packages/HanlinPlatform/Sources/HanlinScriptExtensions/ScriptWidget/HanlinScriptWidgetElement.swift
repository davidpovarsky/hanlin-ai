import Foundation

public final class HanlinScriptWidgetElement: Identifiable, @unchecked Sendable {
    public let id: String
    public let tag: String
    public let props: [String: Any]
    public let children: [HanlinScriptWidgetElement]
    public let rawText: String?

    public init(
        tag: String,
        props: [String: Any] = [:],
        children: [HanlinScriptWidgetElement] = [],
        rawText: String? = nil,
        id: String = UUID().uuidString
    ) {
        self.tag = tag.lowercased()
        self.props = props
        self.children = children
        self.rawText = rawText
        self.id = id
    }

    public convenience init(dictionary: [String: Any]) {
        let tag = (dictionary["tag"] as? String) ?? (dictionary["type"] as? String) ?? "text"
        let props = dictionary["props"] as? [String: Any] ?? [:]
        let rawChildren = dictionary["children"]

        var parsedChildren: [HanlinScriptWidgetElement] = []
        var textContent: String? = dictionary["text"] as? String ?? props["text"] as? String

        if let childStr = rawChildren as? String {
            textContent = childStr
        } else if let childDict = rawChildren as? [String: Any] {
            parsedChildren.append(HanlinScriptWidgetElement(dictionary: childDict))
        } else if let childArr = rawChildren as? [Any] {
            for item in childArr {
                if let s = item as? String {
                    parsedChildren.append(HanlinScriptWidgetElement(tag: "text", rawText: s))
                } else if let d = item as? [String: Any] {
                    parsedChildren.append(HanlinScriptWidgetElement(dictionary: d))
                }
            }
        }

        self.init(
            tag: tag,
            props: props,
            children: parsedChildren,
            rawText: textContent,
            id: (props["id"] as? String) ?? (props["key"] as? String) ?? UUID().uuidString
        )
    }

    // Property helper accessors
    public func string(_ key: String) -> String? {
        props[key] as? String
    }

    public func number(_ key: String) -> Double? {
        (props[key] as? NSNumber)?.doubleValue
    }

    public func bool(_ key: String) -> Bool? {
        props[key] as? Bool
    }

    public func array(_ key: String) -> [Any]? {
        props[key] as? [Any]
    }

    public func dictionary(_ key: String) -> [String: Any]? {
        props[key] as? [String: Any]
    }
}
