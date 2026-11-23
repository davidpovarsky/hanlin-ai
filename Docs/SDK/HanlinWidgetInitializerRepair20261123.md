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
