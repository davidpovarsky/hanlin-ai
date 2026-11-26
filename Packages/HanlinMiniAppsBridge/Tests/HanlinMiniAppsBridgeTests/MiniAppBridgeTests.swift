import Foundation
import Testing
@testable import HanlinMiniAppsBridge

private func fixture() throws -> (URL, MiniAppBridgeStore) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("miniapps-\(UUID().uuidString)")
    return (url, try MiniAppBridgeStore(containerURL: url))
}

private func invocation(id: UUID = UUID(), text: String = "שלום 🙂") -> MiniAppInvocation {
    .init(id: id, appID: "com.hanlin.text-studio",
        source: .init(appID: "org.otzaria.app", displayName: "אוצריא", documentID: "doc-1",
            documentTitle: "מקור", revision: "17",
            selection: .init(location: 0, length: text.utf16.count, text: text, blockIDs: ["block-1"]),
            documentText: text, kind: "annotation", locator: "book:page:4", sceneID: "scene-A",
            metadata: ["spaceID": "space-1", "annotation": "{\"id\":\"note-1\"}"]),
        inputs: [.init(kind: .text, text: text)], operation: .replaceSelection,
        callbacks: .init(success: URL(string: "maktabah://miniapps-result?document=doc-1"),
                         error: URL(string: "maktabah://miniapps-error"),
                         cancel: URL(string: "maktabah://miniapps-cancel")))
}

@Test func requestRoundTripColdReturnAndDurableAcknowledgement() throws {
    let (root, sender) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = invocation()
    let link = try sender.enqueue(original)
    #expect(link.scheme == "hanlinminiapps")
    #expect(MiniAppBridgeStore.requestID(from: link) == original.id)
    let receiver = try MiniAppBridgeStore(containerURL: root)
    #expect(try receiver.request(id: original.id) == original)
    #expect(try receiver.pendingRequests() == [original])
    let output = MiniAppResult(requestID: original.id, operation: .replaceSelection,
                              items: [.init(kind: .text, text: "תוצאה 👩‍💻")])
    try receiver.complete(output)
    #expect(try sender.pendingResults(sourceAppID: "org.otzaria.app") == [output])
    #expect(try sender.pendingResults(sourceAppID: "different-app").isEmpty)
    #expect(try receiver.pendingRequests().isEmpty)
    #expect(try sender.acknowledgeResult(id: original.id, sourceAppID: "org.otzaria.app"))
    #expect(try !receiver.acknowledgeResult(id: original.id, sourceAppID: "org.otzaria.app"))
    #expect(try receiver.pendingResults(sourceAppID: "org.otzaria.app").isEmpty)
    #expect(try receiver.result(id: original.id) == output)
}

@Test func duplicateDeliveryCannotOverwriteOrReplayCompletedResult() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let request = invocation()
    try store.enqueue(request)
    try store.enqueue(request)
    #expect(throws: MiniAppBridgeError.duplicateIdentity) {
        try store.enqueue(invocation(id: request.id, text: "different"))
    }
    let output = MiniAppResult(requestID: request.id, items: [.init(kind: .text, text: "result")])
    try store.complete(output)
    try store.complete(output)
    #expect(throws: MiniAppBridgeError.conflictingResult) {
        try store.complete(.init(requestID: request.id, items: [.init(kind: .text, text: "changed")]))
    }
    try store.acknowledgeResult(id: request.id, sourceAppID: request.source.appID)
    try store.enqueue(request)
    #expect(try store.pendingRequests().isEmpty)
    #expect(try store.pendingResults(sourceAppID: request.source.appID).isEmpty)
}

@Test func callbackVariantsPreserveContextAndEncodeErrors() throws {
    let request = invocation()
    for status in [MiniAppResult.Status.success, .error, .cancelled] {
        let result = MiniAppResult(requestID: request.id, status: status, message: "שגיאה & = ?")
        let url = try #require(request.callbackURL(for: result))
        #expect(MiniAppBridgeStore.requestID(from: url) == request.id)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.queryItems?.first { $0.name == "status" }?.value == status.rawValue)
        if status == .success {
            #expect(parts.queryItems?.first { $0.name == "document" }?.value == "doc-1")
        }
        if status == .error {
            #expect(parts.queryItems?.first { $0.name == "errorMessage" }?.value == "שגיאה & = ?")
        }
    }
    #expect(request.callbackURL(for: .init(requestID: UUID())) == nil)
}

@Test func favoritesEditAndVisibilitySurviveReopen() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let catalog = ["a", "b", "c", "d"].map { MiniAppCatalogItem(id: $0, title: $0) }
    try store.publishCatalog(catalog)
    try store.updatePreferences {
        $0.setFavorite("a", true); $0.setFavorite("b", true); $0.setFavorite("c", true)
        $0.moveFavorites(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        $0.setVisible("d", false)
        $0.opensInNewWindow = false
    }
    let cold = try MiniAppBridgeStore(containerURL: root)
    let preferences = try cold.preferences()
    #expect(preferences.favorites == ["b", "c", "a"])
    #expect(preferences.hidden == ["d"])
    #expect(!preferences.opensInNewWindow)
    #expect(preferences.orderedItems(try cold.loadCatalog()).map(\.id) == ["b", "c", "a"])
    try cold.updatePreferences { $0.setFavorite("d", true) }
    #expect(try cold.preferences().hidden.isEmpty)
    try cold.updatePreferences { $0.setFavorite("b", false) }
    #expect(try cold.preferences().orderedItems(catalog).map(\.id) == ["c", "a", "d", "b"])
}

@Test func concurrentStoresDoNotLosePreferenceUpdates() async throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<24 {
            group.addTask {
                let peer = try MiniAppBridgeStore(containerURL: root)
                try peer.updatePreferences { $0.setFavorite("app-\(index)", true) }
            }
        }
        try await group.waitForAll()
    }
    #expect(try store.preferences().favorites.count == 24)
}

