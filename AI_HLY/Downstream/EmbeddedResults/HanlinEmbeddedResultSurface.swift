import Foundation
import SwiftUI

/// Surface view managing the presentation and lifecycle of an embedded result session.
public struct HanlinEmbeddedResultSurface: View {
    public let session: any HanlinEmbeddedResultSession

    public init(session: any HanlinEmbeddedResultSession) {
        self.session = session
    }

    public var body: some View {
        session.rootView
            .onDisappear {
                session.tearDown()
            }
    }
}
