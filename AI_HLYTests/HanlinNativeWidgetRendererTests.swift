import CryptoKit
@testable import HanlinExpoWidgetSubset
import Foundation
import HanlinExpoWidgetNative
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptExtensions
import HanlinWidgetCompiler
import SwiftUI
import XCTest
import UIKit

/// iPad simulator raster tests of the exact native product linked by the appex.
/// A successful raster is distinct from a SpringBoard action acceptance test.
@MainActor
final class HanlinNativeWidgetRendererTests: XCTestCase {
    func testOriginalTextConcatenationPreservesNativeTypeAndChildStyles() throws {
        let styled: [String: Any] = ["type": "TextView", "props": ["text": " styled", "modifiers": [
            ["$type": "font", "size": 24, "weight": "bold"], ["$type": "foregroundColor", "color": "#0000ff"]]]]
        let child = render(["type": "TextView", "props": ["text": "Base", "children": [styled]]])
        let native = try XCTUnwrap(child.childView as? TextView)
        XCTAssertEqual(native.props.text, "Base")
        XCTAssertEqual(native.props.children?.count, 1)
        XCTAssertTrue(native.props.children?.first?.childView is TextView)
        let expected = Text("Base") + Text(" styled").font(.system(size: 24, weight: .bold)).foregroundColor(Color(red: 0, green: 0, blue: 1))
        XCTAssertEqual(try raster(AnyView(child)), try raster(AnyView(expected)), "Native Text concatenation lost source styles")
    }

    func testOriginalSlotsMatchNativeOverlayBackgroundAndMaskPixels() throws {
        let circle: [String: Any] = ["type": "CircleView", "props": ["modifiers": [
            ["$type": "frame", "width": 12, "height": 12], ["$type": "foregroundColor", "color": "#0000ff"]]]]
        let base: [String: Any] = ["type": "TextView", "props": ["text": "Native slots"]]
        let slot: [String: Any] = ["type": "SlotView", "props": ["name": "content", "children": [circle]]]
        for type in ["OverlayView", "BackgroundView", "MaskView"] {
            let child = render(["type": type, "props": ["alignment": "topTrailing", "children": [base, slot]]])
            let props: ExpoSwiftUI.ViewProps
            let reference: AnyView
            let shape = Circle().frame(width: 12, height: 12).foregroundColor(Color(red: 0, green: 0, blue: 1))
            switch type {
            case "OverlayView":
                props = try XCTUnwrap(child.childView as? UIBaseView<OverlayViewProps, OverlayView>).props
                reference = AnyView(Text("Native slots").overlay(alignment: .topTrailing) { shape })
            case "BackgroundView":
                props = try XCTUnwrap(child.childView as? UIBaseView<BackgroundViewProps, BackgroundView>).props
                reference = AnyView(Text("Native slots").background(alignment: .topTrailing) { shape })
            default:
                props = try XCTUnwrap(child.childView as? UIBaseView<MaskViewProps, MaskView>).props
                reference = AnyView(Text("Native slots").mask(alignment: .topTrailing) { shape })
            }
            XCTAssertEqual(props.children?.withoutSlots().count, 1)
            XCTAssertEqual(props.children?.slot("content")?.props.name, "content")
            XCTAssertEqual(try raster(AnyView(child)), try raster(reference), "\(type) lost its native slot projection")
        }
    }

