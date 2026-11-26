import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func shortcutDictionaryAndListRetainStructureAndExactNumbers() throws {
    let input = #"{"name":"שלום","empty":[],"enabled":true,"nested":{"value":null},"min":-9223372036854775808,"max":9223372036854775807,"fraction":1.5}"#
    let value = try HanlinShortcutValueCodec.decode(input, as: .dictionaryOrList)
    guard case .object(let object) = value else { Issue.record("Expected a dictionary"); return }
    #expect(object["min"] == .integer(.min))
    #expect(object["max"] == .integer(.max))
    #expect(object["enabled"] == .bool(true))
    #expect(object["nested"] == .object(["value": .null]))
    #expect(object["empty"] == .array([]))
    #expect(try HanlinShortcutValueCodec.decode(
        String(decoding: HanlinShortcutValueCodec.encodeJSON(value), as: UTF8.self),
        as: .dictionaryOrList) == value)
    #expect(try HanlinShortcutValueCodec.decode(#"[{},[],null,false,1,"שלום"]"#, as: .dictionaryOrList)
        == .array([.object([:]), .array([]), .null, .bool(false), .integer(1), .string("שלום")]))
}

@Test(arguments: ["null", "true", "42", "1.5", #""hello""#])
func shortcutJSONAcceptsScalarValuesWithoutDoubleEncoding(_ input: String) throws {
    let value = try HanlinShortcutValueCodec.decode(input, as: .json)
    #expect(try HanlinShortcutValueCodec.decode(
        String(decoding: HanlinShortcutValueCodec.encodeJSON(value), as: UTF8.self),
        as: .json) == value)
    #expect(throws: HanlinShortcutValueCodec.InputError.dictionaryOrListRequired) {
        try HanlinShortcutValueCodec.decode(input, as: .dictionaryOrList)
    }
}

@Test(arguments: ["", "[", #"{"duplicate":1,"duplicate":2}"#, "9223372036854775808", "NaN"])
func shortcutJSONRejectsMalformedOrLossyInput(_ input: String) {
    #expect(throws: (any Error).self) {
        try HanlinShortcutValueCodec.decode(input, as: .json)
    }
}

@Test
func shortcutTextRemainsTextAndBinaryOutputRequiresAFile() throws {
    #expect(try HanlinShortcutValueCodec.decode("{}", as: .text) == .string("{}"))
    #expect(try HanlinShortcutValueCodec.decode("", as: .text) == .string(""))
    #expect(throws: HanlinContractError.self) {
        try HanlinShortcutValueCodec.encodeJSON(.data(Data([0, 255])))
    }
}
