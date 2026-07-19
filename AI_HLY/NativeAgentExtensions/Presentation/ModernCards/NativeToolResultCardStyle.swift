import SwiftUI

enum NativeToolResultCardStyle {
    static let cornerRadius: CGFloat = 20
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12

    static var background: Color {
        Color(uiColor: .secondarySystemBackground)
    }

    static var separator: Color {
        Color(uiColor: .separator).opacity(0.32)
    }
}
