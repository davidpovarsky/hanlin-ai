//
//  ScriptWidgetElementTagToggle.swift
//  ScriptWidget
//
//  Created by zhufeng on 2023/10/8.
//

import Foundation
import SwiftUI
import SwiftyJSON

@MainActor
class ScriptWidgetElementTagToggle {

    static func buildView(_ element: ScriptWidgetRuntimeElement, _ context: ScriptWidgetElementContext) -> AnyView {
        return AnyView(Self.buildToggle(
            element: element,
            context: context
        ))
    }

    @ViewBuilder private static func buildToggle(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) -> some View {
        let on = self.getToggleValue(element)
        if let declaration = context.declaration(for: element),
           (element.getPropString("stateKey") == declaration.stateKey || declaration.kind == .function),
           let intent = try? HanlinSetWidgetValueIntent(command: .init(context: context.actionContext, actionID: declaration.id), value: !on) {
            Toggle(isOn: on, intent: intent) { toggleLabel(element: element, context: context) }
                .modifier(ScriptWidgetAttributeGeneralModifier(element, context))
        } else {
            Toggle(isOn: .constant(on)) { toggleLabel(element: element, context: context) }
                .disabled(true)
                .modifier(ScriptWidgetAttributeGeneralModifier(element, context))
        }
    }

    @ViewBuilder private static func toggleLabel(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) -> some View {
        ForEach(element.childrenAsElements()) { item -> AnyView in
            ScriptWidgetElementView.buildView(element: item, context: context)
        }
    }

    static func getToggleActionFunctionName(_ element: ScriptWidgetRuntimeElement) -> String {
        guard let functionName = element.getPropString("onClick") else { return "" }
        return functionName
    }

    static func getToggleValue(_ element: ScriptWidgetRuntimeElement) -> Bool {
        return element.getPropBool("on") ?? false
    }

}
