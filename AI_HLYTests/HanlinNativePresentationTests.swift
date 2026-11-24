import Foundation
import JavaScriptCore
import HanlinTranslationUI
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinWidgetCompiler
import XCTest

@MainActor
final class HanlinNativePresentationTests: XCTestCase {
    func testNativeSnippetHasIndependentDurableSessionsWithoutWidgetInstances() throws {
        try withStore { store in
            let identity = try makeIdentity()
            let declaration = HanlinNativePresentationMetadata(engine: .scriptwidget,
                sourcePath: "native/panel.tsx", sourceFormat: "tsx",
                actions: [.init(id: "choose", kind: .function, handler: "choose"),
                    .init(id: "enabled", kind: .setValue, stateKey: "enabled")])
            let source = """
                export function choose(event: {parameters: {id: string}}) {
                  $storage.set("selected", event.parameters.id);
                  $storage.set("count", Number($storage.get("count") || 0) + 1);
                }
                export default function render() {
                  const input = $getenv("presentation");
                  $render(<vstack><text>{input.inputText}</text><text>{$storage.get("selected") || "none"}</text><toggle actionID="enabled" stateKey="enabled" on={Boolean($storage.get("enabled"))}><text>Enabled</text></toggle><text>{String($storage.get("count") || 0)}</text></vstack>);
                }
                """
            let program = try HanlinWidgetCompiler.preparePresentation(declaration,
                files: ["native/panel.tsx": Data(source.utf8)])
            let descriptor = try publish(program, identity: identity, store: store)
            let first = HanlinNativePresentationRequest(identity: identity, kind: .snippet,
                actionName: "search", inputText: "בראשית")
            let second = HanlinNativePresentationRequest(identity: identity, kind: .snippet,
                actionName: "search", inputText: "שבת")
            let initial = try HanlinNativePresentationExecutor.prepare(first, store: store)
            guard case let .scriptwidget(_, context) = initial.prepared else { return XCTFail("Expected original ScriptWidget renderer") }
            let command = HanlinWidgetActionCommand(context: context, actionID: "choose", nonce: "tap-1",
                parameters: .object(["id": .string("Genesis 1:1")]))
            _ = try HanlinNativePresentationExecutor.prepare(first, store: store, action: command)
            _ = try HanlinNativePresentationExecutor.prepare(first, store: store, action: command)
            let toggle = HanlinWidgetActionCommand(context: context, actionID: "enabled", nonce: "toggle-on", desiredValue: true)
            let nativeToggle = try HanlinNativePresentationToggleIntent(command: toggle, value: true)
            XCTAssertTrue(nativeToggle.value)
            let toggled = try HanlinNativePresentationExecutor.prepare(first, store: store, action: toggle)
            guard case let .scriptwidget(toggledNode, _) = toggled.prepared else { return XCTFail("Expected native toggle state") }
            let toggleNode = toggledNode.children.compactMap { child -> HanlinScriptWidgetPreparedNode? in
                if case let .element(node) = child, node.tag == "toggle" { return node }
                return nil
            }.first
            XCTAssertEqual(toggleNode?.props["on"], .bool(true))
            let reopened = HanlinScriptExtensionStore(root: store.root)
            let result = try HanlinNativePresentationExecutor.prepare(first, store: reopened)
            XCTAssertTrue(text(in: result.prepared).contains("Genesis 1:1"))
            XCTAssertEqual(text(in: result.prepared).last, "1")
            let untouched = try HanlinNativePresentationExecutor.prepare(second, store: reopened)
            XCTAssertTrue(text(in: untouched.prepared).contains("none"))
            XCTAssertEqual(try reopened.load()?.widgetInstances.count, 0)
            XCTAssertEqual(try reopened.load()?.widgets.count, 0)
            XCTAssertEqual(try reopened.load()?.intentEntities.first?.nativePresentation, descriptor)
        }
    }

