# Pass 3 state publication and rollback

Code checkout is not a data migration procedure. Do not overwrite a dirty worktree to recover App Group data.

The store writes immutable SHA-named revision envelopes under Revisions/. A pending journal records the candidate and preceding v1 shadow. It writes the compatible v1 shadow before atomically replacing commit.json. Both new host and extension readers/writers hold a bounded POSIX cross-process lock. A journal whose candidate was not committed restores the exact preceding shadow; a committed candidate only needs journal cleanup. Corrupt committed bytes throw an integrity error and cannot silently select v1.

The v1 shadow contains only historical wire fields, no engine/payload/variant/registry fields, and only default-variant widget records. The actual unmodified reader/encoder from 37ba73ba876fad72a3156052751c1b6a89bf825c is compiled in a test-only module to test both directions. Native engines intentionally degrade to their informational legacy root in that old binary. New v2-only state remains in immutable revisions. If the old binary writes a new verified v1 shadow, the new reader reports legacyWriterDetected, honors its legacy collections and retains the last committed native registry/state metadata.

An explicit new-store v1 save publishes a new commit pointing to that revision; stale snapshot-v2.json cannot win. Historical unmarked v2 stores migrate only after checksum/schema validation. Tests simulate interrupted shadow/pointer publication using real committed revision bytes and exercise actual legacy APIs. Apple execution status is recorded in CI_AND_DEVICE_RESULTS.md; test source presence is not a pass.

Package generation rollback uses HanlinAtomicScriptStore.rollback. The host invalidates action authority first and republishes the selected installed generation transactionally. Variant IDs remain configured; state belongs to each exact generation. On mutation failure a package can remain inactive until successful re-publication, preserving fail-closed behavior.

Release remains gated on native build/link tests, simulator WidgetKit behavior and signed physical iPadOS 27 acceptance. No main merge, TestFlight/App Store/public release or signing changes are authorized here. Asana remains read-only.
