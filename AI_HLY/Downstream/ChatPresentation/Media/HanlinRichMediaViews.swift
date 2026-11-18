#if HANLIN_A2UI_POC && canImport(UIKit)
import A2UICore
import SwiftUI
import UIKit
import QuickLook

struct HanlinGalleryImage: Identifiable, Hashable {
    let id: String
    let image: URL
    let source: URL
    let title: String
    let description: String

    @MainActor
    static func items(in node: Node) -> [Self] {
        guard let values = node.array(for: "items"), !values.isEmpty, values.count <= 10 else { return [] }
        var result: [Self] = []
        for value in values {
            guard let dictionary = value as? ResolvedDictionary else { return [] }
            let item = Node(id: node.id, type: "GalleryItem", properties: dictionary.storage)
            guard let id = item.string(for: "id"), !id.isEmpty, id.utf8.count <= 128,
                  let rawImage = item.string(for: "url"), let image = HanlinRemoteMediaURL(rawImage)?.url,
                  let rawSource = item.string(for: "sourceUrl"), let source = HanlinRemoteMediaURL(rawSource)?.url,
                  let description = item.string(for: "description"), !description.isEmpty,
                  description.utf8.count <= 2048, !result.contains(where: { $0.id == id }) else { return [] }
            result.append(Self(id: id, image: image, source: source,
                title: String((item.string(for: "title") ?? description).prefix(512)), description: description))
        }
        return result
    }
}

struct HanlinSourceCardDescriptor: Hashable {
    let source: URL
    let title: String?
    let summary: String?
    let thumbnail: URL?

    @MainActor
    init?(node: Node) {
        guard let raw = node.string(for: "url"), let source = HanlinRemoteMediaURL(raw)?.url else { return nil }
        self.source = source
        title = node.string(for: "title").map { String($0.prefix(512)) }
        summary = node.string(for: "description").map { String($0.prefix(2048)) }
        if let raw = node.string(for: "thumbnailUrl"), !raw.isEmpty {
            guard let thumbnail = HanlinRemoteMediaURL(raw)?.url else { return nil }
            self.thumbnail = thumbnail
        } else { thumbnail = nil }
    }
}

@MainActor
struct HanlinImageGallery: View {
    let items: [HanlinGalleryImage]
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var requested = false
    @State private var files: [String: URL] = [:]
    @State private var selected: URL?

    private var active: Bool { isEnabled && scenePhase == .active }
    private var orderedFiles: [URL] { items.compactMap { files[$0.id] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !requested {
                Button("Load images", systemImage: "photo.on.rectangle") { requested = true }
                    .buttonStyle(.bordered)
                    .disabled(!active)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HanlinRichMediaThumbnail(url: item.image, description: item.description,
                                requested: requested && active,
                                onLoaded: { files[item.id] = $0 },
                                onOpen: { selected = $0 })
                            Text(item.title).font(.subheadline).lineLimit(3)
                            Link(destination: item.source) {
                                Label(item.source.host ?? String(localized: "Source"), systemImage: "link")
                                    .font(.caption)
                            }
                            .accessibilityLabel("Open source: \(item.title)")
                        }
                        .frame(width: 180, alignment: .leading)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .accessibilityLabel("Image gallery")
        }
        .quickLookPreview($selected, in: orderedFiles)
        .onChange(of: active) { _, active in if !active { reset() } }
        .onDisappear { if selected == nil { reset() } }
    }

    private func reset() {
        requested = false
        selected = nil
        files.removeAll()
    }
}

@MainActor
struct HanlinSourceCard: View {
    let descriptor: HanlinSourceCardDescriptor
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var attempt = 0
    @State private var metadata: HanlinRichMediaStore.LinkMetadata?
    @State private var failed = false
    @State private var preview: URL?

    private var active: Bool { isEnabled && scenePhase == .active }
    private var title: String { metadata?.title ?? descriptor.title ?? descriptor.source.host ?? String(localized: "Source") }
    private var summary: String { metadata?.summary ?? descriptor.summary ?? "" }
    private var thumbnail: URL? { metadata?.thumbnail ?? descriptor.thumbnail }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thumbnail {
                HanlinRichMediaThumbnail(url: thumbnail, description: title,
                    requested: attempt > 0 && active, onLoaded: { _ in }, onOpen: { preview = $0 })
                    .id(thumbnail)
            }
            Text(title).font(.headline).textSelection(.enabled)
            if !summary.isEmpty { Text(summary).font(.subheadline).lineLimit(4).textSelection(.enabled) }
            Link(destination: descriptor.source) {
                Label(descriptor.source.host ?? String(localized: "Open source"), systemImage: "link")
                    .font(.caption)
            }
            .accessibilityLabel("Open linked source")
            if attempt == 0 || failed {
                Button(failed ? "Retry preview" : "Load link preview", systemImage: "arrow.down.doc") {
                    failed = false
                    attempt += 1
                }
                .buttonStyle(.bordered)
                .disabled(!active)
            } else if metadata == nil {
                ProgressView("Loading link preview")
            }
            if failed { Text("Preview unavailable. You can still open the source.").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .quickLookPreview($preview)
        .task(id: active && attempt > 0 ? attempt : nil) {
            guard active, attempt > 0 else { return }
            do {
                let result = try await HanlinRichMediaStore.shared.metadata(for: descriptor.source)
                try Task.checkCancellation()
                metadata = result
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
        .onChange(of: active) { _, active in if !active { reset() } }
        .onDisappear { if preview == nil { reset() } }
    }

    private func reset() {
        attempt = 0
        preview = nil
        metadata = nil
        failed = false
    }
}

@MainActor
private struct HanlinRichMediaThumbnail: View {
    let url: URL
    let description: String
    let requested: Bool
    let onLoaded: (URL) -> Void
    let onOpen: (URL) -> Void
    @State private var file: URL?
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0

    private struct Request: Hashable { let url: URL; let retry: Int }

    var body: some View {
        Group {
            if let image, let file {
                Button { onOpen(file) } label: {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: 180, height: 132)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(description)
                .accessibilityHint("Open full-size image")
            } else if requested {
                if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        Button("Retry image") { failed = false; retry += 1 }
                    }
                    .accessibilityLabel("Image unavailable")
                } else { ProgressView("Loading image") }
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                    .accessibilityLabel(description)
            }
        }
        .frame(width: 180, height: 132)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .clipped()
        .task(id: requested ? Request(url: url, retry: retry) : nil) {
            guard requested else { clear(); return }
            do {
                let result = try await HanlinRichMediaStore.shared.image(for: url)
                try Task.checkCancellation()
                guard let loaded = UIImage(contentsOfFile: result.url.path) else {
                    throw HanlinRichMediaStore.Failure.unsupportedContent
                }
                file = result.url
                image = loaded
                failed = false
                onLoaded(result.url)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
        .onDisappear { clear() }
    }

    private func clear() {
        image = nil
        file = nil
        failed = false
    }
}
#endif
