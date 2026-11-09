import SwiftUI
import UIKit

/// UIKit owns the popover's source-item morph; SwiftUI owns its inner geometry morph.
/// A navigationTransition on a SwiftUI popover's root competes with the inner
/// destination transition (42539502009 rendered an invisible All Models page).
@MainActor
struct HanlinModelZoomPopover<Source: View, Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let presentationID: Int
    let source: Source
    let content: Content

    init(isPresented: Binding<Bool>, presentationID: Int,
         @ViewBuilder source: () -> Source, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.presentationID = presentationID
        self.source = source()
        self.content = content()
    }

    func makeUIViewController(context: Context) -> HanlinModelPopoverController<Source, Content> {
        HanlinModelPopoverController(
            source: HanlinModelHostedView(content: source, environment: context.environment),
            content: HanlinModelHostedView(content: content, environment: context.environment)
        )
    }

    func updateUIViewController(_ controller: HanlinModelPopoverController<Source, Content>, context: Context) {
        controller.update(
            source: HanlinModelHostedView(content: source, environment: context.environment),
            content: HanlinModelHostedView(content: content, environment: context.environment),
            isPresented: $isPresented, presentationID: presentationID
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                     uiViewController: HanlinModelPopoverController<Source, Content>, context: Context) -> CGSize? {
        uiViewController.sourceSize(in: CGSize(width: proposal.width ?? 10_000, height: proposal.height ?? 10_000))
    }

    static func dismantleUIViewController(_ controller: HanlinModelPopoverController<Source, Content>, coordinator: ()) {
        controller.shutdown()
    }
}

/// Carry user-facing environment choices across the explicit hosting boundary.
struct HanlinModelHostedView<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues

    var body: some View {
        content
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.colorScheme, environment.colorScheme)
    }
}

@MainActor
final class HanlinModelPopoverController<Source: View, Content: View>: UIViewController,
    UIPopoverPresentationControllerDelegate {
    private let sourceHost: UIHostingController<HanlinModelHostedView<Source>>
    private var content: HanlinModelHostedView<Content>
    private var popupHost: UIHostingController<HanlinModelHostedView<Content>>?
    private var presentation: Binding<Bool>?
    private var requested = false
    private var requestID = 0
    private var presentedID = 0

    init(source: HanlinModelHostedView<Source>, content: HanlinModelHostedView<Content>) {
        sourceHost = UIHostingController(rootView: source)
        self.content = content
        super.init(nibName: nil, bundle: nil)
        sourceHost.sizingOptions = .intrinsicContentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(source:content:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(sourceHost)
        sourceHost.view.backgroundColor = .clear
        sourceHost.view.layer.cornerRadius = 14
        sourceHost.view.clipsToBounds = true
        sourceHost.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sourceHost.view)
        NSLayoutConstraint.activate([
            sourceHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sourceHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sourceHost.view.topAnchor.constraint(equalTo: view.topAnchor),
            sourceHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        sourceHost.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reconcilePresentation()
    }

    func sourceSize(in proposal: CGSize) -> CGSize { sourceHost.sizeThatFits(in: proposal) }

    func update(source: HanlinModelHostedView<Source>, content: HanlinModelHostedView<Content>,
                isPresented: Binding<Bool>, presentationID: Int) {
        sourceHost.rootView = source
        self.content = content
        presentation = isPresented
        requested = isPresented.wrappedValue
        requestID = presentationID
        if requested, presentedID == requestID {
            popupHost?.rootView = content
        }
        reconcilePresentation()
    }

    private func reconcilePresentation() {
        if let popupHost {
            guard !requested || requestID != presentedID else { return }
            guard !popupHost.isBeingPresented, !popupHost.isBeingDismissed else { return }
            popupHost.dismiss(animated: true) { [weak self, weak popupHost] in
                guard let self, let popupHost else { return }
                self.didDismiss(popupHost)
            }
            return
        }
        guard requested, isViewLoaded, view.window != nil, presentedViewController == nil else { return }
        // The inner route is a same-host geometry transition, so it no longer
        // contributes navigationTransition preferences to modal presentation.
        // Present the hosting controller directly (Apple WWDC22/10072): its
        // native sizing integration owns both content and popover resizing.
        let host = UIHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        host.modalPresentationStyle = .popover
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = true
        host.preferredContentSize = host.sizeThatFits(in: view.window?.bounds.size ?? view.bounds.size)
        guard let popover = host.popoverPresentationController else { return }
        // Public iOS 26+ popover morph. The source contains the actual visible
        // SwiftUI button, rather than a transparent geometry proxy behind it.
        popover.sourceItem = sourceHost.view
        popover.permittedArrowDirections = .down
        popover.delegate = self
        presentedID = requestID
        popupHost = host
        present(host, animated: true) { [weak self] in self?.reconcilePresentation() }
    }

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let host = popupHost, presentationController.presentedViewController === host else { return }
        didDismiss(host)
    }

    private func didDismiss(_ host: UIHostingController<HanlinModelHostedView<Content>>) {
        guard popupHost === host else { return }
        popupHost = nil
        // A late dismissal must not close a newly requested presentation.
        if requested, requestID == presentedID {
            requested = false
            presentation?.wrappedValue = false
        }
        reconcilePresentation()
    }

    func shutdown() {
        requested = false
        presentation = nil
        popupHost?.dismiss(animated: false)
        popupHost = nil
    }
}
