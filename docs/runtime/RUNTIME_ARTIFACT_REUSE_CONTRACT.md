# Native component reuse and current Host

The bundle workflow may reuse completed native components without rebuilding
Node for a Host-only change. Reuse is **not** acceptance of the previous entire
workflow, current application, or physical device behavior.

`verify_runtime_reuse.py` requires authenticated GitHub metadata for the same
repository, a completed approved producer workflow and its exact source SHA.
The current native-input projection is computed against both source revisions:
Node revision/configuration/exports, pinned patch manifests and original patch
bytes, native build/patch scripts, adapter, and locked Python inputs must match.
The exports file is checked by the actual build script against the locked
`node.exportedSymbols`; mismatched exports cannot produce a successful slice.
Host packages and their artifact dependency hash may differ independently.

Each of the device slice, simulator slice and Python runtime requires a real
successful component job and actual build step. The latest actual execution
must pass. Zero-step successes are insufficient; cloned rerun steps keep the
original execution's attempt/job identity. A later zero-step allocation
cancellation supplies no new execution evidence. The exact unique live artifact
must belong to that source/run/repository and successful execution interval,
and carry a GitHub SHA-256 archive digest. An unrelated failed Host/assembly job
does not erase a successful native component, nor does its success prove smoke.

Assembly downloads the **immutable artifact IDs**, verifies actual downloaded
ZIP bytes against their authenticated digests before extracting, rejects unsafe
archive paths, then retains the existing internal framework/Python checksums.
It always prepares/tests/downloads the **current-run Host**. Assembly requires
that Host and plan job to succeed even when native jobs are skipped for reuse.

`NativeReuseProvenance.json` records source SHA/run/conclusion, actual producer
job/attempt, artifact IDs/digests, source and consumer dependency identities,
native input identity and consumer SHA. It is transferred by an immutable
current-run artifact ID and embedded inside the final checksum-protected bundle.
`REUSED_VERIFIED_PASS` in this receipt is explicitly scoped to **native component
production only**. Fresh combined simulator WASM/FD/Host smoke and affected app
gates remain mandatory; no binary hash or verified lock is invented before them.

No automatic workflow trigger, publication, merge or device waiver is added.
