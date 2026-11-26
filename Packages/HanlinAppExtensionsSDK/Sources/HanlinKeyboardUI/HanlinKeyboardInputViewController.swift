#if canImport(UIKit)
import Foundation
import HanlinExtensionContracts
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinTranslationUI
import SwiftUI
import UIKit

/// A real system keyboard. Installed programs are read from the product's
/// publication; every mutable renderer/service file stays in this extension.
@MainActor
open class HanlinKeyboardInputViewController: UIInputViewController {
    open var hostConfiguration: HanlinExtensionHostConfiguration { .init() }

    private let model = HanlinKeyboardModel()
    private var hosting: UIHostingController<HanlinKeyboardRoot>?
    private var loadTask: Task<Void, Never>?
    private var loadID = UUID()
    private var sessionID = UUID()
    private var applyingEdits = false
    private static let selectedKey = "hanlin.keyboard.selectedPresentation"

    open override func viewDidLoad() {
        super.viewDidLoad()
        let root = HanlinKeyboardRoot(model: model,
            select: { [weak self] record in self?.select(record) },
            reload: { [weak self] in self?.reloadCatalog() },
            nextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            insert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
                self?.refreshContext()
            },
            delete: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
                self?.refreshContext()
            },
            effect: { [weak self] effect, request in self?.apply(effect, request: request) })
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 300)
        height.priority = .defaultHigh
        height.isActive = true
        host.didMove(toParent: self)
        hosting = host
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionID = UUID()
        reloadCatalog()
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loadTask?.cancel()
        loadID = UUID()
        model.request = nil
    }

    open override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        if !applyingEdits { refreshContext() }
    }

    open override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        if !applyingEdits { refreshContext() }
    }

    private func reloadCatalog() {
        loadTask?.cancel()
        let currentLoad = UUID()
        loadID = currentLoad
        model.error = nil
        model.isLoading = true
        model.needsNextKeyboard = needsInputModeSwitchKey
        let configuration = hostConfiguration
        loadTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let store = try HanlinScriptExtensionStore(hostConfiguration: configuration)
                    let snapshot = try store.loadReadOnly()
                    let inactive = Set(snapshot?.inactiveWidgetInstallations ?? [])
                    let records = (snapshot?.nativePresentations ?? []).filter {
                        $0.kind == .keyboard && !inactive.contains($0.identity.installedPackageID.rawValue)
                    }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                    return (store, records)
                }.value
                guard let self, !Task.isCancelled, self.loadID == currentLoad else { return }
                self.model.store = result.0
                self.model.records = result.1
                guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw HanlinNativePresentationError.unavailable
                }
                self.model.storage = .extensionLocal(root: support.appendingPathComponent(
                    "HanlinKeyboardPresentations", isDirectory: true))
                self.model.isLoading = false
                let desired = self.model.selectedKey ?? UserDefaults.standard.string(forKey: Self.selectedKey)
                if let record = result.1.first(where: { keyboardSelectionKey($0.identity) == desired }) ?? result.1.first {
                    self.select(record)
                } else {
                    self.model.selectedKey = nil
                    self.model.request = nil
                }
            } catch {
                guard let self, !Task.isCancelled, self.loadID == currentLoad else { return }
                self.model.isLoading = false
                self.model.request = nil
                self.model.error = error.localizedDescription
            }
        }
    }

    private func select(_ record: HanlinNativePresentationSnapshot) {
        let key = keyboardSelectionKey(record.identity)
        if model.selectedKey != key { sessionID = UUID() }
        model.selectedKey = key
        UserDefaults.standard.set(key, forKey: Self.selectedKey)
        refreshContext()
    }

    private func refreshContext() {
        model.needsNextKeyboard = needsInputModeSwitchKey
        guard let record = model.records.first(where: { keyboardSelectionKey($0.identity) == model.selectedKey }) else {
            model.request = nil
            return
        }
        let proxy = textDocumentProxy
        model.request = .init(identity: record.identity, kind: .keyboard, sessionID: sessionID,
            inputText: proxy.selectedText ?? "",
            keyboard: .init(documentContextBeforeInput: proxy.documentContextBeforeInput,
                documentContextAfterInput: proxy.documentContextAfterInput,
                selectedText: proxy.selectedText, hasFullAccess: hasFullAccess))
    }

    private func apply(_ effect: HanlinNativePresentationEffect, request: HanlinNativePresentationRequest) {
        guard model.request == request, request.kind == .keyboard else { return }
        do { try effect.validate(for: request) }
        catch { model.error = error.localizedDescription; return }
        guard !effect.keyboardEdits.isEmpty else { return }
        applyingEdits = true
        defer { applyingEdits = false; refreshContext() }
        for edit in effect.keyboardEdits {
            switch edit.operation {
            case .insertText: textDocumentProxy.insertText(edit.text!)
            case .deleteBackward: textDocumentProxy.deleteBackward()
            case .adjustTextPosition: textDocumentProxy.adjustTextPosition(byCharacterOffset: edit.offset!)
            case .nextInputMode: advanceToNextInputMode()
            }
        }
    }
}

