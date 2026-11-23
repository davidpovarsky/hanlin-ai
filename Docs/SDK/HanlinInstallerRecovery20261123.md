# Canonical installer interrupted-update recovery — 23 November 2026

The original installer could complete selected-manifest generation, then fail
during selected-source materialization before recording the generated file
hashes. Its earlier source-ready receipt still described the untouched root
manifest. A later retry rejected its own generated output as an external edit.

The focused reproduction used a real temporary Git repository, an initial
successful installation, a new immutable source revision, the fixture's actual
generator and real SwiftPM manifest evaluation. A controlled exception at the
selected-source sparse-fetch boundary occurred only after both generated files
were written. The retry on the unchanged installer failed with:

> Generated SDK file was edited outside the installer: Package.swift

No native runtime, actual host checkout or network fetch was used by this
failure fixture. The fixture generator does not certify Hanlin runtime or UI.

## Shared implementation correction

`Scripts/SDK/install.py` now writes an intermediate
`profile-generated` receipt immediately after successful generation and
before path validation or sparse source fetching. It records the exact hashes
of the two already-managed outputs. Read-only `--check` continues to require
the final `installed` state, so interrupted work cannot be accepted as a
finished installation.

Retry still uses the original `verify_owned_changes` and
`reset_generated` implementations. A changed manifest, generated inventory
or original source file is rejected and retained. The fix adds no bypass for
manual edits, changes no lock, and invokes the same newly pinned generator and
canonical source/resource materialization.

Baseline installer Git blob: `b08f172c5b944fe2081c2c7b08eff5866b729eb7`. Corrected installer Git blob:
`c12b6a78e04657e11bb6f695591d9af5f0697036`.

## Focused evidence

Only these two new cases in the existing real-Git installer suite ran:

- `SDKInstallTests.test_interrupted_selected_source_update_is_retryable`:
  interruption after generation of a new locked revision remains unaccepted,
  then retries successfully and installs that revision's actual source bytes.
- `SDKInstallTests.test_interrupted_install_preserves_external_generated_and_source_edits`:
  after an interrupted install, independent edits to each managed output and
  the original generator are each rejected and preserved.

Before the fix, the two-case run exited 1 (one retry error and one edit-category
subcase failure). After the fix, both cases passed in 1.572 seconds. The latter
includes all three external-edit subcases. The original suite was not repeated.

| Retained log | SHA-256 |
| --- | --- |
| `build/installer-recovery-20261123/before.log` | `424296ead339732a709b5b12d24f87e56dafbebd0256d15db3a48b37196cf0ab` |
| `build/installer-recovery-20261123/after.log` | `20575a08142811d5141db60762a6d9587ecdfac4f7a9f545a55ebf4dc63aafba` |

Reproduce the focused cases from the SDK root:

~~~sh
python3 Scripts/SDK/tests/test_install.py \
  SDKInstallTests.test_interrupted_selected_source_update_is_retryable \
  SDKInstallTests.test_interrupted_install_preserves_external_generated_and_source_edits -v
~~~

## Source and acceptance boundary

The change is installer orchestration plus two regression cases and this receipt.
It changes no selected Swift/C implementation, resource, package manifest,
generator or native artifact tool. The three real-host selected-profile identity
observation at `66845991bc06fd008b21dc24bf55d84a9e3a1d56` remains an
unchanged-source observation; no host was repinned and no native/UI gate was
dispatched or repeated. Actual native and visual acceptance retains its original
executing source and runtime identity.
