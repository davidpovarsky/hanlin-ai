import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Adding to ChavrusaChat…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await importItems() }
    }

    @MainActor
    private func importItems() async {
        do {
            let providers = extensionContext?.inputItems
                .compactMap { $0 as? NSExtensionItem }
                .flatMap { $0.attachments ?? [] } ?? []
            var items: [SharedItem] = []
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    items.append(.init(id: UUID(), createdAt: .now, text: nil, url: url, fileName: nil))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    items.append(.init(id: UUID(), createdAt: .now, text: text, url: nil, fileName: nil))
                } else if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
                          let fileURL = try await provider.loadItem(forTypeIdentifier: UTType.data.identifier) as? URL {
                    items.append(.init(id: UUID(), createdAt: .now, text: nil, url: fileURL, fileName: fileURL.lastPathComponent))
                }
            }
            try save(items)
            statusLabel.text = "Added to ChavrusaChat"
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.text = error.localizedDescription
            extensionContext?.cancelRequest(withError: error)
        }
    }

    private func save(_ newItems: [SharedItem]) throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.itorah.chavrusachat"
        ) else { throw CocoaError(.fileNoSuchFile) }
        let url = container.appending(path: "share-inbox.json")
        let existing = (try? JSONDecoder().decode([SharedItem].self, from: Data(contentsOf: url))) ?? []
        try JSONEncoder().encode(existing + newItems).write(to: url, options: .atomic)
    }
}

private struct SharedItem: Codable {
    let id: UUID
    let createdAt: Date
    let text: String?
    let url: URL?
    let fileName: String?
}
