import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
@testable import HanlinScriptExtensions
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Real SwiftUI raster output from the original source builders. These tests
/// deliberately do not claim SpringBoard placement or native AppIntent tapping.
@MainActor
@Suite("Original ScriptWidget native rendering")
struct HanlinOriginalScriptWidgetRenderingTests {
    @Test(arguments: ["hstack", "vstack", "zstack", "hgrid", "vgrid", "text", "date", "image", "gif", "spacer", "rect", "capsule", "ellipse", "circle", "gauge", "chart", "link", "divider", "line", "roundedrect", "icon", "label", "progress", "ring", "badge", "chip", "stat", "button", "toggle"])
    func originalTagProducesDistinctNativeRaster(tag: String) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hanlin-original-raster-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gifURL = root.appending(path: "poster.gif")
        try #require(Data(base64Encoded: "R0lGODlhAQABAIAAABJtxP///yH5BAAAAAAALAAAAAABAAEAAAIBRAA7")).write(to: gifURL)
        let context = try context(resources: ["poster.gif": gifURL])
        var props: [AnyHashable: Any] = [
            "columns": #"[{"type":"fixed","value":"60"},{"type":"flexible"}]"#,
            "color": "#126dc4", "value": "0.7", "total": "1", "type": tag == "gauge" ? "system" : "bar",
            "style": tag == "date" ? "date" : "linear", "date": 1_793_361_600_000.0,
            "data": #"[{"label":"A","value":3},{"label":"B","value":7}]"#,
            "systemName": "star.fill", "file": "poster.gif", "url": "https://example.com", "text": "Native \(tag)",
            "title": "Native \(tag)", "subtitle": "Original source", "on": true
        ]
        if tag == "gif" { props["frame"] = "40" }
        let text = ScriptWidgetRuntimeElement(tagString: "text", props: ["font": "caption"], children: ["Native \(tag)"])
        let element = ScriptWidgetRuntimeElement(tagString: tag, props: props, children: [text, "Native \(tag)"])
        ScriptWidgetRenderClock.fixedNow = Date(timeIntervalSince1970: 1_793_361_600)
        defer { ScriptWidgetRenderClock.fixedNow = nil }
        let png = try raster(element: element, context: context)
        let unknown = try raster(element: .init(tagString: "not-a-widget-tag", props: nil, children: nil), context: context)
        #expect(png != unknown, "\(tag) fell through to the original UnknownTagName view")
        #expect(png.count > 32)
        try save(png, name: "scriptwidget-\(tag).png")
        if tag == "gif" {
            let sequence = try #require(ScriptWidgetGifPipeline.sequence(at: gifURL, animated: false))
            #expect(sequence.frames.count == 1)
            let blank = try raster(element: .init(tagString: "spacer", props: nil, children: nil), context: context)
            #expect(png != blank, "The GIF resource rendered no visible pixels")
        }
    }

    @Test(arguments: ["bar", "bar-x", "bar-y", "bar-gantt", "line", "point", "line-point", "area", "rect", "rule-x"])
    func originalChartVariantUsesItsNativeDataSchema(type: String) throws {
        let data: String
        switch type {
        case "bar-gantt": data = #"[{"job":"A","start":1,"end":4},{"job":"B","start":2,"end":7}]"#
        case "rule-x": data = #"[{"xstart":1,"xend":4,"y":3},{"xstart":2,"xend":7,"y":6}]"#
        default: data = #"[{"label":"A","value":3},{"label":"B","value":7}]"#
        }
        let context = try context()
        let valid = ScriptWidgetRuntimeElement(tagString: "chart", props: ["type": type, "data": data], children: [])
        let invalid = ScriptWidgetRuntimeElement(tagString: "chart", props: ["type": type, "data": "invalid json"], children: [])
        let png = try raster(element: valid, context: context)
        let invalidPNG = try raster(element: invalid, context: context)
        #expect(png != invalidPNG, "\(type) rendered the invalid-data error")
        try save(png, name: "scriptwidget-chart-\(type).png")
    }

    @Test func gridColumnsDateAndNativeElementSemantics() throws {
        let grid = ScriptWidgetRuntimeElement(tagString: "vgrid", props: ["columns": #"[{"type":"fixed","value":"70"},{"type":"flexible"}]"#], children: [])
        let columns = ScriptWidgetElementTagGrid.getColumnsOrRows(grid)
        #expect(columns.count == 2)
        guard case .fixed(70) = columns[0].size else { Issue.record("Original fixed grid column was lost"); return }
        let now = Date(timeIntervalSince1970: 1_793_361_600)
        #expect(ScriptWidgetElementTagDate.getDate(dateName: "tomorrow", now: now) == now.addingTimeInterval(86_400))
        let first = ScriptWidgetRuntimeElement(tagString: "text", props: ["flag": true, "size": "24"], children: ["First"])
        let second = ScriptWidgetRuntimeElement(tagString: "text", props: nil, children: ["Second"])
        let parent = ScriptWidgetRuntimeElement(tagString: "vstack", props: nil, children: [[first], second])
        #expect(parent.childrenAsElements().map(\.id) == [first.id, second.id])
        #expect(first.getPropBool("flag") == true)
        #expect(first.getPropDouble("size") == 24)
    }

    @Test(arguments: ["hstack", "vstack", "zstack", "hgrid", "vgrid", "text", "date", "image", "gif", "spacer", "rect", "capsule", "ellipse", "circle", "gauge", "chart", "link", "divider", "line", "roundedrect", "icon", "label", "progress", "ring", "badge", "chip", "stat", "button", "toggle"])
    func originalTagRespondsToItsSemanticInput(tag: String) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "hanlin-semantic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var resources: [String: URL] = [:]
        for (name, color) in [("red", Color.red), ("blue", Color.blue)] {
            let image = ImageRenderer(content: color.frame(width: 16, height: 16))
            let cg = try #require(image.cgImage)
            #if os(macOS)
            let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            #else
            let png = try #require(UIImage(cgImage: cg).pngData())
            #endif
            let file = root.appending(path: "\(name).png")
            try png.write(to: file)
            resources["\(name).png"] = file
            var gif = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAABJtxP///yH5BAAAAAAALAAAAAABAAEAAAIBRAA7"))
            gif.replaceSubrange(13..<16, with: name == "red" ? [255, 0, 0] : [0, 0, 255])
            let gifFile = root.appending(path: "\(name).gif")
            try gif.write(to: gifFile)
            resources["\(name).gif"] = gifFile
        }
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.semantic"), packageID: try .init(validating: "package.semantic"), generation: 1, entrypointID: "widget")
        let actions: [HanlinWidgetActionDeclaration] = [.init(id: "run", kind: .function, handler: "run"), .init(id: "flag", kind: .setValue, stateKey: "flag")]
        let context = ScriptWidgetElementContext(actionContext: .init(identity: identity, engine: .scriptwidget,
            artifactSHA256: String(repeating: "a", count: 64), family: "systemMedium", actions: actions, resources: resources))
        let first = try raster(element: frozenElement(semanticElement(tag: tag, alternate: false)).nativeElement(), context: context)
        let second = try raster(element: frozenElement(semanticElement(tag: tag, alternate: true)).nativeElement(), context: context)
        #expect(first != second, "\(tag) ignored its source-defined content/layout/value/resource/control input")
        try save(first, name: "semantic-\(tag)-a.png")
        try save(second, name: "semantic-\(tag)-b.png")
    }

    @Test func frozenIntegerPropsPreserveOriginalJSCNumberSemantics() throws {
        // Canonical JSON retains distinct UTF-8 keys; Foundation dictionaries
        // merge canonically equivalent Unicode spellings without trapping.
        let object = try HanlinObject<HanlinValue>(uniqueMembers: [("e\u{301}", .integer(1)), ("\u{e9}", .integer(2))])
        let node = HanlinScriptWidgetPreparedNode(tag: "line", props: ["length": .integer(40), "clip": .integer(2), "on": .bool(true), "date": .integer(1_793_361_600_000)], children: [.value(.integer(17)), .value(.object(object))])
        let native = node.nativeElement()
        #expect(native.getPropDouble("length") == 40)
        #expect(native.getPropInt("clip") == 2)
        #expect(native.getPropBool("on") == true)
        #expect(native.getPropDouble("date") == 1_793_361_600_000)
        #expect((native.getChildren().first as? NSNumber)?.intValue == 17)
        let nativeObject = try #require(native.getChildren().last as? [String: Any])
        #expect(nativeObject.count == 1)
        #expect((nativeObject["\u{e9}"] as? NSNumber)?.intValue == 2)
    }

    private func frozenElement(_ element: ScriptWidgetRuntimeElement) throws -> HanlinScriptWidgetPreparedNode {
        let tag = try #require(element.tagAsString())
        let props = try Dictionary(uniqueKeysWithValues: element.getProps().map { key, value in
            (String(describing: key), try HanlinWidgetJSON.value(value))
        })
        let children = try element.getChildren().map { child -> HanlinScriptWidgetPreparedNode.Child in
            if let child = child as? ScriptWidgetRuntimeElement { return .element(try frozenElement(child)) }
            return .value(try HanlinWidgetJSON.value(child))
        }
        return .init(tag: tag, props: props, children: children)
    }

    private func semanticElement(tag: String, alternate: Bool) -> ScriptWidgetRuntimeElement {
        func text(_ value: String) -> ScriptWidgetRuntimeElement { .init(tagString: "text", props: nil, children: [value]) }
        func cell(_ color: String) -> ScriptWidgetRuntimeElement { .init(tagString: "rect", props: ["color": color, "frame": "30,30"], children: []) }
        var props: [AnyHashable: Any] = [:]
        var children: [Any] = [text(alternate ? "Changed source label" : "Native source label")]
        switch tag {
        case "hstack", "vstack":
            props["spacing"] = alternate ? 40 : 0
            children = [cell("red"), cell("blue")]
        case "zstack":
            // The original ZStack is centered; its contract is child draw order.
            children = alternate ? [cell("red"), cell("blue")] : [cell("blue"), cell("red")]
        case "hgrid", "vgrid":
            props["columns"] = alternate ? #"[{"type":"fixed","value":"35"},{"type":"fixed","value":"35"}]"# : #"[{"type":"fixed","value":"35"}]"#
            children = [cell("red"), cell("blue"), cell("green"), cell("orange")]
        case "text": children = [alternate ? "Changed source label" : "Native source label"]
        case "link", "button":
            props["url"] = "https://example.com/native"
            props["actionID"] = "run"
        case "date":
            props["date"] = alternate ? 1_793_448_000_000.0 : 1_793_361_600_000.0
            props["style"] = "date"
        case "image":
            props["name"] = alternate ? "blue.png" : "red.png"
            props["frame"] = "40,40"
        case "gif":
            props["file"] = alternate ? "blue.gif" : "red.gif"
            props["frame"] = "40,40"
        case "spacer":
            let spacer = ScriptWidgetRuntimeElement(tagString: "spacer", props: ["frame": alternate ? "80,20" : "10,20"], children: [])
            return .init(tagString: "hstack", props: ["spacing": 0], children: [cell("red"), spacer, cell("blue")])
        case "rect", "capsule", "ellipse", "circle", "roundedrect":
            props["color"] = alternate ? "blue" : "red"
            props["frame"] = "60,40"
        case "gauge":
            props["type"] = "system"; props["style"] = "linear"
            props["value"] = alternate ? "0.8" : "0.2"
            children = []
        case "chart":
            props["type"] = "bar"
            props["data"] = alternate ? #"[{"label":"A","value":2},{"label":"B","value":8},{"label":"C","value":10}]"# : #"[{"label":"A","value":2},{"label":"B","value":4},{"label":"C","value":10}]"#
        case "divider":
            props["axis"] = alternate ? "vertical" : "horizontal"
            props["color"] = "red"; props["thickness"] = 4
        case "line":
            props["length"] = alternate ? 100 : 30
            props["color"] = "red"; props["thickness"] = 4
        case "icon": props["systemName"] = alternate ? "heart.fill" : "star.fill"
        case "label": props["title"] = alternate ? "Second label" : "First label"; props["systemName"] = "star.fill"
        case "progress", "ring": props["value"] = alternate ? 0.8 : 0.2; props["total"] = 1
        case "badge", "chip": props["text"] = alternate ? "Second" : "First"
        case "stat": props["value"] = alternate ? "28" : "17"; props["title"] = "Metric"
        case "toggle":
            props["actionID"] = "flag"; props["stateKey"] = "flag"; props["on"] = alternate
            children = [text("Backup")]
        default: Issue.record("Missing semantic input case: \(tag)")
        }
        return .init(tagString: tag, props: props, children: children)
    }

    private func context(resources: [String: URL] = [:]) throws -> ScriptWidgetElementContext {
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.native-render"), packageID: try .init(validating: "package.native-render"), generation: 1, entrypointID: "widget")
        return .init(actionContext: .init(identity: identity, engine: .scriptwidget, artifactSHA256: String(repeating: "a", count: 64), family: "systemMedium", resources: resources), animationDate: Date(timeIntervalSince1970: 1_793_361_600))
    }

    private func raster(element: ScriptWidgetRuntimeElement, context: ScriptWidgetElementContext) throws -> Data {
        let renderer = ImageRenderer(content: ScriptWidgetElementView(element: element, context: context)
            .frame(width: 220, height: 160).environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US")).environment(\.dynamicTypeSize, .large))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 220 && image.height == 160)
        #if os(macOS)
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        #else
        return try #require(UIImage(cgImage: image).pngData())
        #endif
    }

    private func save(_ data: Data, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"] else { return }
        let root = URL(filePath: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appending(path: name))
    }
}
