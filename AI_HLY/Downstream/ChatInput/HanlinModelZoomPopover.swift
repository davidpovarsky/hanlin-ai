import SwiftUI
import UIKit

/// UIKit owns the popover's source-item morph; SwiftUI owns its inner geometry morph.
/// A navigationTransition on a SwiftUI popover's root competes with the inner
/// destination transition (42539502009 rendered an invisible All Models page).
@MainActor
struct HanlinModelZoomPopover<Source: View, Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let presentationID: Int
    let contentSize: CGSize
    let onResizeCompleted: @MainActor (Int, CGSize) -> Void
    let source: Source
    let content: Content

    init(isPresented: Binding<Bool>, presentationID: Int, contentSize: CGSize,
         onResizeCompleted: @escaping @MainActor (Int, CGSize) -> Void,
         @ViewBuilder source: () -> Source, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.presentationID = presentationID
        self.contentSize = contentSize
        self.onResizeCompleted = onResizeCompleted
        self.source = source()
        self.content = content()
    }

    func makeUIViewController(context: Context) -> HanlinModelPopoverController<Source, Content> {
        HanlinModelPopoverController(
            source: HanlinModelHostedView(content: source, environment: context.environment),
            content: HanlinModelHostedView(content: content, environment: context.environment),
            contentSize: contentSize
        )
    }

    func updateUIViewController(_ controller: HanlinModelPopoverController<Source, Content>, context: Context) {
        controller.update(
            source: HanlinModelHostedView(content: source, environment: context.environment),
            content: HanlinModelHostedView(content: content, environment: context.environment),
            isPresented: $isPresented, presentationID: presentationID, contentSize: contentSize,
            animatedResize: !context.environment.accessibilityReduceMotion && !context.transaction.disablesAnimations,
            onResizeCompleted: onResizeCompleted
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

/// A single native size authority. SwiftUI fills these bounds instead of
/// animating a second fixed frame against the popover's presentation mask.
@MainActor
final class HanlinModelSizingHost<Content: View>: UIHostingController<HanlinModelHostedView<Content>> {
    private var resizeGeneration = 0
    private var isResizing = false
    private var observedNativeTransition = false
    private var resizeCompletion: (@MainActor () -> Void)?

    init(content: HanlinModelHostedView<Content>) {
        super.init(rootView: content)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:)") }

    func resize(to size: CGSize, animated: Bool, completion: @escaping @MainActor () -> Void) {
        resizeCompletion = completion
        guard size != preferredContentSize else {
            if !isResizing { finishResize(resizeGeneration) }
            return
        }
        resizeGeneration &+= 1
        let generation = resizeGeneration
        isResizing = true
        observedNativeTransition = false
        if animated, isViewLoaded, view.window != nil {
            // UIKit animates preferredContentSize changes in a live popover.
            preferredContentSize = size
            presentationController?.containerView?.layoutIfNeeded()
            view.layoutIfNeeded()
            if !observedNativeTransition {
                if let transitionCoordinator {
                    observeResize(transitionCoordinator, generation: generation)
                } else {
                    // An already-clamped size needs no visible transition.
                    finishResize(generation)
                }
            }
        } else {
            UIView.performWithoutAnimation {
                preferredContentSize = size
                viewIfLoaded?.layoutIfNeeded()
            }
            finishResize(generation)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if isResizing { observeResize(coordinator, generation: resizeGeneration) }
    }

    private func observeResize(_ coordinator: any UIViewControllerTransitionCoordinator, generation: Int) {
        observedNativeTransition = true
        let registered = coordinator.animate(alongsideTransition: nil) { [weak self] context in
            let completed = !context.isCancelled
            Task { @MainActor in self?.finishResize(generation, completed: completed) }
        }
        if !registered { finishResize(generation) }
    }

    private func finishResize(_ generation: Int, completed: Bool = true) {
        guard generation == resizeGeneration else { return }
        isResizing = false
        let completion = resizeCompletion
        resizeCompletion = nil
        if completed, let completion {
            // An unchanged/clamped size can finish inside updateUIViewController.
            // Deliver the model mutation after that SwiftUI update, and reject a
            // newer resize that supersedes this queued delivery.
            Task { @MainActor [weak self] in
                guard let self, generation == self.resizeGeneration, !self.isResizing else { return }
                completion()
            }
        }
    }
}

@MainActor
final class HanlinModelPopoverController<Source: View, Content: View>: UIViewController,
    UIPopoverPresentationControllerDelegate {
    private let sourceHost: UIHostingController<HanlinModelHostedView<Source>>
    private var content: HanlinModelHostedView<Content>
    private var contentSize: CGSize
    private var popupHost: HanlinModelSizingHost<Content>?
    private var onResizeCompleted: (@MainActor (Int, CGSize) -> Void)?
    private var presentation: Binding<Bool>?
    private var requested = false
    private var requestID = 0
    private var presentedID = 0

    init(source: HanlinModelHostedView<Source>, content: HanlinModelHostedView<Content>, contentSize: CGSize) {
        sourceHost = UIHostingController(rootView: source)
        self.content = content
        self.contentSize = contentSize
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
                isPresented: Binding<Bool>, presentationID: Int, contentSize: CGSize,
                animatedResize: Bool, onResizeCompleted: @escaping @MainActor (Int, CGSize) -> Void) {
        sourceHost.rootView = source
        self.content = content
        self.contentSize = contentSize
        self.onResizeCompleted = onResizeCompleted
        presentation = isPresented
        requested = isPresented.wrappedValue
        requestID = presentationID
        if requested, presentedID == requestID {
            if let host = popupHost {
                host.rootView = content
                let generation = presentedID
                host.resize(to: contentSize, animated: animatedResize) { [weak self, weak host] in
                    guard let self, let host, self.popupHost === host,
                          self.requested, self.requestID == generation else { return }
                    self.onResizeCompleted?(generation, contentSize)
                }
            }
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
        let host = HanlinModelSizingHost(content: content)
        host.modalPresentationStyle = .popover
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = true
        host.resize(to: contentSize, animated: false) {}
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

    private func didDismiss(_ host: HanlinModelSizingHost<Content>) {
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
