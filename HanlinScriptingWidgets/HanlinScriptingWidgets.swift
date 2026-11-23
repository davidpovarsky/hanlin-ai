import AppIntents
import HanlinExtensionContracts
import HanlinWidgetUI
import SwiftUI
import WidgetKit

@main
struct HanlinScriptingWidgetBundle: WidgetBundle {
    var body: some Widget {
        HanlinScriptingWidget(kind: HanlinExtensionHostConfiguration.hanlinWidgetKind)
        HanlinScriptingLiveActivityWidget()
        HanlinOriginalScriptWidgetLiveActivityWidget()
    }
}

struct HanlinScriptingWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinWidgetIntentsPackage.self]
    }
}
