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

@MainActor
private final class HanlinHostingContainerView: UIView {
    weak var provider: HanlinNativeScriptSwiftUIFixtureProvider?

    init(provider: HanlinNativeScriptSwiftUIFixtureProvider) {
        self.provider = provider
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            provider?.attachToParentViewControllerIfNeeded()
        } else {
            provider?.detachFromParentViewControllerIfNeeded()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil {
            provider?.attachToParentViewControllerIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        provider?.layoutHostingViews()
    }
}

/// A build-time provider used by the production acceptance package. NativeScript
/// packages can select pre-embedded providers, but cannot compile arbitrary Swift.
@MainActor
@objc(HanlinNativeScriptSwiftUIFixtureProvider)
public final class HanlinNativeScriptSwiftUIFixtureProvider: UIViewController, SwiftUIProvider {
    @objc public var onEvent: ((NSDictionary) -> Void)?

    private let model = HanlinSwiftUIFixtureModel()

    public override func loadView() {
        view = HanlinHostingContainerView(provider: self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView(content: HanlinSwiftUIFixtureView(model: model) { [weak self] in
            guard let self else { return }
            self.model.count += 1
            self.onEvent?([
                "count": NSNumber(value: self.model.count),
                "source": "swiftui"
            ] as NSDictionary)
        })
        if let hostingView = children.first?.view {
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        NSLog("%@", "HANLIN_NS_SWIFTUI_PROVIDER_READY provider=HanlinNativeScriptSwiftUIFixtureProvider")
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHostingViews()
    }

    fileprivate func attachToParentViewControllerIfNeeded() {
        guard parent == nil else { return }
        var parentVC: UIViewController?
        var responder: UIResponder? = view.superview
        while let current = responder {
            if let vc = current as? UIViewController, vc !== self {
                parentVC = vc
                break
            }
            responder = current.next
        }
        if parentVC == nil, let window = view.window {
            parentVC = window.rootViewController
        }
        guard let host = parentVC else { return }
        host.addChild(self)
        beginAppearanceTransition(true, animated: false)
        didMove(toParent: host)
        endAppearanceTransition()
        layoutHostingViews()
    }

    fileprivate func detachFromParentViewControllerIfNeeded() {
        guard parent != nil else { return }
        willMove(toParent: nil)
        beginAppearanceTransition(false, animated: false)
        removeFromParent()
        endAppearanceTransition()
    }

    fileprivate func layoutHostingViews() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        for child in children {
            if child.view.frame != bounds {
                child.view.frame = bounds
            }
            child.view.layoutIfNeeded()
        }
    }

    @objc(updateDataWithData:)
    public func updateData(data: NSDictionary) {
        if let title = data["title"] as? String, !title.isEmpty {
            model.title = title
        }
        if let count = data["initialCount"] as? NSNumber {
            model.count = count.intValue
        }
        NSLog("%@", "HANLIN_NS_SWIFTUI_DATA_OK title=\(model.title) count=\(model.count)")
    }

    @objc(updateData:)
    public func updateDataDirect(_ data: NSDictionary) {
        updateData(data: data)
    }

    @objc public func registerEventHandler(_ handler: @escaping (NSDictionary) -> Void) {
        self.onEvent = handler
    }
}
