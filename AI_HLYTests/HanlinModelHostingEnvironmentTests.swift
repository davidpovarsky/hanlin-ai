import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import AI_Hanlin

@MainActor
@Suite("Model picker hosting environment", .serialized)
struct HanlinModelHostingEnvironmentTests {
    /// A render-time recorder only: no view state or catalog mutation.
    private struct ContextProbe: View {
        @Environment(\.modelContext) private var modelContext
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let record: @MainActor (ModelContext, Bool) -> Void

        var body: some View {
            let _ = record(modelContext, reduceMotion)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    @Test("Native hosting preserves the actual catalog context and system motion setting")
    func nativeHostRetainsCatalogContextAcrossRootUpdates() throws {
        let firstStore = try ModelContainer(for: AllModels.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let nextStore = try ModelContainer(for: AllModels.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var observations: [(ModelContext, Bool)] = []
        let probe = ContextProbe { context, motion in observations.append((context, motion)) }
        var environment = EnvironmentValues()
        environment.modelContext = firstStore.mainContext
        let host = HanlinModelSizingHost(content: HanlinModelHostedView(content: probe, environment: environment))
        _ = host.sizeThatFits(in: CGSize(width: 286, height: 324))
        #expect(!observations.isEmpty, "The actual hosted SwiftUI body must render")
        #expect(observations.allSatisfy { $0.0 === firstStore.mainContext && $0.1 == UIAccessibility.isReduceMotionEnabled })

        observations.removeAll()
        environment.modelContext = nextStore.mainContext
        host.rootView = HanlinModelHostedView(content: probe, environment: environment)
        _ = host.sizeThatFits(in: CGSize(width: 286, height: 324))
        #expect(!observations.isEmpty, "The updated hosted SwiftUI body must render")
        #expect(observations.allSatisfy { $0.0 === nextStore.mainContext && $0.1 == UIAccessibility.isReduceMotionEnabled })
    }
}
