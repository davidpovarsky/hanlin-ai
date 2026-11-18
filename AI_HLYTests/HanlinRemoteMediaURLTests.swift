import Foundation
#if !HANLIN_MEDIA_URL_PORTABLE_RUNNER
import Testing
@testable import AI_Hanlin
#endif

private enum MediaURLCheckFailure: Error { case rejected(String) }
private enum MediaURLChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ context: String) throws {
        if !condition() { throw MediaURLCheckFailure.rejected(context) }
    }
    static func acceptsPublicHTTPS() throws {
        for url in ["https://images.example.com/a.png", "HTTPS://CDN.EXAMPLE.COM/a.jpg?token=opaque", "https://cdn.example.com:443/video.m3u8"] {
            try require(HanlinRemoteMediaURL(url) != nil, "Public HTTPS source")
        }
    }
    static func rejectsCredentialsAndOtherSchemes() throws {
        for url in ["https://user:password@example.com/image.png", "https://user@example.com/a", "http://example.com/a", "data:image/png;base64,eA==", "file:///private/a", "blob:https://example.com/a", "javascript:alert(1)", "//example.com/a"] {
            try require(HanlinRemoteMediaURL(url) == nil, "Credential/unsupported source admitted")
        }
    }
    static func rejectsLiteralNetworkAddresses() throws {
        for host in ["127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254", "2130706433", "8.8.8.8", "[::1]", "[::ffff:127.0.0.1]"] {
            try require(HanlinRemoteMediaURL("https://\(host)/a") == nil, "IP literal admitted")
        }
    }
    static func rejectsLocalNamesAndAmbiguousHosts() throws {
        for host in ["localhost", "a.localhost", "a.local", "a.internal", "a.home.arpa", "a.onion", "a.test", "a.invalid", "a..com", "-a.com", "a-.com", "example.com.", "%65xample.com", "a.123"] {
            try require(HanlinRemoteMediaURL("https://\(host)/a") == nil, "Local/ambiguous name admitted")
        }
    }
    static func boundsURLAndHostLabels() throws {
        try require(HanlinRemoteMediaURL("https://example.com/" + String(repeating: "x", count: 4096)) == nil, "Oversized URL admitted")
        try require(HanlinRemoteMediaURL("https://" + String(repeating: "a", count: 64) + ".com/a") == nil, "Oversized DNS label admitted")
        try require(HanlinRemoteMediaURL("https://example.com:8443/a") == nil, "Nonstandard port admitted")
    }
    static func preservesOpaqueSourceBytes() throws {
        let raw = "https://cdn.example.com/image.png?signature=opaque%2Bvalue&v=1"
        try require(HanlinRemoteMediaURL(raw)?.url.absoluteString == raw, "Signed URL changed")
        // DNS-shaped admission is deliberately not proof of public DNS/redirect destinations.
        try require(HanlinRemoteMediaURL("https://youtube.com.evil.com/a") != nil, "This generic media policy is not YouTube host authentication")
    }
}

