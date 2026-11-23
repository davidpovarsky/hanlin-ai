# Original widget initializer repair — 23 November 2026

Native run [45126861232](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45126861232)
at source 705f1bd81587d7133aec4d1cd7f9a2b802e7ded6 stopped during full simulator
build. The exact compiler diagnostic is that HanlinScriptingWidget does not
conform to Widget; the accompanying SwiftUI declaration requires init().
Adding the public init(kind:) during extraction suppressed Swift's synthesized
zero-argument initializer.

The shared original widget now explicitly implements init(). It reads the current
extension bundle's HanlinExtensionHost.WidgetKind through the existing strict
configuration loader. Missing or malformed configuration fails the initializer's
precondition; it never supplies Hanlin's widget identifier to an unrelated host.
The original Hanlin wrapper still explicitly calls init(kind:) with its unchanged
original identifier. That explicit initializer remains available to other hosts.

This is one initializer addition. The original widget configuration, timeline,
rendering, AppIntent entities, live activity views, interactions and literals after
the original initializer are byte-identical. Their retained suffix SHA256 is:
461bb5b2e0befc853314c9f2fe1fb17139111b3139686f8124ac5bbde124ac25.

Validation: the actual compiler's required declaration was read from the native
log; source preservation and git diff checks passed. Local Swift syntax parsing is
reported separately from Apple compilation. No native test, UI execution, signing
or device behavior is claimed from this source correction. The next coordinated
native build remains the acceptance gate.

The earlier native-prepared artifact 14796481588 was uploaded successfully before
this compiler failure (184426234 bytes; SHA256
0156e8faf203f58e0d177e69d8f53d7b33fd7fd456b8065babb978edf28b1666).
Its preparation result does not make this failed application build successful.


## Subsequent original host import correction

The next original full-app run [45133911239](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45133911239), at66845991bc06fd008b21dc24bf55d84a9e3a1d56, progressed to the thin widget executable and failed before any selected unit/UI test. The complete original compiler log contains three errors at HanlinScriptingWidgets/HanlinScriptingWidgets.swift: unresolved Widget and WidgetBundle, with the resulting @main entry-point error. Its direct SwiftUI import had been omitted when the host wrapper was reduced; the original603576fa file contained that import.

The correction adds only `import SwiftUI` to the thin original host entry point. Removing that one added line reproduces the previous file byte for byte. Canonical widget bodies, timeline, App Intents, initializer policy, resources, source identities and package graph are unchanged. The other thin OS entry points were inspected for this same direct-protocol import issue; no equivalent omission was found. This does not add an alternative widget or generic fallback policy.

Original artifact14803110248:1,042,365bytes; SHA25603b9d7c9528ae7c3994ccb7d7f4cb46917a9176b09219928cfadcab1300aec70; all ZIP CRCs verified. Original simulator-logs/06-xcodebuild-simulator.log:7,684,890bytes; SHA256d2511cdc89c268aeab692e5a49e23384e5179d47b42354e47ec70cdb653f21df. [Exact receipt and compiler diagnostics](../../docs/agent-sdk/evidence/widget-host-import-45133911239/receipt.json).

The prepared native asset artifact was retained by the failed run but is not eligible for publication. The corrected host still requires the existing full-app native gate. No selected test passed or failed in this build-only failure, and no portable import/string assertion is presented as Apple compilation proof.
