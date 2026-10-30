import CryptoKit
import Foundation
import HanlinPlatformContracts
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
        try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")).write(to: gifURL)
        let context = try context(resources: ["poster.gif": gifURL])
        let props: [AnyHashable: Any] = [
            "columns": #"[{"type":"fixed","value":"60"},{"type":"flexible"}]"#,
            "color": "#126dc4", "value": "0.7", "total": "1", "type": tag == "gauge" ? "system" : "bar",
            "style": tag == "date" ? "date" : "linear", "date": 1_793_361_600_000.0,
            "data": #"[{"label":"A","value":3},{"label":"B","value":7}]"#,
            "systemName": "star.fill", "file": "poster.gif", "url": "https://example.com", "text": "Native \(tag)",
            "title": "Native \(tag)", "subtitle": "Original source", "on": true
        ]
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
