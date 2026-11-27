# Shared MiniApps consumer reconciliation

Read-only observations on 26 November 2026, ending at approximately 15:13 UTC. No consumer source, cache, product, account, profile or process was changed. No native build/test was dispatched.

## Exact lean package equality

The complete `Packages/HanlinMiniAppsBridge` package contains 16 tracked files, both Foundation Bridge and SwiftUI Picker products, and no external/runtime package dependency.

| Source identity | Exact Hanlin pin | Complete Bridge package tree |
| --- | --- | --- |
| Anytype PR2 head `4ce34f33ae515840bfbc9458f5904438200987de` | `4b772b5a7f0eb826c9b9204122bba516af777592` | `98ef5d2b47c03f4ea98319a851abae183f500a40` |
| Otzaria PR4 head `bd8bb2d3a0244d1005c2e0eaf1d17901e3b87ade` | `fe3f75d0638671c749225e9a8ddd487db70981cf` | same |
| Retained standalone companion | `86a6dde354947be9329fe1e8f4d45a433fe488c4` | same |
| Active full SDK owner pin | `9565a9e4775901a4cee6f0402d7fd2978fab6612` | same |
| Two-wave production | `a35694f73d07b161d6db5e8c150b7d905e883455` | same |
| Integrated snapshot | `dacf9b70bad5b1d5c279debb473132397b001e9f` | same |

The Bridge implementation subtree is `5334065bd54293b0e9c9a6e05eab166804796e41`; Picker is `1feabd59239b4ce32b007d1ff252cc30703a8774`. Every exact pin has the same complete mode/blob/path listing SHA256: `238bf4e69e70c0b26e2886d8d15c881718553c66bedb2721fa810b7df7c45902`.

PR2's body still describes a774, but the actual source file at its head pins 4b772b5a. The report uses source, not that stale description. Both PRs are draft/open and separate from later owner candidates.

## Full SDK qualification remains separate

The active Anytype delivery source `a089ff29a5c0a7e415aac800844505f099a5561d` and Otzaria release owner `ec14460748dc79818b1a7a3f269a54e3a1ddfaa9` pin the shared SDK to 9565; their retained companion configuration points to 86a6. Otzaria's later isolated candidate `3184f2bc4c4fd80924495c64c74c535321eb0d6a` changes only the SDK gitlink to a356. It is not PR4's current head.

The complete AgentSDK tree matches 9565/current. Platform and PresentationSDK do not: 52 and 42 changed paths respectively at dacf. Thus the 16-file Bridge/Picker equality does not transfer complete SDK or binary qualification.

The fresh original a356 consumer SDK build exited65. Its recorded failures are explicitly disk exhaustion while writing GoogleProvider diagnostics, HanlinChatUI dependency output and Clang ModuleCache. No product source rejection is inferred. `otzaria-a356-shared-sdk-build.log.gz` preserves the original log losslessly; its uncompressed SHA256 is `0da5b60ee982b8bf191e860ddf1b00b6de012bcbcc8742fc816318273ec60646`.

The original file round-trip on source 3d51363c had build PASS and full-selector FAIL. Its 74ea79ec successor had build PASS with no terminal result at the snapshot. Owner receipts observed two genuine durable callbacks, including cold return, but the complete cancellation/replay/file/text/RTL acceptance remains separate. Existing Anytype App15 focus, drag and partial source-flow proofs also do not close full consumer/release acceptance.

## Anytype signing: obsolete and current facts

Root's 14:46 UTC ASC receipt confirms app6839398256, Pinkha Notes, exact bundle `io.anytype.app.NA6HPWARQ2`. The missing-app claim is obsolete.

The retained owner's 05:37 UTC profile audit additionally confirms:
- Active App Store main profile `9RF3H8H69R`, UUID `0a466cdf-7a7e-4153-a179-f4ee2f61385d`.
- Both `group.io.anytype.app.NA6HPWARQ2` and `group.com.itorah.shared` are granted.
- Expected distribution identity is present.
- Multicast is absent, while the actual current owner entitlement file still requires it.
- CMS signature verification was performed using OpenSSL, but release certificate-chain validation was explicitly not performed by that inventory.
- No archive, upload or physical-device acceptance is recorded by that audit.

No new Apple portal request was made by this lane. Root's fresh ten READY_RESOURCE roles apply to Hanlin/MiniApps; they do not certify Anytype. `Tools/MiniApps/owner-signing.json` still has a broad pending label, which should not obscure the two already-granted groups.

## Retained SQLite lifecycle: protect the active gate

At15:10–15:11 UTC, PID77620 was the current xcodebuild, parented by live controller PID77581, with live UI runner77704 and app77811. It is not an orphan inferred from an older failure.

The controller is `anytype-original-sqlite-completion-after-2406/run-only-remaining-original.py`, SHA256 `474c0abbd11477ffecb260add635d46ad0427eaa70bfd1c810be69f8d9ec170d`. It owns the original 5,000-note test on simulator `2F225B23-3149-4384-906F-8865483CBE41`, retaining exactly 2,406 already-native rows. The test allows14,400s; controller timeout14,900s. Observed elapsed time was28m38s.

It writes `retained-original-result.json` and `retained-original.exit` in its finally block. Both were absent while its actual XCTest log was updated at15:11:43. Earlier FAIL receipts explicitly retained this same simulator for retry and do not end the current continuation. No stop or cleanup is recommended by these observations. Subsequent lifecycle decisions require a fresh owner observation.

## Evidence

`reconciliation.json` records all exact source/pin/tree identities and observation times. The other retained files are immutable copies of the original profile audit, SDK build exit/log, prior file round-trip failure, and currently running SQLite controller. `artifact-manifest.json` binds every committed evidence byte, including compressed log and decompressed identity. There is no new native acceptance credit in this report.
