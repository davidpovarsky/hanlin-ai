import Foundation
import HanlinScriptContracts
import HanlinScriptExtensions
import HanlinScriptWidgetOriginal
import HanlinWidgetCompiler
import Testing

extension HanlinDualWidgetEnginesTests {
    @Test func rootFragmentsPreserveOriginalElementAllowances() throws {
        func run(_ source: String) throws -> HanlinScriptWidgetExecution {
            try HanlinScriptWidgetRuntime.shared.run(program: .init(engine: .scriptwidget,
                sourceSHA256: String(repeating: "a", count: 64), compilerSHA256: String(repeating: "b", count: 64),
                javaScript: "async function $main() { \(source) }", actions: [], families: ["systemMedium"]),
                values: [:], environment: [:])
        }
        func elementCount(_ node: HanlinScriptWidgetPreparedNode) -> Int {
            1 + node.children.reduce(0) { count, child in
                if case let .element(element) = child { return count + elementCount(element) }
                return count
            }
        }
        func depth(_ node: HanlinScriptWidgetPreparedNode) -> Int {
            1 + (node.children.compactMap { child -> Int? in
                if case let .element(element) = child { return depth(element) }
                return nil
            }.max() ?? 0)
        }
        let maximumNodes = HanlinOriginalScriptWidgetSession.maximumElementNodes
        let maximumDepth = HanlinOriginalScriptWidgetSession.maximumElementDepth
        func wideTree(_ leaves: Int) -> String {
            "ScriptWidget.createElement('vstack', {}, Array.from({length:\(leaves)}, () => ScriptWidget.createElement('text', {}, 'x')))"
        }
        // Upstream unwraps repeated single-root Fragments after resolving a
        // function component, flattening nested child arrays at the same depth.
        let entry = """
            import { tree } from './tree';
            function Root() {
              const inner = <>{[[tree]]}</>;
              return <>{[[inner]]}</>;
            }
            export default function render() { $render(<Root />); }
            """
        // The real Apple compiler also has to bind the per-operation deadline
        // callback while compiling this entry and its independently typed module.
        let compiled = try HanlinWidgetCompiler.preparePresentation(
            .init(engine: .scriptwidget, sourcePath: "native/root.tsx", sourceFormat: "tsx"),
            files: ["native/root.tsx": Data(entry.utf8),
                    "native/tree.ts": Data("export const tree = \(wideTree(maximumNodes - 1));".utf8)])
        let wide = try HanlinScriptWidgetRuntime.shared.run(program: compiled, values: [:], environment: [:]).node
        #expect(wide.tag == "vstack")
        #expect(elementCount(wide) == maximumNodes)
        let deep = try run("""
            let root = ScriptWidget.createElement('text', {}, 'At original depth');
            for (let level = 1; level < \(maximumDepth); level++) root = ScriptWidget.createElement('vstack', {}, root);
            $render(ScriptWidget.createElement('Fragment', {}, [[root]]));
            """).node
        #expect(deep.tag == "vstack")
        #expect(depth(deep) == maximumDepth)
        #expect(throws: HanlinScriptWidgetError.self) {
            _ = try run("$render(ScriptWidget.createElement('Fragment', {}, \(wideTree(maximumNodes))));")
        }
        #expect(throws: HanlinScriptWidgetError.self) {
            _ = try run("""
                let root = ScriptWidget.createElement('text', {}, 'Too deep');
                for (let level = 1; level <= \(maximumDepth); level++) root = ScriptWidget.createElement('vstack', {}, root);
                $render(ScriptWidget.createElement('Fragment', {}, root));
                """)
        }
        // Only single-element roots normalize. Nested and multiple-child
        // Fragments retain their original element/depth semantics.
        let nested = try run("$render(ScriptWidget.createElement('vstack', {}, ScriptWidget.createElement('Fragment', {}, ScriptWidget.createElement('text', {}, 'Nested'))));").node
        guard case let .element(fragment)? = nested.children.first else {
            Issue.record("Nested Fragment was lost"); return
        }
        #expect(fragment.tag == "Fragment")
        #expect(elementCount(nested) == 3)
        for children in ["'Scalar', ScriptWidget.createElement('text', {}, 'Element')", "ScriptWidget.createElement('text', {}, 'One'), ScriptWidget.createElement('text', {}, 'Two')"] {
            #expect(try run("$render(ScriptWidget.createElement('Fragment', {}, \(children)));").node.tag == "Fragment")
        }
        #expect(throws: HanlinScriptWidgetError.self) {
            _ = try run("const root = ScriptWidget.createElement('Fragment', {}); root.children = [root]; $render(root);")
        }
        // Each original Dynamic Island region is a separate normalized root.
        let island = try #require(try run("""
            const root = ScriptWidget.createElement('Fragment', {}, [[\(wideTree(maximumNodes - 1))]]);
            $dynamic_island({expanded: {}, compactLeading: root, compactTrailing: root, minimal: root});
            """).dynamicIsland)
        for node in [island.compactLeading, island.compactTrailing, island.minimal] {
            let normalized = try #require(node)
            #expect(normalized.tag == "vstack")
            #expect(elementCount(normalized) == maximumNodes)
        }
    }
}
