#if HANLIN_A2UI_POC
import A2UICore
import A2UISwiftUI
import BasicCatalogSwiftUI
import SwiftUI

@MainActor
enum HanlinMediaCatalogImplementation {
    static func basicCatalog(locale: Locale) -> Catalog<ComponentImplementation> {
        var catalog = BasicCatalogImplementation.makeCatalog(version: .v10, locale: locale)
        for name in ["Image", "Video", "AudioPlayer"] {
            guard let original = catalog.components[name] else { continue }
            catalog.components[name] = ComponentImplementation(api: original) { node in
                HanlinA2UIMediaURLGate(node: node, isPlayer: name != "Image", builder: original.builder)
            }
        }
        return catalog
    }

    static func makeCatalog(locale: Locale) -> Catalog<ComponentImplementation> {
        var catalog = basicCatalog(locale: locale)
        catalog.id = HanlinA2UIIngress.mediaCatalogID
        catalog.components["YouTube"] = ComponentImplementation(api: HanlinMediaCatalog.youTube) { node in
            Group {
                if let value = node.string(for: "url"), value.utf8.count <= 2048, let url = URL(string: value),
                   let video = HanlinYouTubeVideo(url: url) {
                    HanlinYouTubePlayerView(video: video)
                } else {
                    ContentUnavailableView("Video unavailable", systemImage: "video.slash",
                        description: Text("This video link is not supported."))
                }
            }
        }
        return catalog
    }
}
#endif
