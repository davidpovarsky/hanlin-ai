# MAIN13: native publication value type failure

Run 45389020875, source `2cb851067c4339125ab6fb515522796bceb80c35`, completed the original native/RuntimeHost preparation and export. The first MiniApps build then exited 65 after 1260.912584583 seconds, before its 3600-second deadline. AI and all 52 application cases were not run.

The authentic complete mini-build log has one compiler diagnostic header: `HanlinExpoWidgetPublication.swift:26:36` passes a `[String: HanlinValue]` where `HanlinObject<HanlinValue>` is required. See `diagnostic-context.json`; raw logs and command journals are retained. The focused fix is tracked separately.

The retained artifact was authenticated against its GitHub digest. No absent error, screenshot from failure capture or dispatch is relabelled a native/application PASS.
