# Pass 3 widget pipeline

The registered kind remains com.hanlin.scripting.widget in HanlinScriptingWidgets.appex. Three engines are selected by validated stored metadata: legacy, expo, scriptwidget. Missing engine in a historical v1 record means legacy; unknown declarations fail import. Corrupt v2 engine/payload records render an error.

Install Preview and installation use HanlinWidgetCompiler with explicit ABI/source-format metadata. Babel is the pinned ScriptWidget support resource. Expo JSX imports resolve to the pinned Expo Widgets globals; ScriptWidget JSX uses the original ScriptWidget.createElement/$element JSExport object and $render lifecycle. The generic Scripting compiler remains separate.

Installed programs are immutable HanlinWidgetProgram values: ABI, engine/upstream commit, source/compiler SHA, compiled source, action declarations, families and bounded resources. Host publication exports a generation-scoped content-addressed App Group ref. Descriptor inline source fields are empty for new native programs and are never a fallback authority.

The provider verifies the artifact and exact selected entity, executes a one-shot JSC context on its preparation task, freezes a Sendable value, and supplies it to the timeline entry. SwiftUI bodies render native prepared data and never compile or execute JavaScript. Expo's original AnyChild renderer lives in HanlinExpoWidgetNative under the existing binary-target owner. Only the WidgetKit Xcode target links this product. ScriptWidget uses its original native builders/attributes with a narrow Hanlin resource/action context.

Identity includes installed package, package, generation, entrypoint, engine and a real configured variant. Family and artifact digest travel with the action context. The app can create independent named instances; identical selections share state. Exact recorded entity migrations follow upgrades; normal lookup never uses a partial identifier or first-widget fallback.

Native Button/Toggle -> typed command -> current enabled published installation and declared action -> verified program -> source callback/named function or Boolean set-value -> serialized atomic state revision -> reload only the registered kind. Legacy compiled intents keep their existing route. No hardcoded counter actions or UserDefaults fallback exists in the native router.

Host update/rollback/disable/uninstall invalidates extension action authority before asynchronous installed-store changes. Publication reads the latest state/instances under the same cross-process lock as actions and preserves Live Activities. User state is generation-scoped; upgrades keep variant IDs but start new generation state. Rollback to a retained generation restores its state. Uninstall removes its registry/state after installed-store removal.

No public JavaScriptCore API used here can preempt every native parser or built-in call. Compiler-inserted loop/function guards and pre/post deadlines are cooperative bounds, with explicit byte/tree limits. Native per-tap OS retry IDs are unavailable: generated invocation IDs distinguish real invocations; explicitly supplied nonces deduplicate the last 128 committed receipts. Automatic OS retries are at-least-once and are not advertised as exactly-once.
