import Foundation

/// Persist only this versioned identifier. Preset tuning stays in one mapping below.
enum ChatMotionPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case relaxed = "v1.relaxed"
    case heightReveal = "v1.height-reveal"
    case gentleSqueeze = "v1.gentle-squeeze"
    case quietFade = "v1.quiet-fade"
    case none = "v1.none"

    static let storageKey = "hanlin.chat.motion.preset"
    var id: String { rawValue }

    static func fromStoredID(_ value: String) -> Self {
        if let current = Self(rawValue: value) { return current }
        // The unversioned spellings are the only supported legacy schema.
        switch value {
        case "relaxed": return .relaxed
        case "heightReveal": return .heightReveal
        case "gentleSqueeze": return .gentleSqueeze
        case "quietFade": return .quietFade
        case "none": return .none
        default: return .relaxed
        }
    }
}

struct ChatMotionConfiguration: Equatable, Sendable {
    enum Curve: Sendable { case easeInOut, easeOut }
    let openingDuration: Double
    let closingDuration: Double
    let updateDuration: Double
    let resultDuration: Double
    let shimmerDuration: Double
    let collapsedOpacity: Double
    let collapsedScale: Double
    let resultScale: Double
    let numericCounts: Bool
    let curve: Curve

    var isAnimated: Bool { openingDuration > 0 }
    var showsShimmer: Bool { shimmerDuration > 0 }

    static func forPreset(_ preset: ChatMotionPreset, reduceMotion: Bool = false) -> Self {
        if reduceMotion || preset == .none {
            return Self(openingDuration: 0, closingDuration: 0, updateDuration: 0,
                resultDuration: 0, shimmerDuration: 0, collapsedOpacity: 1,
                collapsedScale: 1, resultScale: 1, numericCounts: false, curve: .easeInOut)
        }
        switch preset {
        case .relaxed:
            return Self(openingDuration: 0.410, closingDuration: 0.300, updateDuration: 0.160,
                resultDuration: 0.280, shimmerDuration: 2, collapsedOpacity: 0.25,
                collapsedScale: 1, resultScale: 0.96, numericCounts: true, curve: .easeInOut)
        case .heightReveal:
            return Self(openingDuration: 0.450, closingDuration: 0.330, updateDuration: 0.160,
                resultDuration: 0.280, shimmerDuration: 2.2, collapsedOpacity: 1,
                collapsedScale: 1, resultScale: 1, numericCounts: true, curve: .easeInOut)
        case .gentleSqueeze:
            return Self(openingDuration: 0.460, closingDuration: 0.340, updateDuration: 0.180,
                resultDuration: 0.300, shimmerDuration: 2.2, collapsedOpacity: 0.3,
                collapsedScale: 0.985, resultScale: 0.98, numericCounts: true, curve: .easeInOut)
        case .quietFade:
            return Self(openingDuration: 0.280, closingDuration: 0.240, updateDuration: 0.150,
                resultDuration: 0.240, shimmerDuration: 2.6, collapsedOpacity: 0,
                collapsedScale: 1, resultScale: 1, numericCounts: false, curve: .easeOut)
        case .none:
            preconditionFailure("Static configuration handled above")
        }
    }
}
