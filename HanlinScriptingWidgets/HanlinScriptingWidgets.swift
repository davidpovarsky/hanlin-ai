import AppIntents
import HanlinCameraCaptureUI
import ExpoWidgets
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
        HanlinOriginalExpoWidget()
        ExpoWidgets.WidgetLiveActivity()
        ScriptWidgetButtonControlWidget()
        ScriptWidgetControlWidget()
        HanlinCameraCaptureControl()
    }
}

struct HanlinScriptingWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinWidgetIntentsPackage.self, HanlinExpoWidgetsIntentsPackage.self, HanlinCameraCaptureIntentsPackage.self]
    }
}
