# Otzaria Hanlin union ? 25 November 2026

## Source checkpoint

The real merge commit `c92c3f904872b37287861dfafa9cc668d5dc44c3` has parents
`4e921b9517f2fc28fcaebcb2ba7441ab1fb46a90` and
`5b69bbb52013686922efa7c4e7d9f2d44b774f94`.

All eleven conflicts were the reviewed pin/generated-manifest files. Their final
blobs are exactly the incoming 5b69 blobs. The complete merged tree differs from
5b69 only by the five byte-identical files retained under
`docs/agent-sdk/otzaria-integration-20261125`. No production source or test assertion
was changed by the merge. Core remains
`abf0921c6e89e6521cc2b510ff11016b45a0ef08` throughout the active pins.

The full merge whitespace check reports incoming original vendored tslib CRLF
and preserved raw evidence whitespace. Those original bytes were retained;
the added delta relative to incoming 5b69 passes `git diff --check`.
The original diagnostic is retained as a compressed log.

## Qualification state at this checkpoint

- Source merge and incoming-tree/preserved-evidence equality: EXECUTED_PASS.
- Canonical static graph/link ownership: see source-checks.json.
- Actual Apple canonical manifest --check: NOT_RUN; waiting for the storage owner
  to admit its small manifest-evaluation footprint.
- Original Core continuation controls: NOT_RUN; six unchanged original methods,
  seven invocations, prepared in run-core7.py. The existing test fixture uses the
  real original producer with its original mock transport. This is not a live
  provider test, app test, or substitute SDK.
- Existing Core48 proof stays separately attributed to its original source,
  receipt, raw log and exact dependency closure. It is not rerun here.
- C8 owner app03 remains sealed at exact incoming 5b69. At the latest Asana
  snapshot, 2026-11-25 03:17:41 UTC, the native app build is still running; no
  executed app-test pass is claimed. The future active-lock validation correction
  at owner 0d6280a4 is not silently included in this sealed source.

## Exact source preparation

The canonical manifest source archive contains 754 committed files (8,202,590
bytes of original blob content), including original symlink identity. It is an
exact source closure and does not pretend to be a Git checkout.

Archive: `hanlin-c92c3f-manifest-source.tar.gz`, 2,617,262 bytes,
SHA-256 `a459fe8b3b1da2c17c78a63894c140f7f6b8d6d867dcd853fc6340a7ea43ac0f`.
Source manifest SHA-256:
`04f5f9d9a703ae8c94baea9047b6b750478ecf0c2586ec6fed5d11653c1d1e88`.

The prepared Core7 runner admits actual incremental disk plus caller-declared
concurrent growth and OS margin. It preserves the donor cache, makes an isolated
APFS clone, quarantines only the clone's nonportable ModuleCache directories,
verifies complete original production inputs before and after, retains both
original test files byte-for-byte, records actual test XML and both parameter
invocations, and refuses a skipped/missing/duplicate/failing case.

Final Maktabah UI, live provider, device, signing and TestFlight acceptance remain
separate obligations owned by the application integration.
