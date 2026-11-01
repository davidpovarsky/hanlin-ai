import CryptoKit
@testable import AI_Hanlin
@testable import HanlinExpoWidgetSubset
import Foundation
import HanlinExpoWidgetNative
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptExtensions
import HanlinScriptUI
import HanlinWidgetCompiler
import SwiftUI
import XCTest
import UIKit

/// iPad simulator raster tests of the exact native product linked by the appex.
/// A successful raster is distinct from a SpringBoard action acceptance test.
@MainActor
final class HanlinNativeWidgetRendererTests: XCTestCase {
    func testExpoRawTaggedAndDateWireSurvivePublicationAndSourceAction() throws {
        let bundle = Bundle(for: Self.self)
        let fixtures = try XCTUnwrap(bundle.url(forResource: "WidgetEngineFixtures", withExtension: "bundle", subdirectory: "Fixtures") ?? bundle.url(forResource: "WidgetEngineFixtures", withExtension: "bundle"))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = try HanlinPackageCenter().stageAndInspect(sourceURL: fixtures.appending(path: "Hanlin-Expo-Widget-Counter.hanlinExpo"), stagingParent: root)
        var files: [String: Data] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: staged.packageRoot, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let file as URL in enumerator where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files[String(file.path.dropFirst(staged.packageRoot.path.count + 1))] = try Data(contentsOf: file)
        }
        let program = try HanlinWidgetCompiler.prepare(manifest: staged.manifest, entryPath: XCTUnwrap(staged.manifest.entry), files: files)
        let wire: [String: Any] = ["flag": true, "count": 7, "ratio": 0.25, "nil": NSNull(), "array": ["אבג", 3, false]]
        let rawNode = try ExpoHostServicesAdapter.parseUntaggedNode(["kind": "text", "properties": ["wire": wire], "children": []])
        let taggedNode = try JSONDecoder().decode(HanlinScriptUINode.self, from: JSONEncoder().encode(rawNode))
        XCTAssertEqual(taggedNode, rawNode)
        let expectedWire = try ExpoHostServicesAdapter.toHanlinValue(wire)
        XCTAssertEqual(rawNode.properties["wire"], expectedWire)
        let date = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + 3_600.125)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let inputs: [[String: Any]] = [["validUntil": iso.string(from: date)], ["validUntilEpochMilliseconds": date.timeIntervalSince1970 * 1_000]]
        for (index, input) in inputs.enumerated() {
            let parsedDate = try XCTUnwrap(ExpoHostServicesAdapter.parseValidUntil(from: input))
            XCTAssertEqual(parsedDate.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
            let storeRoot = root.appending(path: "wire-\(index)")
            let store = HanlinScriptExtensions.HanlinScriptExtensionStore(root: storeRoot)
            let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.wire"), packageID: try .init(validating: "package.wire"), generation: 1, entrypointID: "widget")
            let artifact = try store.storeArtifact(data: JSONEncoder().encode(program), installedPackageID: identity.installedPackageID, generation: 1)
            let widget = HanlinScriptWidgetSnapshot(identity: identity, displayName: "Wire roundtrip", validUntil: parsedDate, engine: .expo,
                payload: .expo(.init(layout: "", props: ["wire": expectedWire], layoutRef: artifact.ref, layoutSHA256: artifact.sha256)), root: index == 0 ? rawNode : taggedNode)
            try store.publishWidgetTemplates([widget], intentEntities: [], translationApps: [], installedPackageIDs: [identity.installedPackageID])
            let reopened = HanlinScriptExtensions.HanlinScriptExtensionStore(root: storeRoot)
            let committed = try XCTUnwrap(reopened.load()?.widgets.first)
            XCTAssertEqual(committed.root, rawNode)
            XCTAssertEqual(committed.validUntil.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
            let context = HanlinWidgetActionContext(identity: identity, engine: .expo, artifactSHA256: artifact.sha256, family: "systemMedium", actions: program.actions)
            let command = HanlinWidgetActionCommand(context: context, actionID: "increment")
            let decodedCommand = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: JSONEncoder().encode(command))
            _ = try HanlinWidgetActionExecutor.perform(decodedCommand, store: reopened)
            let state = try XCTUnwrap(reopened.load()?.widgetStates.first)
            XCTAssertEqual(state.values["wire"], expectedWire)
            XCTAssertEqual(state.values["count"], .integer(8))
        }
    }

    func testOriginalShapesStacksImagesLinksAndModifiersMatchNativeReferences() throws {
        let blue = Color(red: 0, green: 0, blue: 1)
        let modifiers: [[String: Any]] = [["$type": "foregroundColor", "color": "#0000ff"], ["$type": "frame", "width": 64, "height": 40]]
        func node(_ type: String, _ props: [String: Any] = [:]) -> [String: Any] { ["type": type, "props": props] }
        let a = node("TextView", ["text": "אבג Native"])
        let b = node("TextView", ["text": "Second"])
        let destination = try XCTUnwrap(URL(string: "https://example.com/widget"))
        var cases: [(String, [String: Any], AnyView)] = [
            ("rectangle", node("RectangleView", ["modifiers": modifiers]), AnyView(Rectangle().foregroundColor(blue).frame(width: 64, height: 40))),
            ("roundedrectangle", node("RoundedRectangleView", ["cornerRadius": 13, "modifiers": modifiers]), AnyView(RoundedRectangle(cornerRadius: 13).foregroundColor(blue).frame(width: 64, height: 40))),
            ("capsule", node("CapsuleView", ["cornerStyle": "circular", "modifiers": modifiers]), AnyView(Capsule(style: .circular).foregroundColor(blue).frame(width: 64, height: 40))),
            ("circle", node("CircleView", ["modifiers": modifiers]), AnyView(Circle().foregroundColor(blue).frame(width: 64, height: 40))),
            ("ellipse", node("EllipseView", ["modifiers": modifiers]), AnyView(Ellipse().foregroundColor(blue).frame(width: 64, height: 40))),
            ("hstack", node("HStackView", ["alignment": "bottom", "spacing": 23, "children": [a, [b]]]), AnyView(HStack(alignment: .bottom, spacing: 23) { Text("אבג Native"); Text("Second") })),
            ("vstack", node("VStackView", ["alignment": "trailing", "spacing": 19, "children": [a, b]]), AnyView(VStack(alignment: .trailing, spacing: 19) { Text("אבג Native"); Text("Second") })),
            ("zstack", node("ZStackView", ["alignment": "topLeading", "children": [a, b]]), AnyView(ZStack(alignment: .topLeading) { Text("אבג Native"); Text("Second") })),
            ("spacer", node("HStackView", ["spacing": 0, "children": [a, node("SpacerView", ["minLength": 37]), b]]), AnyView(HStack(spacing: 0) { Text("אבג Native"); Spacer(minLength: 37); Text("Second") })),
            ("divider", node("DividerView"), AnyView(Divider())),
            ("symbol", node("ImageView", ["systemName": "star.fill"]), AnyView(Image(systemName: "star.fill", variableValue: nil))),
            ("link-label", node("LinkView", ["label": "Native link", "destination": "https://example.com/widget"]), AnyView(Link("Native link", destination: destination))),
            ("link-children", node("LinkView", ["destination": "https://example.com/widget", "children": [a]]), AnyView(Link(destination: destination) { Text("אבג Native") })),
            ("button-label", node("Button", ["label": "Run source", "systemImage": "play.fill", "target": "run", "role": "destructive"]), AnyView(Label(title: { Text("Run source") }, icon: { Image(systemName: "play.fill") }))),
            ("button-children", node("Button", ["target": "run", "children": [a]]), AnyView(Text("אבג Native")))
        ]
        let styled = node("HStackView", ["children": [a], "modifiers": [
            ["$type": "padding", "horizontal": 9, "top": 3], ["$type": "opacity", "value": 0.65],
            ["$type": "offset", "x": 5, "y": 7], ["$type": "rotationEffect", "angle": 12],
            ["$type": "scaleEffect", "x": 0.8, "y": 1.1]]])
        cases.append(("ordered-modifiers", styled, AnyView(HStack { Text("אבג Native") }.padding(EdgeInsets(top: 3, leading: 9, bottom: 0, trailing: 9)).opacity(0.65).offset(x: 5, y: 7).rotationEffect(.degrees(12)).scaleEffect(x: 0.8, y: 1.1))))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12)).image { context in
            UIColor.red.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
        let file = root.appending(path: "verified.png")
        let imageBytes = try XCTUnwrap(image.pngData())
        try imageBytes.write(to: file)
        let decodedImage = try XCTUnwrap(UIImage(data: imageBytes))
        cases.append(("verified-asset", node("ImageView", ["assetName": "verified.png"]), AnyView(Image(uiImage: decodedImage))))
        for (name, input, reference) in cases {
            var targets: [String] = []
            let child = HanlinExpoWidgetNative.render(node: input, resources: ["verified.png": file]) { target, role, label in
                targets.append(target)
                if name == "button-label" { XCTAssertEqual(role, .destructive) }
                return label
            }
            if name.hasPrefix("button-") { XCTAssertEqual(targets, ["run"]) }
            for rtl in [false, true] {
                let native = AnyView(AnyView(child).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight).dynamicTypeSize(rtl ? .accessibility3 : .large))
                let expected = AnyView(reference.environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight).dynamicTypeSize(rtl ? .accessibility3 : .large))
                let png = try raster(native)
                XCTAssertEqual(png, try raster(expected), "Original \(name) differs from native SwiftUI; RTL/accessibility=\(rtl)")
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "expo-\(name)-rtl-\(rtl).png"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        // Resource access and unsupported modifiers fail visibly before native
        // ImageView can read an unverified file or silently drop a gesture.
        XCTAssertThrowsError(try ImageViewProps(rawProps: ["uiImage": "file:///etc/hosts"], context: AppContext()))
        XCTAssertThrowsError(try HStackViewProps(rawProps: ["modifiers": [["$type": "unregisteredModifier"]]], context: AppContext()))
    }

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

    func testOriginalLabelAndProgressKeepTheirPreparedChildren() throws {
        let text: [String: Any] = ["type": "TextView", "props": ["text": "Native label"]]
        let slot: [String: Any] = ["type": "SlotView", "props": ["name": "title", "children": [text]]]
        let label = render(["type": "LabelView", "props": ["children": [slot]]])
        let nativeLabel = try XCTUnwrap(label.childView as? UIBaseView<LabelViewProps, LabelView>)
        XCTAssertEqual(nativeLabel.props.children?.slot("title")?.props.children?.count, 1)
        XCTAssertEqual(try raster(AnyView(label)), try raster(AnyView(Text("Native label"))))
        let progress = render(["type": "ProgressView", "props": ["value": 0.7, "children": [text]]])
        let nativeProgress = try XCTUnwrap(progress.childView as? UIBaseView<ProgressViewProps, HanlinExpoWidgetSubset.ProgressView>)
        XCTAssertEqual(nativeProgress.props.children?.count, 1)
        XCTAssertEqual(try raster(AnyView(progress)), try raster(AnyView(SwiftUI.ProgressView(value: 0.7) { Text("Native label") })))
        let invalid = render(["type": "GaugeView", "props": ["min": 2, "max": 1]])
        XCTAssertEqual(try raster(AnyView(invalid)), try raster(AnyView(Text("Invalid gauge range"))))
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
