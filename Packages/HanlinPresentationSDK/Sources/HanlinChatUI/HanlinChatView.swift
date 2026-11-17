#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import HanlinPresentationKit

/// The canonical Hanlin workspace layout, extracted from ChatView. The existing
/// host supplies its transcript/auto-follow and composer; this package owns no
/// models, SwiftData context, engine, provider, or global conversation selection.
public struct HanlinChatView<Transcript: View, Composer: View>: View {
    public let shell: ShellDescriptor
    private let transcript: Transcript
    private let composer: Composer

    public init(shell: ShellDescriptor,
                @ViewBuilder transcript: () -> Transcript,
                @ViewBuilder composer: () -> Composer) {
        self.shell = shell; self.transcript = transcript(); self.composer = composer()
    }

    public var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                transcript
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground)],
                    startPoint: .top, endPoint: .center
                )
                .frame(height: 120)
                .allowsHitTesting(false)
                .zIndex(0)
                composer
            }
        }
        .environment(\.hanlinPresentationShell, shell)
    }
}

private struct PresentationShellKey: EnvironmentKey {
    static let defaultValue = ShellDescriptor(id: "hanlin.standard", title: "Hanlin")
}

public extension EnvironmentValues {
    var hanlinPresentationShell: ShellDescriptor {
        get { self[PresentationShellKey.self] }
        set { self[PresentationShellKey.self] = newValue }
    }
}

/// Research sources use the native inspector; the host retains source/navigation
/// authority and supplies its existing source view through this slot.
public struct HanlinResearchShell<Content: View, Sources: View>: View {
    @Binding private var showsSources: Bool
    private let content: Content
    private let sources: Sources
    public init(showsSources: Binding<Bool>, @ViewBuilder content: () -> Content,
                @ViewBuilder sources: () -> Sources) {
        _showsSources = showsSources; self.content = content(); self.sources = sources()
    }
    public var body: some View {
        content
            .inspector(isPresented: $showsSources) { sources.inspectorColumnWidth(min: 240, ideal: 300, max: 420) }
    }
}
#endif
