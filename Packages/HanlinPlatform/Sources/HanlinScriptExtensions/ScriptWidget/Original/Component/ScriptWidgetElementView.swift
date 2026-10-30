//
//  ScriptWidgetElementView.swift
//  ScriptWidget
//
//  Created by everettjf on 2020/10/31.
//

import SwiftUI
import HanlinScriptContracts

// Hanlin adapter: prepared, execution-free context bound to one installed instance.
@MainActor
final class ScriptWidgetElementContext {
    let actionContext: HanlinWidgetActionContext
    let debugMode = false
    let animationDate: Date?
    let package: HanlinScriptWidgetResources
    var canExecuteActions: Bool { !actionContext.actions.isEmpty }
    init(actionContext: HanlinWidgetActionContext, animationDate: Date? = nil) {
        self.actionContext = actionContext
        self.animationDate = animationDate
        package = HanlinScriptWidgetResources(files: actionContext.resources)
    }
    func usesContainerBackground(for element: ScriptWidgetRuntimeElement) -> Bool { false }
    func declaration(for element: ScriptWidgetRuntimeElement) -> HanlinWidgetActionDeclaration? {
        if element.getPropString("action")?.lowercased() == "reload" {
            return actionContext.actions.first { $0.kind == .reload }
        }
        if let actionID = element.getPropString("actionID") {
            return actionContext.actions.first { $0.id == actionID }
        }
        if let function = element.getPropString("onClick"), !function.isEmpty {
            return actionContext.actions.first { $0.handler == function && $0.kind == .function }
        }
        return nil
    }
}

struct ScriptWidgetElementView: View {

    let element: ScriptWidgetRuntimeElement
    let context: ScriptWidgetElementContext

    init(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) {
        self.element = element
        self.context = context
    }

    var body: some View {
        ScriptWidgetElementView.buildView(element: element, context: context)
    }

    static func buildView(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) -> AnyView {
        if let tag = element.tagAsString() {
            print("build tag : \(tag)")

            switch tag {
            case "hstack": return ScriptWidgetElementTagStack.buildViewHStack(element, context)
            case "vstack": return ScriptWidgetElementTagStack.buildViewVStack(element, context)
            case "zstack": return ScriptWidgetElementTagZStack.buildView(element, context)
            case "hgrid": return ScriptWidgetElementTagGrid.buildViewHGrid(element, context)
            case "vgrid": return ScriptWidgetElementTagGrid.buildViewVGrid(element, context)

            case "text": return ScriptWidgetElementTagText.buildView(element, context)
            case "date": return ScriptWidgetElementTagDate.buildView(element, context)
            case "image": return ScriptWidgetElementTagImage.buildView(element, context)

            case "gif": return ScriptWidgetElementTagGif.buildView(element, context)
            case "spacer": return ScriptWidgetElementTagSpacer.buildView(element, context)
            case "rect": return ScriptWidgetElementTagRectangle.buildView(element, context)
            case "capsule": return ScriptWidgetElementTagCapsule.buildView(element, context)
            case "ellipse": return ScriptWidgetElementTagEllipse.buildView(element, context)
            case "circle": return ScriptWidgetElementTagCircle.buildView(element, context)
            case "gauge": return ScriptWidgetElementTagGauge.buildView(element, context)
            case "chart": return ScriptWidgetElementTagChart.buildView(element, context)
            case "link": return ScriptWidgetElementTagLink.buildView(element, context)
            case "divider": return ScriptWidgetElementTagDivider.buildView(element, context)
            case "line": return ScriptWidgetElementTagLine.buildView(element, context)
            case "roundedrect": return ScriptWidgetElementTagRoundedRect.buildView(element, context)
            case "icon": return ScriptWidgetElementTagIcon.buildView(element, context)
            case "label": return ScriptWidgetElementTagLabel.buildView(element, context)
            case "progress": return ScriptWidgetElementTagProgress.buildView(element, context)
            case "ring": return ScriptWidgetElementTagRing.buildView(element, context)
            case "badge": return ScriptWidgetElementTagBadge.buildView(element, context)
            case "chip": return ScriptWidgetElementTagChip.buildView(element, context)
            case "stat": return ScriptWidgetElementTagStat.buildView(element, context)

            case "button": return ScriptWidgetElementTagButton.buildView(element, context)
            case "toggle": return ScriptWidgetElementTagToggle.buildView(element, context)

            default: return Self.unknownStringTagView(element: element, context: context)
            }
        } else {
            print("build tag : unknown type")

            return Self.unknownTypeTagView(element: element, context: context)
        }
    }

    static func unknownTypeTagView(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) -> AnyView {
        // Runtime execution resolves custom components before SwiftUI builds the
        // view tree. Never call JavaScriptCore here because SwiftUI may evaluate
        // this body on a different thread from the owning JSContext.
        return AnyView(Text("UnknownTagType").background(Color.purple))
    }

    static func unknownStringTagView(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) -> AnyView {
        if let tag = element.tagAsString() {
            if tag == "Fragment" {
                return AnyView(Group(content: {
                    ForEach(element.childrenAsElements()) { item -> AnyView in
                        return ScriptWidgetElementView.buildView(element: item, context: context)
                    }
                }))
            }
        }

        return AnyView(Text("UnknownTagName").background(Color.pink))
    }
}
