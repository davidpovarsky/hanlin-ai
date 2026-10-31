import Foundation
import SwiftUI
import UIKit

/// Dictionary-only widget adapter for the pinned ExpoUI source props. It has no
/// React registry, JavaScript engine, hosting controller or module lifecycle.
public final class AppContext { public init() {} }

public protocol Convertible {
    static func convert(from value: Any?, appContext: AppContext) throws -> Self
}
public protocol Enumerable: Convertible, RawRepresentable, CaseIterable {}
public extension Enumerable {
    static func convert(from value: Any?, appContext: AppContext) throws -> Self {
        guard let raw = value as? RawValue, let result = Self(rawValue: raw) else { throw Conversions.ConvertingException<Self>(value) }
        return result
    }
}
open class GenericException<Param>: Error, CustomStringConvertible, @unchecked Sendable {
    public let param: Param
    public init(_ param: Param) { self.param = param }
    open var reason: String { "Invalid widget property: \(param)" }
    public var description: String { reason }
}
public enum Conversions {
    public final class ConvertingException<Value>: GenericException<Any?>, @unchecked Sendable {}
}

public enum FieldOption: ExpressibleByStringLiteral {
    case keyed(String), required
    public init(stringLiteral value: String) { self = .keyed(value) }
}
private protocol DictionaryField: AnyObject {
    var key: String? { get }
    func set(_ value: Any, context: AppContext) throws
}
@propertyWrapper public final class Field<Type>: DictionaryField {
    public var wrappedValue: Type
    private let options: [FieldOption]
    var key: String? { options.compactMap { if case let .keyed(key) = $0 { key } else { nil } }.first }
    public init(wrappedValue: Type, _ options: FieldOption...) { self.wrappedValue = wrappedValue; self.options = options }
    public init(wrappedValue: Type, _ options: [FieldOption]) { self.wrappedValue = wrappedValue; self.options = options }
    public init(wrappedValue: Type = nil) where Type: ExpressibleByNilLiteral { self.wrappedValue = wrappedValue; options = [] }
    public init(wrappedValue: Type = nil, _ options: FieldOption...) where Type: ExpressibleByNilLiteral { self.wrappedValue = wrappedValue; self.options = options }
    func set(_ value: Any, context: AppContext) throws { wrappedValue = try dictionaryValue(value, context: context) }
}

private func dictionaryValue<T>(_ value: Any?, context: AppContext) throws -> T {
    if let convertible = T.self as? any Convertible.Type,
       let result = try convertible.convert(from: value, appContext: context) as? T { return result }
    if let result = value as? T { return result }
    if T.self == CGFloat.self, let number = value as? NSNumber { return CGFloat(number.doubleValue) as! T }
    throw Conversions.ConvertingException<T>(value)
}
extension Optional: Convertible {
    public static func convert(from value: Any?, appContext: AppContext) throws -> Self {
        if value == nil || value is NSNull { return nil }
        let result: Wrapped = try widgetDictionaryValue(value, context: appContext)
        return .some(result)
    }
}
private func widgetDictionaryValue<T>(_ value: Any?, context: AppContext) throws -> T { try dictionaryValue(value, context: context) }
extension Array: Convertible {
    public static func convert(from value: Any?, appContext: AppContext) throws -> Self {
        guard let array = value as? [Any] else { throw Conversions.ConvertingException<Self>(value) }
        return try array.map { try dictionaryValue($0, context: appContext) as Element }
    }
}
extension Dictionary: Convertible where Key == String {
    public static func convert(from value: Any?, appContext: AppContext) throws -> Self {
        guard let dict = value as? [String: Any] else { throw Conversions.ConvertingException<Self>(value) }
        return try dict.mapValues { try dictionaryValue($0, context: appContext) as Value }
    }
}
public struct Either<First, Second>: Convertible {
    private let value: Any
    public func get<T>() -> T? { value as? T }
    public static func convert(from value: Any?, appContext: AppContext) throws -> Self {
        if let first: First = try? dictionaryValue(value, context: appContext) { return .init(value: first) }
        let second: Second = try dictionaryValue(value, context: appContext)
        return .init(value: second)
    }
}
public protocol Record: Convertible {
    typealias Dict = [String: Any]
    init()
    init(from: Dict, appContext: AppContext) throws
}
private func updateFields(_ record: Any, props: [String: Any], context: AppContext) throws {
    var mirror: Mirror? = Mirror(reflecting: record)
    while let current = mirror {
        for child in current.children {
            if let field = child.value as? any DictionaryField, let label = child.label {
                let key = field.key ?? String(label.dropFirst())
                if let value = props[key] { try field.set(value, context: context) }
            }
        }
        mirror = current.superclassMirror
    }
}
public extension Record {
    init(from props: Dict, appContext: AppContext) throws { self.init(); try updateFields(self, props: props, context: appContext) }
    static func convert(from value: Any?, appContext: AppContext) throws -> Self {
        guard let dict = value as? Dict else { throw Conversions.ConvertingException<Self>(value) }
        return try Self(from: dict, appContext: appContext)
    }
}

