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

@MainActor
@Suite("Original ScriptWidget image drawing")
struct HanlinOriginalScriptWidgetImageTests {
    @Test(arguments: [0.0, 45.0, 90.0, 180.0])
    func imageRotationKeepsTheOriginalSwiftUICenter(degrees: Double) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let actual = try raster(ScriptWidgetElementView(element: .init(tagString: "image",
            props: ["name": "asymmetric.png", "frame": "80,40", "rotation": degrees], children: []),
            context: fixture.context))
        let native = try #require(ScriptWidgetImagePipeline.image(at: fixture.file))
        #if os(macOS)
        let expected = try raster(Image(nsImage: native).resizable().frame(width: 80, height: 40)
            .rotationEffect(.degrees(degrees), anchor: .center))
        #else
        let expected = try raster(Image(uiImage: native).resizable().frame(width: 80, height: 40)
            .rotationEffect(.degrees(degrees), anchor: .center))
        #endif
        #expect(actual == expected, "The original image must rotate around its destination frame center.")
        try save(actual, name: "image-center-rotation-\(Int(degrees)).png")
    }

    @Test(arguments: ["frame", "rotation", "ratio"])
    func invalidImageDimensionsAndTransformsNeverReachSwiftUI(attribute: String) throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let values: [String]
        var base: [AnyHashable: Any] = ["name": "asymmetric.png", "mode": "fit"]
        switch attribute {
        case "frame":
            values = ["nan", "inf", "-1", "nan,40", "40,inf", "-10,40", "max,-1",
                      "-1,max", "nan,40,topLeading", "40,inf,center", "max,-1,topLeading", "-1,max,center"]
        case "rotation":
            base["frame"] = "80,40"
            values = ["nan", "inf", "-inf"]
        default:
            base["frame"] = "80,40"
            values = ["nan", "inf", "-1", "0"]
        }
        let expected = try raster(ScriptWidgetElementView(element: .init(tagString: "image",
            props: base, children: []), context: fixture.context))
        for value in values {
            var props = base
            props[attribute] = value
            let actual = try raster(ScriptWidgetElementView(element: .init(tagString: "image",
                props: props, children: []), context: fixture.context))
            #expect(actual == expected, "Invalid \(attribute)=\(value) must preserve the untransformed image.")
        }
    }

    @Test func largeValidImagesUseTheOriginalBoundedDownsampler() throws {
        ScriptWidgetImagePipeline.removeAll()
        let data = try solidImage(width: 3_072, height: 2_048)
        #expect(data.count < ScriptWidgetImagePipeline.maximumInputBytes)
        let result = try #require(ScriptWidgetImagePipeline.image(data: data))
        #if os(macOS)
        let representation = try #require(result.representations.first)
        #expect(representation.pixelsWide <= ScriptWidgetImagePipeline.defaultMaximumPixelSize)
        #expect(representation.pixelsHigh <= ScriptWidgetImagePipeline.defaultMaximumPixelSize)
        #else
        let pixels = try #require(result.cgImage)
        #expect(pixels.width <= ScriptWidgetImagePipeline.defaultMaximumPixelSize)
        #expect(pixels.height <= ScriptWidgetImagePipeline.defaultMaximumPixelSize)
        #endif
    }

    @Test func oversizedAndMalformedImagesAreRejectedBeforeDisplay() throws {
        let oversized = try solidImage(width: 4_097, height: 4_097)
        #expect(oversized.count < ScriptWidgetImagePipeline.maximumInputBytes)
        #expect(ScriptWidgetImagePipeline.image(data: oversized) == nil,
            "A compressed image exceeding 16M source pixels must not enter the renderer.")
        #expect(ScriptWidgetImagePipeline.image(data: Data(repeating: 0,
            count: ScriptWidgetImagePipeline.maximumInputBytes + 1)) == nil)
        #expect(ScriptWidgetImagePipeline.image(data: Data("not an encoded image".utf8)) == nil)
    }

    private func fixture() throws -> (root: URL, file: URL, context: ScriptWidgetElementContext) {
        let root = FileManager.default.temporaryDirectory.appending(path: "Hanlin-Image-Drawing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: HStack(spacing: 0) {
            Color.red.frame(width: 16, height: 16)
            Color.blue.frame(width: 16, height: 16)
        })
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let file = root.appending(path: "asymmetric.png")
        try png(image).write(to: file)
        let identity = HanlinScriptExtensionIdentity(installedPackageID: try .init(validating: "installed.image-drawing"),
            packageID: try .init(validating: "package.image-drawing"), generation: 1, entrypointID: "widget")
        let context = ScriptWidgetElementContext(actionContext: .init(identity: identity, engine: .scriptwidget,
            artifactSHA256: String(repeating: "a", count: 64), family: "systemMedium",
            resources: ["asymmetric.png": file]))
        return (root, file, context)
    }

    private func solidImage(width: CGFloat, height: CGFloat) throws -> Data {
        let renderer = ImageRenderer(content: Color.red.frame(width: width, height: height))
        renderer.scale = 1
        return try png(#require(renderer.cgImage))
    }

    private func raster<Content: View>(_ content: Content) throws -> Data {
        let renderer = ImageRenderer(content: content.frame(width: 220, height: 160)
            .environment(\.colorScheme, .light).environment(\.locale, Locale(identifier: "en_US")))
        renderer.scale = 1
        return try png(#require(renderer.cgImage))
    }

    private func png(_ image: CGImage) throws -> Data {
        #if os(macOS)
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        #else
        return try #require(UIImage(cgImage: image).pngData())
        #endif
    }

    private func save(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"] else { return }
        let directory = URL(filePath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: name))
    }
}
