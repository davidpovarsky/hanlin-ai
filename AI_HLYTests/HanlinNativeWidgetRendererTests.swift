import CryptoKit
@testable import AI_Hanlin
@testable import HanlinExpoWidgetSubset
import Foundation
import HanlinExpoWidgetNative
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
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
    func testDeclaredWidgetHostActionsCompileAndKeepOriginalLocalActions() throws {
        // Author plain JSON independently of the Swift Codable models. The
        // ordinary {type,value} object must remain application data.
        let parameters: [String: Any] = ["text": "שלום🙂", "flag": true, "none": NSNull(),
            "values": [1, 0.25, false], "ordinary": ["type": "object", "value": ["type": "number", "value": 7]]]
        let hostAction: [String: Any] = ["id": "host-run", "kind": "hostAction", "hostAction": [
            "entrypointID": "run-intent", "actionName": "run.all", "parameters": parameters]]
        let metadata: [String: Any] = ["abiVersion": 1, "sourceFormat": "expo-layout",
            "families": ["systemMedium"], "actions": [hostAction, ["id": "local-run", "kind": "expoCallback"]]]
        let declaration: [String: Any] = ["id": "run-intent", "kind": "appIntent", "sourcePath": "bundle.js", "exportedSymbol": "run.all"]
        var manifest: [String: Any] = ["name": "Widget Host target", "version": "1.0.0", "entry": "bundle.js",
            "hanlinRuntime": "hanlin-expo", "widgetEngine": "expo", "hanlinWidget": metadata,
            "entrypoints": [declaration], "actions": [["id": "run.all", "handler": "bundle.js"]]]
        let expoUIVersion = HanlinMiniAppHostVersions.expoUIVersion
        let files: [String: Data] = ["bundle.js": Data("console.log('declared handler source');".utf8),
            "other.js": Data("console.log('unrelated source');".utf8),
            "package.json": Data(#"{"name":"host-target","main":"bundle.js","hanlinRuntime":"hanlin-expo","hanlinExpo":{"runtimeVersion":"\#(expoUIVersion)","plugins":{"@expo/ui":"\#(expoUIVersion)"}}}"#.utf8),
            "widget.json": Data(#"(props) => ({type:'Button',props:{target:'host-run',label:'Continue in app'}})"#.utf8)]
        let analyzer = HanlinScriptAnalyzer(inventory: .init(baselineID: "widget-host-target",
            baselineDigest: String(repeating: "a", count: 64), symbols: []))
        func preview(_ object: [String: Any]) throws -> HanlinImportPreview {
            let root = FileManager.default.temporaryDirectory.appending(path: "widget-host-target-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let manifestData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try manifestData.write(to: root.appending(path: "script.json"))
            for (name, data) in files { try data.write(to: root.appending(path: name)) }
            let staged = HanlinStagedPackage(source: .init(originalFileName: "fixture.hanlinExpo", format: .zip,
                contentSHA256: String(repeating: "a", count: 64), byteCount: Int64(manifestData.count), importedAt: .now),
                stagingRoot: root, archiveURL: root.appending(path: "fixture.hanlinExpo"), packageRoot: root,
                inspection: .init(fileCount: files.count + 1, directoryCount: 1, compressedBytes: 0,
                    uncompressedBytes: Int64(files.values.reduce(0) { $0 + $1.count } + manifestData.count),
                    maximumDepth: 1, manifestPath: "script.json"),
                manifest: try JSONDecoder().decode(HanlinScriptingManifest.self, from: manifestData))
            return try analyzer.analyze(staged)
        }
        let valid = try preview(manifest)
        XCTAssertTrue(valid.canInstall, valid.findings.map(\.message).joined(separator: "\n"))
        let decoded = try JSONDecoder().decode(HanlinScriptingManifest.self,
            from: JSONSerialization.data(withJSONObject: manifest))
        let program = try HanlinWidgetCompiler.prepare(manifest: decoded, entryPath: "widget.json", files: files)
        // Admission follows the same native runtime and string/legacy-path
        // contract as installed action registration.
        func target(_ path: String, runtime: HanlinRuntimeProfile) -> HanlinPackageEntrypointDescriptor {
            .init(id: "run-intent", kind: .appIntent, sourcePath: path, exportedSymbol: "run.all",
                supportedContexts: [.appIntent, .mainApplication], runtimePolicyID: "prepared-foreground-action-v1",
                runtimeProfile: runtime, compatibility: .partial)
        }
        XCTAssertThrowsError(try HanlinWidgetCompiler.validateHostActionTargets(program.actions,
            manifest: decoded, entrypoints: [target("bundle.js", runtime: .scriptingJSC)]))
        for nonStringHandler in [NSNull(), 17] as [Any] {
            var aliasManifest = manifest
            aliasManifest["actions"] = [["id": "run.all", "handler": nonStringHandler, "entrypoint": "bundle.js"]]
            let alias = try JSONDecoder().decode(HanlinScriptingManifest.self,
                from: JSONSerialization.data(withJSONObject: aliasManifest))
            XCTAssertNoThrow(try HanlinWidgetCompiler.validateHostActionTargets(program.actions,
                manifest: alias, entrypoints: [target("bundle.js", runtime: .hanlinExpo)]))
            XCTAssertNoThrow(try HanlinWidgetCompiler.validateHostActionTargets(program.actions,
                manifest: alias, entrypoints: [target("source/bundle.js", runtime: .hanlinNativeScript)]))
            XCTAssertThrowsError(try HanlinWidgetCompiler.validateHostActionTargets(program.actions,
                manifest: alias, entrypoints: [target("another/bundle.js", runtime: .hanlinExpo)]))
        }
        var stringWins = manifest
        stringWins["actions"] = [["id": "run.all", "handler": "other.js", "entrypoint": "bundle.js"]]
        let selectedHandler = try JSONDecoder().decode(HanlinScriptingManifest.self,
            from: JSONSerialization.data(withJSONObject: stringWins))
        XCTAssertThrowsError(try HanlinWidgetCompiler.validateHostActionTargets(program.actions,
            manifest: selectedHandler, entrypoints: [target("bundle.js", runtime: .hanlinExpo)]))
        let encoded = try JSONEncoder().encode(program)
        let encodedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedActions = try XCTUnwrap(encodedObject["actions"] as? [[String: Any]])
        let encodedHost = try XCTUnwrap(encodedActions.first?["hostAction"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(encodedHost["parameters"] as? NSDictionary), parameters as NSDictionary)
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.host-action"),
            packageID: try .init(validating: "package.host-action"), generation: 7, entrypointID: "widget")
        let context = HanlinWidgetActionContext(identity: identity, engine: .expo,
            artifactSHA256: SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined(),
            family: "systemMedium", actions: program.actions)
        let foreground = try HanlinExpoWidgetsViewRenderer.hostActionIntent(target: "host-run", context: context)
        let foregroundCommand = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(foreground.commandJSON.utf8))
        XCTAssertEqual(foregroundCommand.context, context)
        XCTAssertEqual(foregroundCommand.actionID, "host-run")
        let local = try HanlinExpoWidgetsViewRenderer.actionIntent(target: "local-run", context: context)
        let localCommand = try JSONDecoder().decode(HanlinWidgetActionCommand.self, from: Data(local.commandJSON.utf8))
        XCTAssertEqual(localCommand.actionID, "local-run")
        XCTAssertThrowsError(try HanlinExpoWidgetsViewRenderer.actionIntent(target: "host-run", context: context))
        XCTAssertThrowsError(try HanlinExpoWidgetsViewRenderer.hostActionIntent(target: "local-run", context: context))
        XCTAssertThrowsError(try HanlinWidgetCompiler.preparePresentation(.init(engine: .expo,
            sourcePath: "widget.json", sourceFormat: "expo-layout", actions: program.actions), files: files))

        // Invalid references must be visible import diagnostics, before any tap
        // or foreground VM can run; source order cannot choose another target.
        var invalid: [[String: Any]] = []
        for target in [["entrypointID": "missing", "actionName": "run.all"],
                       ["entrypointID": "run-intent", "actionName": "missing.action"]] {
            var bad = manifest; var badMetadata = metadata
            badMetadata["actions"] = [["id": "host-run", "kind": "hostAction", "hostAction": target]]
            bad["hanlinWidget"] = badMetadata; invalid.append(bad)
        }
        var badHandler = manifest
        badHandler["actions"] = [["id": "run.all", "handler": "other.js"]]
        invalid.append(badHandler)
        var wrongSymbol = manifest; var wrongDeclaration = declaration
        wrongDeclaration["exportedSymbol"] = "another.action"
        wrongSymbol["entrypoints"] = [wrongDeclaration]; invalid.append(wrongSymbol)
        var duplicate = manifest
        duplicate["actions"] = [["id": "run.all", "handler": "bundle.js"], ["id": "run.all", "handler": "bundle.js"]]
        invalid.append(duplicate)
        var wrongKind = manifest; var wrongMetadata = metadata; var localWithTarget = hostAction
        localWithTarget["kind"] = "expoCallback"; wrongMetadata["actions"] = [localWithTarget]
        wrongKind["hanlinWidget"] = wrongMetadata; invalid.append(wrongKind)
        for object in invalid {
            let result = try preview(object)
            XCTAssertFalse(result.canInstall)
            XCTAssertTrue(result.findings.contains { $0.code == "MINIAPP_WIDGET_HOST_ACTION_INVALID" && $0.sourcePath == "script.json" })
        }
        // A legacy local callback declaration keeps its existing admission path.
        var localMetadata = metadata
        localMetadata["actions"] = [["id": "local-run", "kind": "expoCallback"]]
        manifest["hanlinWidget"] = localMetadata
        manifest.removeValue(forKey: "actions"); manifest.removeValue(forKey: "entrypoints")
        XCTAssertTrue(try preview(manifest).canInstall)
    }

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
