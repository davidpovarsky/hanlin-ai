import HanlinPlatformContracts
import HanlinScriptDeviceServices
import Testing

@Suite("Apple Scripting service availability")
struct HanlinAppleServiceContractsTests {
    @Test("Every implemented family has one explicit availability record")
    func inventory() {
        let records = HanlinAppleServiceAvailability.current
        #expect(Set(records.map(\.family)) == Set(HanlinAppleServiceFamily.allCases))
        #expect(records.count == HanlinAppleServiceFamily.allCases.count)
        #expect(records.allSatisfy { !$0.allowedContexts.isEmpty })
    }

    @Test("Sensitive frameworks declare their signing and privacy requirements")
    func requirements() throws {
        let records = Dictionary(
            uniqueKeysWithValues: HanlinAppleServiceAvailability.current.map { ($0.family, $0) }
        )
        #expect(try #require(records[.health]).requiredEntitlements == ["com.apple.developer.healthkit"])
        #expect(try #require(records[.location]).requiredUsageDescriptions.contains("NSLocationWhenInUseUsageDescription"))
        #expect(try #require(records[.calendar]).requiredUsageDescriptions.contains("NSCalendarsFullAccessUsageDescription"))
        #expect(!(try #require(records[.health]).allowedContexts.contains(.widget)))
    }
}
