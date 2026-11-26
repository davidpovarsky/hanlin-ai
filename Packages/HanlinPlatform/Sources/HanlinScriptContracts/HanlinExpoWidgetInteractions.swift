import Foundation

/// A small host adapter around the original Expo widget renderer. This resource
/// runs only in the existing widget JavaScript context, never a new app runtime.
public enum HanlinExpoWidgetInteractions {
    public static func script() throws -> String {
        guard let url = Bundle.module.url(forResource: "HanlinExpoWidgetInteractions", withExtension: "js") else {
            throw HanlinWidgetProgramError.invalidProgram
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