extension URL: Convertible {
    public static func convert(from value: Any?, appContext: AppContext) throws -> URL {
        if let url = value as? URL { return url }
        guard let string = value as? String, let url = URL(string: string) else { throw Conversions.ConvertingException<Self>(value) }
        return url
    }
}
extension CGPoint: Convertible {
    public static func convert(from value: Any?, appContext: AppContext) throws -> CGPoint {
        if let array = value as? [Double], array.count == 2 { return CGPoint(x: array[0], y: array[1]) }
        guard let dict = value as? [String: Double], let x = dict["x"], let y = dict["y"] else { throw Conversions.ConvertingException<Self>(value) }
        return CGPoint(x: x, y: y)
    }
}
extension Date: Convertible {
    public static func convert(from value: Any?, appContext: AppContext) throws -> Date {
        if let date = value as? Date { return date }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue / 1_000) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let string = value as? String, let date = formatter.date(from: string) else { throw Conversions.ConvertingException<Self>(value) }
        return date
    }
}

/// Event dispatch into React is outside WidgetKit. Native Button actions are
/// injected by Hanlin's verified intent builder. Unsupported gesture/event
/// declarations are rejected by ViewProps rather than pretending to execute.
public final class EventDispatcher {
    public init(_ name: String? = nil) {}
    public func callAsFunction(_ payload: Any? = nil) {}
}
extension ExpoSwiftUI {
    open class ViewProps: ObservableObject, Record {
        public var children: [any AnyChild]?
        public internal(set) weak var appContext: AppContext?
        public let globalEventDispatcher = EventDispatcher()
        public required init() {}
        public required init(rawProps: [String: Any], context: AppContext) throws {
            appContext = context
            guard rawProps["useTapGesture"] as? Bool != true else { throw GenericException("Use a native widget Button for an action") }
            if let modifiers = rawProps["modifiers"] as? [[String: Any]] {
                for modifier in modifiers {
                    guard let name = modifier["$type"] as? String,
                          name == "resizable" || name == "widgetAccentedRenderingMode" || ViewModifierRegistry.shared.hasModifier(name) else {
                        throw GenericException("Unsupported widget modifier: \(modifier["$type"] ?? "missing type")")
                    }
                }
            }
            try updateFields(self, props: rawProps, context: context)
        }
    }
    public typealias View = ExpoSwiftUIView
}
public protocol ExpoSwiftUIView<Props>: SwiftUI.View, ExpoSwiftUI.AnyChild {
    associatedtype Props: ExpoSwiftUI.ViewProps
    var props: Props { get }
    init(props: Props)
}
public extension ExpoSwiftUIView {
    func Children() -> ForEach<[any ExpoSwiftUI.AnyChild], ExpoSwiftUI.ChildIdentity, AnyView> {
        ForEach(props.children ?? [], id: \.childIdentity) { child in AnyView(child.childView) }
    }
}
struct WidgetSourceLogger { func warn(_ message: String) { NSLog("[HanlinExpoWidgetSubset] %@", message) } }
let log = WidgetSourceLogger()

extension View {
    func applyOnTapGesture(useTapGesture: Bool?, eventDispatcher: EventDispatcher) -> some View { self }
}
