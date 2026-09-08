import Foundation
import HanlinNativeScriptCoreSupport
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
        super.init(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 300)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width > 0 ? size.width : 400, height: size.height > 0 ? size.height : 300)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            provider?.attachToParentViewControllerIfNeeded()
        } else {
            provider?.detachFromParentViewControllerIfNeeded()
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
    private var hostingController: UIHostingController<HanlinSwiftUIFixtureView>?

    public override var description: String {
        "HanlinNativeScriptSwiftUIFixtureProvider(count: \(model.count))"
    }

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func loadView() {
        view = HanlinHostingContainerView(provider: self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let hosting = UIHostingController(rootView: HanlinSwiftUIFixtureView(model: model) { [weak self] in
            guard let self else { return }
            self.model.count += 1
            let payload: [AnyHashable: Any] = [
                "count": NSNumber(value: self.model.count),
                "source": "swiftui"
            ]
            if let onEvent = self.onEvent {
                onEvent(payload as NSDictionary)
            } else {
                HanlinNativeScriptCompatibility.sendEvent(toRegisteredHandler: payload)
            }
        })
        self.hostingController = hosting
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        NSLog("%@", "HANLIN_NS_SWIFTUI_PROVIDER_READY provider=HanlinNativeScriptSwiftUIFixtureProvider")
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hostingController?.beginAppearanceTransition(true, animated: animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hostingController?.endAppearanceTransition()
        layoutHostingViews()
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
        hostingController?.view.setNeedsLayout()
        hostingController?.view.layoutIfNeeded()
        layoutHostingViews()
    }

    fileprivate func detachFromParentViewControllerIfNeeded() {
        guard parent != nil else { return }
        willMove(toParent: nil)
        removeFromParent()
    }

    fileprivate func layoutHostingViews() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        for child in children {
            if child.view.frame != bounds {
                child.view.frame = bounds
            }
            child.view.setNeedsLayout()
            child.view.layoutIfNeeded()
        }
    }

    @objc(updateDataWithData:)
    public func updateData(data: NSDictionary?) {
        guard let data else { return }
        if let title = data["title"] as? String, !title.isEmpty {
            model.title = title
        }
        if let count = data["initialCount"] as? NSNumber {
            model.count = count.intValue
        } else if let countInt = data["initialCount"] as? Int {
            model.count = countInt
        }
        NSLog("%@", "HANLIN_NS_SWIFTUI_DATA_OK title=\(model.title) count=\(model.count)")
    }

    @objc(updateData:)
    public func updateDataDirect(_ data: NSDictionary?) {
        updateData(data: data)
    }

    @objc public func registerEventHandler(_ handler: @escaping (NSDictionary) -> Void) {
        self.onEvent = handler
    }
}
