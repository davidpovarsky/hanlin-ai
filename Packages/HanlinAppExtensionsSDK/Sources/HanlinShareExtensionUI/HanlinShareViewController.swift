#if canImport(UIKit)
import HanlinExtensionContracts
import HanlinLocalization
import HanlinScriptStore
import UIKit

open class HanlinShareViewController: UIViewController {
    private let suppliedConfiguration: HanlinExtensionHostConfiguration?

    /// Override only host policy in an extension's principal-class wrapper.
    open var hostConfiguration: HanlinExtensionHostConfiguration {
        suppliedConfiguration ?? .init()
    }

    public init(configuration: HanlinExtensionHostConfiguration) {
        self.suppliedConfiguration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    public override init(nibName: String? = nil, bundle: Bundle? = nil) {
        self.suppliedConfiguration = nil
        super.init(nibName: nibName, bundle: bundle)
    }

    public required init?(coder: NSCoder) {
        self.suppliedConfiguration = nil
        super.init(coder: coder)
    }

    private let statusLabel = UILabel()
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var importTask: Task<Void, Never>?
    private var currentProgress: Progress?
    private var staging: (HanlinShareInboxStore, UUID)?

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = String(localized: "Saving shared items…", bundle: HanlinLocalization.bundle)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        doneButton.setTitle(String(localized: "Done", bundle: HanlinLocalization.bundle), for: .normal)
        doneButton.isEnabled = false
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)
        cancelButton.setTitle(String(localized: "Cancel", bundle: HanlinLocalization.bundle), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelImport), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [statusLabel, doneButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard importTask == nil else { return }
        importTask = Task { await importItems() }
    }

    @MainActor
    private func importItems() async {
        do {
            guard let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: try hostConfiguration.requireAppGroupIdentifier()
            ) else { throw HanlinShareInboxError.invalidPath }
            let store = try HanlinShareInboxStore(container: hostConfiguration.storageContainer(in: container, createIfNeeded: true))
            let batchID = try store.begin()
            staging = (store, batchID)
            let providers = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .flatMap { $0.attachments ?? [] } ?? []
            var items: [HanlinShareItem] = []
            for (ordinal, provider) in providers.enumerated() {
                try Task.checkCancellation()
                items.append(await load(provider, store: store, batchID: batchID, ordinal: ordinal))
            }
            try Task.checkCancellation()
            _ = try store.commit(batchID, items: items)
            staging = nil
            currentProgress = nil
            let hasErrors = items.contains { $0.content == .rejected }
            statusLabel.text = hasErrors
                ? String(localized: "Saved for Hanlin with item errors. Open the app to review this batch; no action has run yet.", bundle: HanlinLocalization.bundle)
                : String(localized: "Saved for Hanlin. Open the app to review these items; no action has run yet.", bundle: HanlinLocalization.bundle)
            doneButton.isEnabled = true
            cancelButton.isHidden = true
        } catch is CancellationError {
            discardStaging()
        } catch {
            discardStaging()
            statusLabel.text = String(localized: "The shared items could not be saved. Cancel and try again.", bundle: HanlinLocalization.bundle)
        }
    }

    private func load(_ provider: NSItemProvider, store: HanlinShareInboxStore,
                      batchID: UUID, ordinal: Int) async -> HanlinShareItem {
        await withCheckedContinuation { continuation in
            currentProgress = HanlinShareItemLoader.load(provider, store: store, batchID: batchID, ordinal: ordinal) { item in
                continuation.resume(returning: item)
            }
        }
    }

    @objc private func finish() { extensionContext?.completeRequest(returningItems: nil) }

    @objc private func cancelImport() {
        importTask?.cancel()
        currentProgress?.cancel()
        discardStaging()
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func discardStaging() {
        if let (store, id) = staging { try? store.abort(id) }
        staging = nil
    }
}

#endif