private func keyboardSelectionKey(_ identity: HanlinScriptExtensionIdentity) -> String {
    // JSON string framing avoids ambiguous separators in declared entrypoint IDs.
    let parts = [identity.installedPackageID.rawValue, identity.entrypointID, identity.variantID]
    return (try? JSONEncoder().encode(parts).base64EncodedString()) ?? ""
}

@MainActor
private final class HanlinKeyboardModel: ObservableObject {
    @Published var records: [HanlinNativePresentationSnapshot] = []
    @Published var selectedKey: String?
    @Published var request: HanlinNativePresentationRequest?
    @Published var store: HanlinScriptExtensionStore?
    @Published var storage: HanlinNativePresentationStorage = .shared
    @Published var error: String?
    @Published var isLoading = false
    @Published var needsNextKeyboard = true
}

@MainActor
private struct HanlinKeyboardRoot: View {
    @ObservedObject var model: HanlinKeyboardModel
    let select: (HanlinNativePresentationSnapshot) -> Void
    let reload: () -> Void
    let nextKeyboard: () -> Void
    let insert: (String) -> Void
    let delete: () -> Void
    let effect: (HanlinNativePresentationEffect, HanlinNativePresentationRequest) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    ForEach(model.records, id: \.identity) { record in
                        Button(record.displayName) { select(record) }
                    }
                } label: {
                    Label(model.records.first(where: {
                        keyboardSelectionKey($0.identity) == model.selectedKey
                    })?.displayName ?? "MiniApp keyboard", systemImage: "keyboard")
                        .lineLimit(1)
                }
                .disabled(model.records.isEmpty)
                Spacer()
                Button(action: reload) { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh keyboards")
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("hanlin.keyboard.error")
            }
            ScrollView {
                if model.isLoading {
                    ProgressView()
                } else if let request = model.request, let store = model.store {
                    HanlinNativePresentationContentView(request: request, store: store, storage: model.storage) {
                        effect($0, request)
                    }
                    .accessibilityIdentifier("hanlin.keyboard.presentation")
                } else if model.error == nil {
                    Text("Install a MiniApp with a keyboard entrypoint to use its keyboard here.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                if model.needsNextKeyboard {
                    Button(action: nextKeyboard) { Image(systemName: "globe") }
                        .accessibilityLabel("Next keyboard")
                }
                Button("Space") { insert(" ") }.frame(maxWidth: .infinity)
                Button { insert("\n") } label: { Image(systemName: "return") }
                    .accessibilityLabel("Return")
                Button(action: delete) { Image(systemName: "delete.left") }
                    .accessibilityLabel("Delete")
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.background)
    }
}
#endif
