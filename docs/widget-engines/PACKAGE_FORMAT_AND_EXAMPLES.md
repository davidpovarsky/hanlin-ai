# Pass 3 widget package contract

Archive containers are ZIP .hanlinExpo or .scripting files. Both pass through the same HanlinPackageCenter, archive policy, analyzer and installed-store path; there is no fixture bypass.

A native widget script.json declares name/version, kind=widget, canonical entry, matching hanlinRuntime, explicit widgetEngine (expo or scriptwidget), and hanlinWidget with abiVersion=1, sourceFormat (jsx, tsx or javascript), families and actions. Expo additionally requires package.json with hanlinRuntime=hanlin-expo, hanlinExpo.runtimeVersion=58.0.3 and supported native plugin versions. ScriptWidget uses scripting-jsc with its own widget ABI, not the Scripting app typechecker.

Example metadata:

~~~json
{"name":"Counter","version":"1.0.0","kind":"widget","entry":"widget.jsx","hanlinRuntime":"hanlin-expo","widgetEngine":"expo","hanlinWidget":{"abiVersion":1,"sourceFormat":"jsx","families":["systemMedium"],"actions":[{"id":"increment","kind":"expoCallback"}]}}
~~~

Expo source imports the pinned @expo/ui/swift-ui components/modifiers and exports a default layout function containing 'widget'. Use Button target="increment" onPress={() => ({count: (props.count ?? 7) + 1})}. The original bundle resolves native JSX components and calls onButtonPress; the generic router contains no counter rule. Local Expo module imports are compiled into the immutable program registry. Supported external module names are react, react/jsx-runtime, @expo/ui/swift-ui and its modifiers.

ScriptWidget source calls $render with upstream JSX. Native buttons use actionID or named onClick. Their action declaration uses kind=function and a handler identifier; reload uses kind=reload. Toggle uses on, actionID and stateKey, whose declaration is kind=setValue with that same stateKey. The native SetValueIntent persists a Bool. Example: $render(<toggle on={$storage.get('backup') ?? false} actionID="backup" stateKey="backup"><text>Backup</text></toggle>).

The typed $storage get/set/remove and original string/JSON method subset is transaction-local and durable only after a successful action commit. $getenv/$widget receive instance/family parameters. The original $element, util.js and function-component resolution are used. The full upstream app/editor/system-service API surface is not currently imported; network/file/import API completion and native execution evidence must be tracked honestly rather than inferred from global names.

New native descriptor inline source fields are empty; refs point to verified HanlinWidgetProgram JSON under Packages/<installedID>/generations/<generation>/artifacts/<sha>. Program metadata contains source/compiler hashes and the exact engine pin. Both provider and action executor validate that same program. Source limits are 512 KiB per file, compiled output 2 MiB, 1,000 nodes/64 levels/128 props, resource bytes 1 MiB and snapshot bytes 4 MiB. Cooperative deadlines do not imply hard interruption of every JavaScriptCore native call.

Legacy archives with no engine remain legacy. Their JSON tree uses actual tagged HanlinValue encoding, for example properties.text={"type":"string","value":"Legacy"}. A .js/.tsx suffix never selects Expo. Unknown engine/runtime conflicts, absent entry, invalid syntax/ABI and unsafe archive paths must fail preview.

In Package Details, create independent named instances, then select those names in WidgetKit configuration. Two placements using one instance share state. Variant IDs survive updates; state is generation-scoped, so a new generation starts fresh unless explicitly migrated. A retained-generation rollback restores that generation's prior state. Explicit recorded entity migrations follow valid upgrade selections and stale action envelopes fail before mutation.

Canonical external samples and source strings: Scripts/Widgets/samples.mjs. All seven archive and source hashes: Fixtures/Widgets/SHA256.json. Five are positive cases pending native acceptance. Invalid-Cases must fail import. Mixed-Native-Widget deliberately declares ABI 0 and is DEFERRED_OPTIONAL; it is not a working mixed-engine example. Rebuilding archives does not prove import, install, display or interaction.
