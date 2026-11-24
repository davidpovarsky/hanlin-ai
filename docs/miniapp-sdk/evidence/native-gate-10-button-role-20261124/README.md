# Native gate 10: native presentation ButtonRole ambiguity

Run 45354940642, source a12eb646aeb5c484f746c07ecffafc7d9f34f167, failed during the HanlinMiniApps build-for-testing command. It exited 65 after 1203.752 seconds, before app or UI tests executed. The authenticated artifact digest and original failure logs are retained with this receipt.

The only compiler error headers identify HanlinNativePresentationView.swift lines 13 and 16. Both SwiftUI and the reexported original HanlinExpoWidgetSubset publish a ButtonRole type. The existing HanlinExpoWidgetNative.render callback explicitly takes SwiftUI.ButtonRole, as do its native Button consumers. The correction qualifies only those two annotations. Original Expo sources, exports, callback behavior, UI cases, test assertions, and acceptance commands are unchanged.

Local Swift parsing and whitespace validation passed. They do not establish Apple typechecking or native test success; the corrected app build and all 42 selected app tests remain awaiting actual execution. No unchanged test suite was rerun, and no CI was dispatched by this agent.

The original acceptance.json is preserved byte-for-byte, including its inconsistent build=NOT_RUN field. Its status=BUILD_FAILED, the completed commands.jsonl entry, and the compiler log establish the actual failed build. The durable command journal retains the completed exit 65 despite subsequent diagnostic commands. No cancellation or timeout is inferred.
