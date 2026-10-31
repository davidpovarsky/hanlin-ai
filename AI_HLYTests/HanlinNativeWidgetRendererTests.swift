import CryptoKit
import HanlinExpoWidgetSubset
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