@Test func largeInputAndAttachmentRemainByteExact() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let text = String(repeating: "אבג🙂\n", count: 90_000)
    let request = invocation(text: text)
    try store.enqueue(request)
    #expect(try store.request(id: request.id)?.inputs.first?.text == text)
    let bytes = Data((0..<400_000).map { UInt8($0 % 251) })
    let attachment = try store.writeAttachment(bytes, name: "תמונה.bin", typeIdentifier: "public.data")
    let id = try #require(attachment.attachmentID)
    #expect(try Data(contentsOf: store.attachmentURL(id: id)) == bytes)
    let source = root.appendingPathComponent("original.bin")
    try bytes.write(to: source)
    let copied = try store.importAttachment(at: source)
    try FileManager.default.removeItem(at: source)
    #expect(try Data(contentsOf: store.attachmentURL(id: #require(copied.attachmentID))) == bytes)
}

@Test func unicodeSelectionReplacementInsertionAndChangedSelection() throws {
    let original = "א 🙂 שלום סוף"
    let range = (original as NSString).range(of: "שלום")
    let selection = MiniAppTextSelection(location: range.location, length: range.length, text: "שלום")
    let replacement = MiniAppResult(requestID: UUID(), operation: .replaceSelection,
                                   items: [.init(kind: .text, text: "ברכה")])
    #expect(try MiniAppTextEditing.applying(replacement, to: original, selection: selection) == "א 🙂 ברכה סוף")
    let insertion = MiniAppResult(requestID: UUID(), operation: .insert,
                                 items: [.init(kind: .text, text: " חדש")])
    #expect(try MiniAppTextEditing.applying(insertion, to: original, selection: selection) == "א 🙂 שלום חדש סוף")
    #expect(throws: MiniAppBridgeError.selectionChanged) {
        try MiniAppTextEditing.applying(replacement, to: "א 🙂 אחרר סוף", selection: selection)
    }
    #expect(throws: MiniAppBridgeError.invalidSelection) {
        try MiniAppTextEditing.applying(replacement, to: original,
            selection: .init(location: Int.max, length: Int.max, text: ""))
    }
}

@Test func wrongSourceAcknowledgementPreservesOriginalResult() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let request = invocation()
    try store.enqueue(request)
    try store.complete(.init(requestID: request.id, status: .cancelled))
    #expect(throws: MiniAppBridgeError.wrongSource) {
        try store.acknowledgeResult(id: request.id, sourceAppID: "different")
    }
    #expect(try store.pendingResults(sourceAppID: request.source.appID).count == 1)
}

@Test func newWindowDefaultAndDistinctInvocationIdentity() {
    #expect(MiniAppPreferences().opensInNewWindow)
    #expect(invocation().opensInNewWindow)
    #expect(invocation().id != invocation().id)
}

@Test func catalogProjectionPreservesIdentityAndRejectsDuplicateEntries() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let item = MiniAppCatalogItem(id: "app", title: "Text", supportedContentTypes: ["public.text"],
                                 localizedTitles: ["he": "טקסט"])
    try store.publishCatalog([item])
    #expect(try store.loadCatalog() == [item])
    #expect(item.title(locale: Locale(identifier: "he_IL")) == "טקסט")
    #expect(item.accepts([.init(kind: .text, text: "שלום")]))
    #expect(!item.accepts([.init(kind: .file, attachmentID: UUID())]))
    #expect(throws: MiniAppBridgeError.duplicateCatalogIdentity) {
        try store.publishCatalog([item, item])
    }
}

@Test func unsupportedOnDiskSchemaIsNotSilentlyReset() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = store.rootURL.appendingPathComponent("catalog.json")
    try Data("{\"schemaVersion\":2,\"items\":[]}".utf8).write(to: file)
    #expect(throws: MiniAppBridgeError.unsupportedSchema) { try store.loadCatalog() }
    #expect(try String(contentsOf: file, encoding: .utf8).contains("\"schemaVersion\":2"))
}

@Test func originalIconsAndLocalizedSubtitlesSurviveColdCatalogRead() throws {
    let (root, store) = try fixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jX1sAAAAASUVORK5CYII="))
    let item = MiniAppCatalogItem(id: "package.icon", title: "Original", subtitle: "Fallback",
        localizedTitles: ["he": "מקור"], iconData: png,
        localizedSubtitles: ["he": "תיאור מקורי", "en": "Original description"])
    try store.publishCatalog([item])
    let cold = try MiniAppBridgeStore(containerURL: root)
    let decoded = try #require(cold.loadCatalog().first)
    #expect(decoded.iconData == png)
    #expect(decoded.subtitle(locale: Locale(identifier: "he_IL")) == "תיאור מקורי")
    #expect(decoded.subtitle(locale: Locale(identifier: "en_US")) == "Original description")
    #expect(decoded.subtitle(locale: Locale(identifier: "fr_FR")) == "Fallback")
}

@Test func preIconSchemaV1CatalogRemainsCompatible() throws {
    let json = Data(#"{"id":"legacy","title":"Legacy","subtitle":"Old description","systemImage":"book","supportedContentTypes":[],"supportedOperations":["display"],"localizedTitles":{"he":"מקורי"}}"#.utf8)
    let item = try JSONDecoder().decode(MiniAppCatalogItem.self, from: json)
    #expect(item.iconData == nil)
    #expect(item.localizedSubtitles == nil)
    #expect(item.subtitle(locale: Locale(identifier: "he_IL")) == "Old description")
    #expect(item.title(locale: Locale(identifier: "he_IL")) == "מקורי")
}
