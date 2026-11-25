# Otzaria Hanlin union - 25 November 2026

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

## Qualification state after the first native attempt

- Source merge and incoming-tree/preserved-evidence equality: EXECUTED_PASS.
- Canonical static graph/link ownership: see source-checks.json.
- Actual Apple canonical manifest --check: EXECUTED_PASS in job_723e56f227ee,
  15.087 seconds, 523 original application sources, 114 targets and zero local
  package edges. All 754 exact manifest-source inputs were unchanged.
- Original Core continuation controls: INCOMPLETE. Exact original abf production
  and the two unchanged test files resolved; the owned Swift process was stopped
  with exit 125 after 101.342 seconds because concurrent growth consumed the
  recorded remaining disk reserve. No test result is counted as passed. The
  compiler output contains no compiler-error diagnostic before interruption.
- The earlier job_5911ae8b89ea was BLOCKED before extraction, graph evaluation or
  Swift compilation: 8,697,040,896 free bytes versus the then-current joint plan
  of 13,958,643,712 bytes. That failure is retained independently.
- Existing Core48 proof stays separately attributed to its original source,
  receipt, raw log and exact dependency closure. It was not rerun here.
- Latest observed C8 owner task (03:46:36 UTC) has app04 running on sealed
  1710bc6119983799f7d22cb723659ac274fe96b1, after its narrow fixture correction
  4f2bc986 and new composer/MiniApps integration. Its actual app result remains
  pending. This union checkpoint does not silently claim those newer source
  changes or another owner's eventual app test result.

## Native evidence and continuation

All 19 actual raw evidence files were copied from the Mac to Oracle and checked
against the observed receipts. They are retained under native-evidence-01;
the original 306,886-byte compiler log is losslessly gzip-compressed. ARTIFACTS.json
records original and stored hashes. The entire original Core production input
inventory matches before/after. The raw failed receipt remains status FAILED;
its precise cause is the explicit owned storage monitor, not an executed test
failure.

Manifest RESULT SHA-256:
`fec337b2f8ed915e2571718cf23f3e95f9ec2b535c40fac64be444358d600d0d`.
Interrupted Core receipt SHA-256:
`9c91a94345466f2efc5659f853f309147f34f2370d5ee89f0645c8122b1cf065`.
Original compiler log SHA-256:
`6d0d8860262c050ca627f40cde0b1d2c3fe26dc4da8fa44c4dd0788639f1ee9a`.

The second admission was a separately approved phase plan of 1 GiB owned growth,
1 GiB remaining Anytype growth, 8 GiB external growth and 2 GiB OS margin.
It started with 13,443,284,992 actual free bytes; Core started at 13,327,015,936.
The monitor stopped only this owned process group when the remaining 11 GiB
reserve was consumed. No other owner's process or cache was touched.

Retained Mac paths:

- `/Users/m1/builds/hanlin-c92c3f-manifest-check-20261125/evidence`
- `/Users/m1/builds/otzaria-core7-abf-union-20261125`
- `/Users/m1/caches/DerivedData/otzaria-core7-abf-union-20261125`

Reuse the paid exact package/cache for a scoped continuation after fresh storage
admission. Do not clone or repeat the successful graph step merely because the
Core compilation was interrupted. The six original methods and seven invocations
remain the unchanged acceptance requirement; no source or assertion was relaxed.

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
