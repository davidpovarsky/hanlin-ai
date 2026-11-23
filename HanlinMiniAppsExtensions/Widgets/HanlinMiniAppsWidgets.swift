import AppIntents
import HanlinExtensionContracts
import HanlinWidgetUI
import SwiftUI
import WidgetKit

@main
struct HanlinMiniAppsWidgetBundle: WidgetBundle {
    var body: some Widget {
        HanlinScriptingWidget(kind: HanlinExtensionHostConfiguration.miniapps.widgetKind)
        HanlinScriptingLiveActivityWidget()
    }
}

struct HanlinMiniAppsWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinWidgetIntentsPackage.self]
    }
}
