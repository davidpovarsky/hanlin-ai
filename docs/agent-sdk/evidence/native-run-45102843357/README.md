# Original full-app Apple failure, run 45102843357

The exact producer source was `f120d0fe1b5c0fe874df83e8d4006e79488928a0`.
The iPad Simulator job `137457462750` failed at **Build full arm64 simulator app**
under Xcode27.2 (27B52), iOS Simulator SDK27.2.

The log establishes five source locations:

| Original location | Diagnostic | Compared with published b66aa5e0 |
|---|---|---|
| HanlinPendingFirstTurn.swift:19 / witness53 | Identifiable witness is main-actor isolated | Still present; root owns the repair |
| ChatViewComponents.swift:2172 / witness2187 | AgentActivityContentView Equatable witness is main-actor isolated | Still present at the comparison source; presentation owner owns the repair |
| KnowledgeListView.swift:25 | Old Color.hlBlue member missing | Source now uses canonical hanlinHLBlue |
| ListView.swift:37 | Old Color.hlBlue member missing | Source now uses canonical hanlinHLBlue |
| ChatViewComponents.swift:6276 | Old Color.hlBluefont member missing | Source now uses canonical hanlinHLBluefont |

State-macro expansions repeat the same Color error; they are not additional
independent defects. The earlier Expo preparation message mentioning a command
with exit code0 is not the app build's failing step: original NativeScript/Expo
preparation, verified RuntimeCore preparation and Swift package resolution all
completed successfully. Shell-echoed version-guard messages are also not
observed failures.

This producer predates the SDK native export steps. It produced no verified
14-binary/four-support SDK export. No linker failure is established because
app Swift compilation failed first. Calendar native tests, app launch,
runtime, visual and physical-device acceptance are not inferred from this run.

Final metadata and diagnostic context were retrieved once. The complete
12,706,650-byte log is retained on Oracle; its SHA256 is
`967db29a673b997ef97e79578df79caacac193a33bbb1dd684a999f4b0c5b479`.
The receipt records exact failed/current source blobs, comparison lines and
the run/job URLs.

This evidence-only change does not repair shared UI, dispatch another run or
relabel a later source as the tested source. The root integration lane owns
the next coherent original Apple validation after the remaining isolation
repairs.
