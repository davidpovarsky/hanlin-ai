// Original ScriptWidget source, Copyright 2021-2026 everettjf and contributors.
// Apache-2.0; license/notice retained in HanlinScriptWidgetOriginal/Original.
// Hanlin adaptations: public module API and installed-package/state transport.
#if os(iOS)
import SwiftUI
import WidgetKit
import HanlinScriptExtensions

@available(iOSApplicationExtension 18.0, *)
public struct ScriptWidgetButtonControlWidget: ControlWidget {
    public init() {}
    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: HanlinScriptWidgetControlCatalog.buttonKind,
            provider: ScriptWidgetButtonControlProvider()
        ) { value in
            ControlWidgetButton(action: RunScriptWidgetControlIntent(controlID: value.id)) {
                Label(value.title, systemImage: value.systemImage)
            }
        }
        .displayName("ScriptWidget Button")
        .description("Run an action declared by a ScriptWidget package.")
        .promptsForUserConfiguration()
    }
}

@available(iOSApplicationExtension 18.0, *)
public struct ScriptWidgetControlWidget: ControlWidget {
    public init() {}
    public var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: HanlinScriptWidgetControlCatalog.toggleKind,
            provider: ScriptWidgetToggleControlProvider()
        ) { value in
            ControlWidgetToggle(
                value.title,
                isOn: value.isOn,
                action: SetScriptWidgetControlValueIntent(controlID: value.id)
            ) { isOn in
                Label(isOn ? "On" : "Off", systemImage: value.systemImage)
            }
        }
        .displayName("ScriptWidget Toggle")
        .description("Change state with an action declared by a ScriptWidget package.")
        .promptsForUserConfiguration()
    }
}

#endif
