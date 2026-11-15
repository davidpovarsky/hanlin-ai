import Foundation
import UniformTypeIdentifiers

public enum HanlinShareItemLoader {
    /// Completion receives an owned snapshot, never an NSItemProvider URL.
    /// The copy must finish before the provider callback returns.
    @discardableResult
    public static func load(_ provider: NSItemProvider, store: HanlinShareInboxStore,
                            batchID: UUID, ordinal: Int,
                            completion: @escaping @Sendable (HanlinShareItem) -> Void) -> Progress? {
        let fileType = provider.registeredTypeIdentifiers.first {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
        }
        if let fileType {
            let name = provider.suggestedName
            return provider.loadFileRepresentation(forTypeIdentifier: fileType) { url, error in
                guard error == nil, let url else {
                    completion(.rejected(ordinal: ordinal, typeIdentifier: fileType, failure: .providerFailed)); return
                }
                copy(url, store: store, batchID: batchID, ordinal: ordinal, type: fileType, name: name, completion: completion)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return provider.loadObject(ofClass: URL.self) { url, error in
                guard error == nil, let url else {
                    completion(.rejected(ordinal: ordinal, typeIdentifier: UTType.url.identifier, failure: .providerFailed)); return
                }
                if url.isFileURL {
                    copy(url, store: store, batchID: batchID, ordinal: ordinal, type: UTType.fileURL.identifier, name: nil, completion: completion)
                } else {
                    completion(.text(url.absoluteString, ordinal: ordinal, typeIdentifier: UTType.url.identifier, isURL: true))
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return provider.loadObject(ofClass: String.self) { text, error in
                guard error == nil, let text else {
                    completion(.rejected(ordinal: ordinal, typeIdentifier: UTType.plainText.identifier, failure: .providerFailed)); return
                }
                completion(.text(text, ordinal: ordinal, typeIdentifier: UTType.plainText.identifier))
            }
        }
        completion(.rejected(ordinal: ordinal, typeIdentifier: provider.registeredTypeIdentifiers.first ?? "unknown", failure: .unsupportedType))
        return nil
    }

    private static func copy(_ url: URL, store: HanlinShareInboxStore, batchID: UUID,
                             ordinal: Int, type: String, name: String?,
                             completion: @Sendable (HanlinShareItem) -> Void) {
        do { completion(try store.copyFile(url, batchID: batchID, ordinal: ordinal, typeIdentifier: type, suggestedName: name)) }
        catch { completion(.rejected(ordinal: ordinal, typeIdentifier: type, failure: .copyFailed)) }
    }
}
