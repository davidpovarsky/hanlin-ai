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

@Test
func shortcutNativeTextListPreservesOrderAndExactUnicodeBytes() throws {
    let input = ["שלום", "", "{\"keep\":true}", "e\u{301}", "é", "  RTL עברית\n"]
    let value = try HanlinShortcutValueCodec.decodeNativeList(.text(input))
    guard case .array(let values) = value else { Issue.record("Expected a native list"); return }
    #expect(values.count == input.count)
    for (expected, actual) in zip(input, values) {
        guard case .string(let text) = actual else { Issue.record("Expected a text item"); continue }
        #expect(Array(text.utf8) == Array(expected.utf8))
    }
    #expect(try HanlinShortcutValueCodec.decode(
        String(decoding: HanlinShortcutValueCodec.encodeJSON(value), as: UTF8.self),
        as: .dictionaryOrList) == value)
}

@Test
func shortcutNativeIntegerListRetainsValuesBeyondBinary64Precision() throws {
    let value = try HanlinShortcutValueCodec.decodeNativeList(.integers(
        [Int.min, -1, 0, 1, 9_007_199_254_740_993, Int.max]))
    #expect(value == .array([.integer(.min), .integer(-1), .integer(0),
        .integer(1), .integer(9_007_199_254_740_993), .integer(.max)]))
    let json = try HanlinShortcutValueCodec.encodeJSON(value)
    #expect(String(decoding: json, as: UTF8.self) ==
        "[-9223372036854775808,-1,0,1,9007199254740993,9223372036854775807]")
    #expect(try HanlinShortcutValueCodec.decode(String(decoding: json, as: UTF8.self),
        as: .dictionaryOrList) == value)
}

@Test
func shortcutNativeBooleanListDoesNotCoerceToNumbersOrText() throws {
    let value = try HanlinShortcutValueCodec.decodeNativeList(.booleans([true, false, false]))
    #expect(value == .array([.bool(true), .bool(false), .bool(false)]))
    #expect(String(decoding: try HanlinShortcutValueCodec.encodeJSON(value), as: UTF8.self)
        == "[true,false,false]")
}

@Test
func shortcutNativeNumberListRetainsFiniteBinary64TypesAndBits() throws {
    let input: [Double] = [-0.0, 1.0, 1.25, .pi, .leastNonzeroMagnitude, .greatestFiniteMagnitude]
    let value = try HanlinShortcutValueCodec.decodeNativeList(.numbers(input))
    guard case .array(let values) = value else { Issue.record("Expected a native number list"); return }
    #expect(values.count == input.count)
    for (expected, actual) in zip(input, values) {
        guard case .number(let number) = actual else { Issue.record("Expected a Double item"); continue }
        #expect(number.bitPattern == expected.bitPattern)
    }
    // The existing tagged invocation wire preserves integral Doubles and -0.0.
    let wire = try value.canonicalJSONData(limits: .unbounded)
    let restored = try HanlinValue.decodeCanonicalJSON(wire, limits: .unbounded)
    guard case .array(let roundTrip) = restored else { Issue.record("Expected a wire list"); return }
    #expect(roundTrip.count == input.count)
    for (expected, actual) in zip(input, roundTrip) {
        guard case .number(let number) = actual else { Issue.record("Expected a Double after wire decoding"); continue }
        #expect(number.bitPattern == expected.bitPattern)
    }
}

@Test
func shortcutNativeNumberListRejectsNonfiniteItems() {
    for number in [Double.infinity, -Double.infinity, Double.nan] {
        #expect(throws: HanlinContractError.self) {
            try HanlinShortcutValueCodec.decodeNativeList(.numbers([1.25, number]))
        }
    }
}

@Test
func shortcutNativeEmptyListsRemainArrays() throws {
    let inputs: [HanlinShortcutValueCodec.NativeList] = [
        .text([]), .integers([]), .numbers([]), .booleans([])
    ]
    for input in inputs {
        let value = try HanlinShortcutValueCodec.decodeNativeList(input)
        #expect(value == .array([]))
        #expect(String(decoding: try HanlinShortcutValueCodec.encodeJSON(value), as: UTF8.self) == "[]")
    }
}