#if HANLIN_MEDIA_URL_PORTABLE_RUNNER
@main
enum MediaURLPortableRunner {
    static func main() throws {
        for (name, check) in [("acceptsPublicHTTPS", MediaURLChecks.acceptsPublicHTTPS),
            ("rejectsCredentialsAndOtherSchemes", MediaURLChecks.rejectsCredentialsAndOtherSchemes),
            ("rejectsLiteralNetworkAddresses", MediaURLChecks.rejectsLiteralNetworkAddresses),
            ("rejectsLocalNamesAndAmbiguousHosts", MediaURLChecks.rejectsLocalNamesAndAmbiguousHosts),
            ("boundsURLAndHostLabels", MediaURLChecks.boundsURLAndHostLabels),
            ("preservesOpaqueSourceBytes", MediaURLChecks.preservesOpaqueSourceBytes)] {
            try check(); print("EXECUTED_PASS \(name)")
        }
    }
}
#else
@Suite("Media source lexical admission")
struct HanlinRemoteMediaURLTests {
    @Test func acceptsPublicHTTPS() throws { try MediaURLChecks.acceptsPublicHTTPS() }
    @Test func rejectsCredentialsAndOtherSchemes() throws { try MediaURLChecks.rejectsCredentialsAndOtherSchemes() }
    @Test func rejectsLiteralNetworkAddresses() throws { try MediaURLChecks.rejectsLiteralNetworkAddresses() }
    @Test func rejectsLocalNamesAndAmbiguousHosts() throws { try MediaURLChecks.rejectsLocalNamesAndAmbiguousHosts() }
    @Test func boundsURLAndHostLabels() throws { try MediaURLChecks.boundsURLAndHostLabels() }
    @Test func preservesOpaqueSourceBytes() throws { try MediaURLChecks.preservesOpaqueSourceBytes() }
    @Test func resolvedDestinationsRejectPrivateSpecialAndTranslatedLocalAddresses() {
        #expect(HanlinMediaAddressPolicy.publicIPv4(16843009) == true) // 1.1.1.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(134744072) == true) // 8.8.8.8
        #expect(HanlinMediaAddressPolicy.publicIPv4(301830154) == true) // 17.253.144.10
        #expect(HanlinMediaAddressPolicy.publicIPv4(66051) == false) // 0.1.2.3
        #expect(HanlinMediaAddressPolicy.publicIPv4(167838211) == false) // 10.1.2.3
        #expect(HanlinMediaAddressPolicy.publicIPv4(1681915905) == false) // 100.64.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(1686110207) == false) // 100.127.255.255
        #expect(HanlinMediaAddressPolicy.publicIPv4(2130706433) == false) // 127.0.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(2852039166) == false) // 169.254.169.254
        #expect(HanlinMediaAddressPolicy.publicIPv4(2886729729) == false) // 172.16.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(2887778303) == false) // 172.31.255.255
        #expect(HanlinMediaAddressPolicy.publicIPv4(3221225473) == false) // 192.0.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3221225985) == false) // 192.0.2.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3227017985) == false) // 192.88.99.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3232235777) == false) // 192.168.1.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3323068417) == false) // 198.18.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3323199487) == false) // 198.19.255.255
        #expect(HanlinMediaAddressPolicy.publicIPv4(3325256705) == false) // 198.51.100.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3405803777) == false) // 203.0.113.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(3758096385) == false) // 224.0.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(4026531841) == false) // 240.0.0.1
        #expect(HanlinMediaAddressPolicy.publicIPv4(4294967295) == false) // 255.255.255.255
        #expect(HanlinMediaAddressPolicy.publicIPv6([32, 1, 72, 96, 72, 96, 0, 0, 0, 0, 0, 0, 0, 0, 136, 136]) == true) // 2001:4860:4860::8888
        #expect(HanlinMediaAddressPolicy.publicIPv6([38, 6, 71, 0, 71, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17, 17]) == true) // 2606:4700:4700::1111
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 8, 8, 8, 8]) == true) // ::ffff:8.8.8.8
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 100, 255, 155, 0, 0, 0, 0, 0, 0, 0, 0, 8, 8, 8, 8]) == true) // 64:ff9b::808:808
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) == false) // ::
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // ::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([252, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // fc00::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([253, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // fd00::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([254, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // fe80::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([255, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // ff02::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // 2001:db8::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([32, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // 2001:2::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([32, 2, 127, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // 2002:7f00:1::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([63, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // 3fff::1
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 192, 168, 1, 1]) == false) // ::ffff:192.168.1.1
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 100, 255, 155, 0, 0, 0, 0, 0, 0, 0, 0, 127, 0, 0, 1]) == false) // 64:ff9b::7f00:1
        #expect(HanlinMediaAddressPolicy.publicIPv6([0, 100, 255, 155, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]) == false) // 64:ff9b:1::1
    }

}
#endif