    func testOriginalChartAndGaugeReceiveTheirTypedNativeData() throws {
        let chart = render(["type": "ChartView", "props": ["type": "bar", "data": [["x": "A", "y": 3], ["x": "B", "y": 7]]]])
        let nativeChart = try XCTUnwrap(chart.childView as? UIBaseView<ChartProps, ChartView>)
        XCTAssertEqual(nativeChart.props.data.map(\.xValue), ["A", "B"])
        XCTAssertEqual(nativeChart.props.data.map(\.y), [3, 7])
        XCTAssertEqual(nativeChart.props.type, .bar)
        let gauge = render(["type": "GaugeView", "props": ["value": 0.7, "min": 0, "max": 1, "children": [
            ["type": "SlotView", "props": ["name": "currentValue", "children": [["type": "TextView", "props": ["text": "70%"]]]]]]]])
        let nativeGauge = try XCTUnwrap(gauge.childView as? UIBaseView<GaugeProps, GaugeView>)
        XCTAssertEqual(nativeGauge.props.value, 0.7)
        XCTAssertEqual(nativeGauge.props.min, 0)
        XCTAssertEqual(nativeGauge.props.max, 1)
        XCTAssertEqual(nativeGauge.props.children?.slot("currentValue")?.props.name, "currentValue")
        let frozen = render(["type": "GaugeView", "props": ["value": Int64(1), "min": Int64(0), "max": Int64(3)]])
        XCTAssertEqual((frozen.childView as? UIBaseView<GaugeProps, GaugeView>)?.props.max, 3)
        XCTAssertThrowsError(try Color.convert(from: Double.nan, appContext: AppContext()))
        XCTAssertThrowsError(try Color.convert(from: -1, appContext: AppContext()))
    }

    private func render(_ node: [String: Any]) -> any ExpoSwiftUI.AnyChild {
        HanlinExpoWidgetNative.render(node: node) { _, _, label in AnyView(label) }
    }

    func testInstalledExternalSourceRendersThroughAnyChild() throws {
      for archive in ["Hanlin-Expo-Widget-Counter.hanlinExpo", "Hanlin-Expo-Widget-Visuals.hanlinExpo"] {
        let bundle = Bundle(for: Self.self)
        let fixtures = try XCTUnwrap(bundle.url(forResource: "WidgetEngineFixtures", withExtension: "bundle", subdirectory: "Fixtures") ?? bundle.url(forResource: "WidgetEngineFixtures", withExtension: "bundle"))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = try HanlinPackageCenter().stageAndInspect(sourceURL: fixtures.appending(path: archive), stagingParent: root)
        let entry = try XCTUnwrap(staged.manifest.entry)
        var files: [String: Data] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: staged.packageRoot, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let file as URL in enumerator where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files[String(file.path.dropFirst(staged.packageRoot.path.count + 1))] = try Data(contentsOf: file)
        }
        let program = try HanlinWidgetCompiler.prepare(manifest: staged.manifest, entryPath: entry, files: files)
        let node = try HanlinExpoWidgetsRuntime.shared.render(layout: program.javaScript, props: [:], environment: ["widgetFamily": "systemMedium"]).get()
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.native-raster"), packageID: try .init(validating: "package.native-raster"), generation: 1, entrypointID: "widget")
        let context = HanlinWidgetActionContext(identity: identity, engine: .expo, artifactSHA256: String(repeating: "a", count: 64), family: "systemMedium", actions: program.actions)
        var commands: [HanlinWidgetActionCommand] = []
        let child: any ExpoSwiftUI.AnyChild = HanlinExpoWidgetNative.render(node: node) { target, role, label in
            do {
                let intent = try HanlinExpoWidgetsViewRenderer.actionIntent(target: target, context: context)
                commands.append(try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(intent.commandJSON.utf8)))
                return AnyView(Button(role: role, intent: intent) { label })
            } catch { XCTFail("Native renderer emitted an undeclared action: \(error)"); return AnyView(Text("Invalid action")) }
        }
        let png = try raster(AnyView(child))
        let diagnostic = try raster(AnyView(Text("Unsupported Expo widget view")))
        XCTAssertNotEqual(png, diagnostic)
        XCTAssertFalse(commands.isEmpty)
        XCTAssertTrue(commands.allSatisfy { $0.context.engine == .expo && $0.context.identity == identity })
        XCTAssertEqual(Set(commands.map(\.actionID)), Set(program.actions.map(\.id)))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(archive)-native.png"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }

    private func raster(_ view: AnyView) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: 360, height: 320).environment(\.colorScheme, .light))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }
}
