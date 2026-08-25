import HanlinPlatformContracts
import HanlinScriptDeviceServices
import Foundation
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

    @Test("Location and placemark values preserve modern MapKit result fields")
    func locationValues() {
        let location = HanlinScriptLocationValue(
            latitude: 31.7683,
            longitude: 35.2137,
            altitude: 754,
            horizontalAccuracy: 10,
            timestamp: Date(timeIntervalSince1970: 123)
        )
        let placemark = HanlinScriptPlacemarkValue(
            location: location,
            timeZoneIdentifier: "Asia/Jerusalem",
            name: "Jerusalem",
            locality: "Jerusalem",
            isoCountryCode: "IL",
            country: "Israel"
        )
        #expect(placemark.location == location)
        #expect(placemark.timeZoneIdentifier == "Asia/Jerusalem")
        #expect(placemark.locality == "Jerusalem")
        #expect(placemark.isoCountryCode == "IL")
    }
}
