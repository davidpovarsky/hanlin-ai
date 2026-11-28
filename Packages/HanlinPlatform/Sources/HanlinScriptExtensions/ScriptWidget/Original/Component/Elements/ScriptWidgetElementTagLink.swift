//
//  ScriptWidgetElementTagLink.swift
//  ScriptWidget
//
//  Created by everettjf on 2021/4/12.
//

import SwiftUI


@MainActor
struct ScriptWidgetElementTagLink {

    static func buildView(_ element: ScriptWidgetRuntimeElement, _ context: ScriptWidgetElementContext) -> AnyView {

        return AnyView(ScriptWidgetElementTagLink.buildVStack(
            element: element,
            context: context
        ))
    }

    @ViewBuilder static func buildVStack(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) -> some View {
        if let destination = ScriptWidgetElementTagLink.getDestination("url", element) {
        Link(destination: destination) {
            ForEach(element.childrenAsElements()) { item -> AnyView in
                return ScriptWidgetElementView.buildView(element: item, context: context)
            }
        }
        .buttonStyle(.plain)
        .modifier(ScriptWidgetAttributeGeneralModifier(element, context))
        } else {
            Text("Invalid widget link")
        }
    }

    static func getDestination(_ attrName: String, _ element: ScriptWidgetRuntimeElement) -> URL? {

        guard let urlString = element.getPropString(attrName) else {
            return nil
        }

        guard let url = URL(string: urlString), url.scheme != nil else {
            return nil
        }

        return url
    }

}
struct ScriptWidgetElementTagLinkSample: View {
    var body: some View {
        VStack {
            Link(destination: URL(string: "widget-deeplink://standingsAAA")!) {
                Text("Link Test1")
                Text("Link Test2")
            }
            Link(destination: URL(string: "widget-deeplink://standingsBBB")!) {
                VStack {
                    Text("Link Test3")
                    Text("Link Test4")
                }
            }
            Link("Hello", destination: URL(string: "widget-deeplink://standingsBBB")!)
        }
    }
}

struct ScriptWidgetElementTagLinkSample_Previews: PreviewProvider {
    static var previews: some View {
        ScriptWidgetElementTagLinkSample()
    }
}
