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
}
#endif