    func testTranslationUsesOriginalAsyncAPIAndReturnsNativeFinishEffect() throws {
        let metadata = HanlinNativePresentationMetadata(engine: .scriptwidget,
            sourcePath: "native/panel.jsx", sourceFormat: "jsx")
        let source = """
            export default async function render() {
              const documents = await $documents.list();
              const text = $getenv("presentation").inputText;
              $presentation.expandSheet();
              $presentation.finish(text + " — תוצאה");
              $render(<text>{String(documents.length)}</text>);
            }
            """
        let program = try HanlinWidgetCompiler.preparePresentation(metadata, files: ["native/panel.jsx": Data(source.utf8)])
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [
            "presentation": .object(["kind": .string("translationUI"), "inputText": .string("מקור"), "allowsReplacement": .bool(true)])
        ])
        XCTAssertTrue(result.presentationEffect.expandsSheet)
        XCTAssertTrue(result.presentationEffect.finishRequested)
        XCTAssertEqual(result.presentationEffect.replacementText, "מקור — תוצאה")
    }

    func testOriginalDynamicIslandCapturesAllSevenNativeRegionsAndFunctionComponents() throws {
        let metadata = HanlinNativePresentationMetadata(engine: .scriptwidget,
            sourcePath: "native/island.tsx", sourceFormat: "tsx")
        let source = """
            function Region(props: {name: string}) { return <text>{props.name}</text>; }
            export default function render() {
              $component("Region", Region);
              $dynamic_island({
                expanded: {leading: <Region name="leading"/>, trailing: <Region name="trailing"/>,
                  center: <Region name="center"/>, bottom: <Region name="bottom"/>},
                compactLeading: <Region name="compact-leading"/>,
                compactTrailing: <Region name="compact-trailing"/>, minimal: <Region name="minimal"/>
              });
            }
            """
        let program = try HanlinWidgetCompiler.preparePresentation(metadata, files: ["native/island.tsx": Data(source.utf8)])
        let result = try HanlinScriptWidgetRuntime.shared.run(program: program, values: [:], environment: [:])
        let island = try XCTUnwrap(result.dynamicIsland)
        let nodes = [island.expandedLeading, island.expandedTrailing, island.expandedCenter,
            island.expandedBottom, island.compactLeading, island.compactTrailing, island.minimal]
        XCTAssertEqual(nodes.compactMap { $0 }.count, 7)
        XCTAssertEqual(nodes.compactMap { $0 }.map(\.tag), Array(repeating: "text", count: 7))
        XCTAssertEqual(result.node.tag, "vstack")
    }

    func testNativePresentationRejectsRemovedGenerationAndDifferentProductStore() throws {
        try withStore { store in
            let identity = try makeIdentity()
            let declaration = HanlinNativePresentationMetadata(engine: .scriptwidget, sourcePath: "native/panel.jsx", sourceFormat: "jsx")
            let program = try HanlinWidgetCompiler.preparePresentation(declaration,
                files: ["native/panel.jsx": Data("export default function render(){ $render(<text>current</text>); }".utf8)])
            _ = try publish(program, identity: identity, store: store)
            let request = HanlinNativePresentationRequest(identity: identity, kind: .snippet, actionName: "search")
            _ = try HanlinNativePresentationExecutor.prepare(request, store: store)
            let other = HanlinScriptExtensionStore(root: store.root.appendingPathComponent("OtherProduct"))
            XCTAssertThrowsError(try HanlinNativePresentationExecutor.prepare(request, store: other))
            try store.save(.init(schemaVersion: 2, generatedAt: .now))
            XCTAssertThrowsError(try HanlinNativePresentationExecutor.prepare(request, store: store))
        }
    }

    func testExpoLayoutEntryUsesItsDeclaredFormatRegardlessOfFileExtension() throws {
        let declaration = HanlinNativePresentationMetadata(engine: .expo,
            sourcePath: "native/layout.json", sourceFormat: "expo-layout")
        let source = #"props => ({ type: "TextView", props: { text: props.label } })"#
        let program = try HanlinWidgetCompiler.preparePresentation(declaration,
            files: ["native/layout.json": Data(source.utf8), "bundle.js": Data("unrelated invalid source".utf8)])
        let context = try XCTUnwrap(JSContext())
        let check: @convention(block) () -> Void = {}
        context.setObject(check, forKeyedSubscript: "__scriptWidgetCheckExecution" as NSString)
        let layout = try XCTUnwrap(context.evaluateScript(program.javaScript))
        XCTAssertNil(context.exception)
        let rendered = try XCTUnwrap(layout.call(withArguments: [["label": "מקור מקורי"]])?.toDictionary())
        XCTAssertNil(context.exception)
        let properties = try XCTUnwrap(rendered["props"] as? [String: Any])
        XCTAssertEqual(properties["text"] as? String, "מקור מקורי")
        XCTAssertThrowsError(try HanlinWidgetCompiler.preparePresentation(declaration,
            files: ["native/layout.json": Data([0xff])]))
    }

    private func publish(_ program: HanlinWidgetProgram, identity: HanlinScriptExtensionIdentity,
                         store: HanlinScriptExtensionStore) throws -> HanlinNativePresentationDescriptor {
        let artifact = try store.storeArtifact(data: JSONEncoder().encode(program),
            installedPackageID: identity.installedPackageID, generation: identity.generation)
        let descriptor = HanlinNativePresentationDescriptor(engine: program.engine, programRef: artifact.ref,
            programSHA256: artifact.sha256)
        try store.save(.init(schemaVersion: 2, generatedAt: .now,
            intentEntities: [.init(identity: identity, id: "search", displayName: "Search", nativePresentation: descriptor)]))
        return descriptor
    }

    private func makeIdentity() throws -> HanlinScriptExtensionIdentity {
        .init(installedPackageID: try .init(validating: "installed.native-presentation"),
            packageID: try .init(validating: "package.native-presentation"),
            generation: 1, entrypointID: "appIntents")
    }

    private func withStore(_ body: (HanlinScriptExtensionStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(.init(root: root))
    }

    private func text(in prepared: HanlinPreparedWidget) -> [String] {
        guard case let .scriptwidget(node, _) = prepared else { return [] }
        func collect(_ node: HanlinScriptWidgetPreparedNode) -> [String] {
            node.children.flatMap { child in
                switch child {
                case let .element(element): collect(element)
                case let .value(.string(value)): [value]
                default: []
                }
            }
        }
        return collect(node)
    }
}
