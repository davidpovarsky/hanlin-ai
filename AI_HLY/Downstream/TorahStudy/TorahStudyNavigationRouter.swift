import Foundation
import SwiftUI
import TorahLibraryKit

/// Central navigation coordinator for in-app Torah study deep links and primary source reading.
@MainActor
public final class TorahStudyNavigationRouter: ObservableObject {
    public static let shared = TorahStudyNavigationRouter()

    @Published public var activeDeepLink: TorahStudyDeepLink? = nil
    @Published public var isPresentingReader: Bool = false

    private init() {}

    /// Navigates to a specific source passage by presenting the in-app source reader.
    public func navigate(to deepLink: TorahStudyDeepLink) {
        self.activeDeepLink = deepLink
        self.isPresentingReader = true
    }

    /// Dismisses the active source reader.
    public func closeReader() {
        self.isPresentingReader = false
        self.activeDeepLink = nil
    }
}
