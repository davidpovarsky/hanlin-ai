import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Foundation JSON shadow adapter")
struct FoundationJSONShadowAdapterTests {
    @Test("Null, booleans, integers, and floating point retain their domains")
    func primitiveDomains() throws {
        #expect(try HanlinFoundationJSONShadowAdapter.project(NSNull()) == .null)
        #expect(try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: true)) == .bool(true))
        #expect(try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: Int64.max)) == .integer(Int64.max))
        #expect(try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: Int64.min)) == .integer(Int64.min))
        #expect(try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: 0)) == .integer(0))

        guard case let .number(zero) = try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: 0.0)),
              case let .number(integral) = try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: 1.0)) else {
            Issue.record("Floating NSNumber values must remain canonical binary64 numbers.")
            return
        }
        #expect(zero.bitPattern == 0.0.bitPattern)
        #expect(integral.bitPattern == 1.0.bitPattern)
    }

    @Test("Negative zero preserves its exact binary64 bit pattern")
    func negativeZero() throws {
        guard case let .number(value) = try HanlinFoundationJSONShadowAdapter.project(
            NSNumber(value: -0.0)
        ) else {
            Issue.record("Negative zero did not project as a number.")
            return
        }
        #expect(value.bitPattern == (-0.0).bitPattern)
    }

    @Test("Nested collections and UTF-8-distinct keys remain distinct")
    func nestedCollectionsAndUnicodeKeys() throws {
        let latinKey = "\u{00E9}"
        let hanKey = "\u{4F60}\u{597D}"
        let source: [String: Any] = [
            latinKey: [NSNull(), NSNumber(value: true)],
            hanKey: ["nested": "שלום"]
        ]
        guard case let .object(object) = try HanlinFoundationJSONShadowAdapter.project(source) else {
            Issue.record("Object source did not project as a canonical object.")
            return
        }
        #expect(object.count == 2)
        #expect(object.containsKey(latinKey))
        #expect(object.containsKey(hanKey))
        #expect(Set(object.keys.map { Data($0.utf8) }).count == 2)
    }

    @Test("Lossy or unsupported Foundation values fail explicitly")
    func rejectsUnsupportedValues() {
        #expect(throws: HanlinContractError.self) {
            try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: UInt64.max))
        }
        #expect(throws: HanlinContractError.self) {
            try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: Double.nan))
        }
        #expect(throws: HanlinContractError.self) {
            try HanlinFoundationJSONShadowAdapter.project(NSNumber(value: Double.infinity))
        }
        #expect(throws: HanlinContractError.self) {
            try HanlinFoundationJSONShadowAdapter.project(Data([0x00, 0xFF]))
        }
        #expect(throws: HanlinContractError.self) {
            try HanlinFoundationJSONShadowAdapter.project(Date(timeIntervalSince1970: 0))
        }
    }
}
