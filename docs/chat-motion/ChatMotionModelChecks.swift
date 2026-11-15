import Foundation

@main
struct ChatMotionModelChecks {
    static func main() throws {
        let ids = ChatMotionPreset.allCases.map(\.rawValue)
        precondition(ids.count == 5 && Set(ids).count == ids.count)
        for preset in ChatMotionPreset.allCases {
            let encoded = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(ChatMotionPreset.self, from: encoded)
            precondition(decoded == preset)
            precondition(ChatMotionPreset.fromStoredID(preset.rawValue) == preset)
            let configuration = ChatMotionConfiguration.forPreset(preset)
            precondition(configuration.openingDuration >= configuration.closingDuration)
            precondition((0...1).contains(configuration.collapsedOpacity))
            precondition(configuration.collapsedScale >= 0.98 && configuration.collapsedScale <= 1)
            let reduced = ChatMotionConfiguration.forPreset(preset, reduceMotion: true)
            precondition(reduced == ChatMotionConfiguration.forPreset(.none))
            precondition(!reduced.isAnimated && !reduced.showsShimmer && !reduced.numericCounts)
        }
        precondition(ChatMotionPreset.fromStoredID("none") == .none)
        precondition(ChatMotionPreset.fromStoredID("quietFade") == .quietFade)
        for corrupt in ["", "v2.relaxed", "v1.unknown", "v1.NONE", " v1.none "] {
            precondition(ChatMotionPreset.fromStoredID(corrupt) == .relaxed)
        }
        // Defaults serialization, not a SwiftUI/AppStorage or app-relaunch claim.
        let suite = "hanlin-motion-check-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(ChatMotionPreset.heightReveal.rawValue, forKey: ChatMotionPreset.storageKey)
        precondition(ChatMotionPreset.fromStoredID(defaults.string(forKey: ChatMotionPreset.storageKey)!) == .heightReveal)
        precondition(ChatMotionConfiguration.forPreset(.relaxed).collapsedScale == 1)
        precondition(ChatMotionConfiguration.forPreset(.relaxed).openingDuration == 0.410)
        print("PASS: preset identity/Codable, migration/corruption, Reduce Motion, bounded tuning, Defaults serialization")
    }
}
