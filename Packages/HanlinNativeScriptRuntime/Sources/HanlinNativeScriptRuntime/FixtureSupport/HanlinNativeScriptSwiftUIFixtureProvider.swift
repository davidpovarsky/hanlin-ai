import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
private final class HanlinSwiftUIFixtureModel {
    var title = "SwiftUI in Hanlin"
    var count = 0
}

@MainActor
private struct HanlinSwiftUIFixtureView: View {
    @Bindable var model: HanlinSwiftUIFixtureModel
    let increment: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(model.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("hanlin-swiftui-title")
            Text("SwiftUI count: \(model.count)")
                .font(.title2.monospacedDigit())
                .accessibilityIdentifier("hanlin-swiftui-count")
            Button("Increment in SwiftUI", action: increment)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("hanlin-swiftui-increment")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// A build-time provider used by the production acceptance package. NativeScript
/// packages can select pre-embedded providers, but cannot compile arbitrary Swift.
@MainActor
@objc(HanlinNativeScriptSwiftUIFixtureProvider)
public final class HanlinNativeScriptSwiftUIFixtureProvider: UIViewController, SwiftUIProvider {
    @objc public var onEvent: ((NSDictionary) -> Void)?

    private let model = HanlinSwiftUIFixtureModel()

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView(content: HanlinSwiftUIFixtureView(model: model) { [weak self] in
            guard let self else { return }
            model.count += 1
            onEvent?([
                "count": NSNumber(value: model.count),
                "source": "swiftui"
            ] as NSDictionary)
        })
        print("HANLIN_NS_SWIFTUI_PROVIDER_READY provider=HanlinNativeScriptSwiftUIFixtureProvider")
    }

    @objc public func updateData(data: NSDictionary) {
        if let title = data["title"] as? String, !title.isEmpty {
            model.title = title
        }
        if let count = data["initialCount"] as? NSNumber {
            model.count = count.intValue
        }
        print("HANLIN_NS_SWIFTUI_DATA_OK title=\(model.title) count=\(model.count)")
    }
}
