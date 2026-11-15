import Foundation
#if !HANLIN_MEDIA_PORTABLE_RUNNER
import Testing
#if HANLIN_MEDIA_ISOLATED_PROOF
@testable import HanlinChatMediaProof
#else
@testable import AI_Hanlin
#endif
#endif

private enum YouTubeCheckFailure: Error { case invalid(String) }
private enum YouTubeChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        if !condition() { throw YouTubeCheckFailure.invalid(description) }
    }
    static func video(_ value: String) -> HanlinYouTubeVideo? {
        URL(string: value).flatMap(HanlinYouTubeVideo.init(url:))
    }
    static func watchURL() throws {
        let normalized = video("https://WWW.YOUTUBE.COM/watch?v=M7lc1UVf-VE&si=tracking&t=2#fragment")
        try require(normalized?.id == "M7lc1UVf-VE", "Valid watch URL")
        try require(normalized?.sourceURL.absoluteString == "https://www.youtube.com/watch?v=M7lc1UVf-VE", "Canonical source drops untrusted tracking/fragment")
    }
    static func shareAndShorts() throws {
        for value in ["https://youtu.be/M7lc1UVf-VE?si=tracking", "https://youtube.com/shorts/M7lc1UVf-VE", "https://m.youtube.com/watch?v=M7lc1UVf-VE"] {
            try require(video(value)?.id == "M7lc1UVf-VE", "Actual supported URL: \(value)")
        }
    }
    static func embedURL() throws {
        for value in ["https://www.youtube.com/embed/M7lc1UVf-VE", "https://www.youtube-nocookie.com/embed/M7lc1UVf-VE"] {
            try require(video(value)?.id == "M7lc1UVf-VE", "Supported official embed host")
        }
        try require(video("https://youtube-nocookie.com/watch?v=M7lc1UVf-VE") == nil, "No invented nocookie watch route")
    }
    static func spoofedHosts() throws {
        for value in ["https://youtube.com.evil.test/watch?v=M7lc1UVf-VE", "https://youtube.com@evil.test/watch?v=M7lc1UVf-VE", "https://evil@youtube.com/watch?v=M7lc1UVf-VE", "https://youtube.com./watch?v=M7lc1UVf-VE", "https://notyoutube.com/watch?v=M7lc1UVf-VE", "https://www.youtu.be.evil.test/M7lc1UVf-VE", "https://localhost/watch?v=M7lc1UVf-VE", "https://127.0.0.1/watch?v=M7lc1UVf-VE"] {
            try require(video(value) == nil, "Spoof/credentials/local URL admitted")
        }
    }
    static func unsupportedSchemesAndPorts() throws {
        for value in ["http://youtu.be/M7lc1UVf-VE", "javascript:alert(1)", "file:///M7lc1UVf-VE", "data:text/html,<script>x</script>", "https://youtu.be:8443/M7lc1UVf-VE"] {
            try require(video(value) == nil, "Non-HTTPS or unsupported port admitted")
        }
        try require(video("https://youtu.be:443/M7lc1UVf-VE")?.id == "M7lc1UVf-VE", "Explicit standard HTTPS port")
    }
    static func malformedIdentity() throws {
        for value in ["https://youtube.com/watch?v=M7lc1UVf-VE&v=abcdefghijk", "https://youtu.be/M7lc1UVf-VE/extra", "https://youtu.be//M7lc1UVf-VE", "https://youtube.com/shorts%2FM7lc1UVf-VE", "https://youtube.com/playlist?list=M7lc1UVf-VE", "https://youtube.com/watch?v=short", "https://youtube.com/watch?v=abcdefghij%27", "https://youtube.com/watch?v=abcdefghij%3C"] {
            try require(video(value) == nil, "Ambiguous/path/HTML injection admitted")
        }
        try require(HanlinYouTubeVideo(id: "אבגדהוזחטיכ") == nil, "Unicode ID admitted")
        try require(HanlinYouTubeVideo(id: String(repeating: "a", count: 12)) == nil, "Oversized ID admitted")
    }
    static func appIdentity() throws {
        try require(HanlinYouTubeDocument.origin(bundleID: "Com.Example.Hanlin")?.absoluteString == "https://com.example.hanlin", "Installed app origin")
        for value in ["", "single", "com..app", "com.app.", "-com.app", "com.app-", "com.app/path", "com.app\" onload=evil", "user@com.app", "com.app:443"] {
            try require(HanlinYouTubeDocument.origin(bundleID: value) == nil, "Invalid app identity admitted")
        }
        try require(HanlinYouTubeDocument.origin(bundleID: nil) == nil, "Missing identity must not be invented")
    }
    static func officialDocument() throws {
        guard let video = HanlinYouTubeVideo(id: "M7lc1UVf-VE"),
              let origin = HanlinYouTubeDocument.origin(bundleID: "com.example.hanlin") else { throw YouTubeCheckFailure.invalid("Fixture") }
        let html = HanlinYouTubeDocument.html(video: video, origin: origin)
        try require(html.contains("https://www.youtube.com/iframe_api") && html.contains("new YT.Player("), "Official player API")
        try require(html.contains("\"autoplay\":0") && html.contains("\"controls\":1") && html.contains("\"playsinline\":1"), "User-controlled playback/controls")
        try require(!html.contains("playVideo()") && html.contains("player.destroy()"), "No autoplay and explicit disposal")
        try require(html.contains("Content-Security-Policy") && html.contains("strict-origin-when-cross-origin"), "Scoped document and referrer")
    }
}

#if HANLIN_MEDIA_PORTABLE_RUNNER
@main
enum HanlinYouTubePortableRunner {
    static func main() throws {
        for (name, check) in [("watchURL", YouTubeChecks.watchURL), ("shareAndShorts", YouTubeChecks.shareAndShorts),
            ("embedURL", YouTubeChecks.embedURL), ("spoofedHosts", YouTubeChecks.spoofedHosts),
            ("unsupportedSchemesAndPorts", YouTubeChecks.unsupportedSchemesAndPorts), ("malformedIdentity", YouTubeChecks.malformedIdentity),
            ("appIdentity", YouTubeChecks.appIdentity), ("officialDocument", YouTubeChecks.officialDocument)] {
            try check()
            print("EXECUTED_PASS \(name)")
        }
    }
}
#else
@Suite("YouTube identity and official embed document")
struct HanlinYouTubeTests {
    @Test func watchURL() throws { try YouTubeChecks.watchURL() }
    @Test func shareAndShorts() throws { try YouTubeChecks.shareAndShorts() }
    @Test func embedURL() throws { try YouTubeChecks.embedURL() }
    @Test func spoofedHosts() throws { try YouTubeChecks.spoofedHosts() }
    @Test func unsupportedSchemesAndPorts() throws { try YouTubeChecks.unsupportedSchemesAndPorts() }
    @Test func malformedIdentity() throws { try YouTubeChecks.malformedIdentity() }
    @Test func appIdentity() throws { try YouTubeChecks.appIdentity() }
    @Test func officialDocument() throws { try YouTubeChecks.officialDocument() }
}
#endif
