import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func identifiersValidateAndRoundTripCanonically() throws {
    let appID = try HanlinAppID(validating: "com.example.transit")
    #expect(appID.rawValue == "com.example.transit")
    #expect(HanlinAppID(rawValue: "Com.Example") == nil)
    #expect(HanlinAppID(rawValue: ".com.example") == nil)
    #expect(HanlinAppID(rawValue: "com..example") == nil)
    #expect(HanlinAppID(rawValue: "com.example/escape") == nil)
    #expect(HanlinAppID(rawValue: "שלום") == nil)

    let data = try JSONEncoder().encode(appID)
    #expect(try JSONDecoder().decode(HanlinAppID.self, from: data) == appID)

    let malformed = Data(#""com..example""#.utf8)
    #expect(throws: HanlinContractError.self) {
        try JSONDecoder().decode(HanlinAppID.self, from: malformed)
    }
}

@Test
func majorMinorVersionsRejectNonCanonicalAndUnknownVersions() throws {
    let api = try HanlinAPIVersion(validating: "1.0")
    #expect(api == HanlinAPIVersion(major: 1, minor: 0))
    #expect(HanlinAPIVersion(rawValue: "01.0") == nil)
    #expect(HanlinAPIVersion(rawValue: "1") == nil)
    #expect(HanlinAPIVersion(rawValue: "1.0.0") == nil)

    try HanlinVersionSupport.version1.validate(api)
    #expect(throws: HanlinContractError.self) {
        try HanlinVersionSupport.version1.validate(
            HanlinAPIVersion(major: 2, minor: 0)
        )
    }
}

@Test
func packageVersionsUseStableTotalOrdering() throws {
    let prerelease = try HanlinPackageVersion(validating: "1.2.3-beta.2")
    let release = try HanlinPackageVersion(validating: "1.2.3")
    let later = try HanlinPackageVersion(validating: "1.3.0")
    let build1 = try HanlinPackageVersion(validating: "1.2.3+build.1")
    let build2 = try HanlinPackageVersion(validating: "1.2.3+build.2")

    #expect(prerelease < release)
    #expect(release < later)
    #expect(build1 < build2)
    #expect(HanlinPackageVersion(rawValue: "1.02.3") == nil)
    #expect(HanlinPackageVersion(rawValue: "1.2.3-01") == nil)
    #expect(HanlinPackageVersion(rawValue: "1.2") == nil)
}

@Test
func hostVersionRangeRejectsInversion() throws {
    let one = try HanlinPackageVersion(validating: "1.0.0")
    let two = try HanlinPackageVersion(validating: "2.0.0")
    let range = try HanlinHostVersionRange(minimum: one, maximum: two)
    #expect(range.contains(one))
    #expect(range.contains(two))
    #expect(throws: HanlinContractError.self) {
        try HanlinHostVersionRange(minimum: two, maximum: one)
    }
}
