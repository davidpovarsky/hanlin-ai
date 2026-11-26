# PR19 system integration: MiniApps owns the new surfaces

The integration merges reviewed PR19 system-surface code into the two-wave source while retaining the standalone product boundary. The graph has **13 shipping bundles**: Hanlin and its four existing extensions, plus MiniApps and its four existing extensions and three new extensions. The new targets are Keyboard, Notification Content and Camera Capture.

## Product ownership

The existing MiniApps extension generator creates the new targets from the original Notification/Translation templates and links canonical shared SDK products. The parallel AI-only generator and new Hanlin wrapper targets are omitted. Camera links and control registration are added to MiniApps Widgets. Hanlin's original scene, intent registration and widget entry files remain byte-identical to the integration base.

New Spotlight/camera publication, index reopening and Camera-section construction require the existing standalone MiniApps bundle identity. Shared catalog and SDK types remain generic and available to consumers. Legacy Hanlin widget publication remains outside that guard.

The exact original ten signing role, bundle, provisioning environment and entitlement tuples are retained. Three MiniApps entries are appended. Profile creation still requires the original full source SHA and numeric build context, or a concrete original GitHub run. A generic operation label does not replace those checks.

## Verification

| Check | Actual result |
| --- | --- |
| Original focused Python suites | 98 unique methods passed across the retained 97-method run and final 10-method system-target rerun |
| Original Node manifest/presentation/authoring checks | 7 methods passed, no skips in those selected runs |
| Canonical manifest, App Intent resources and Xcode project generation/check | Passed |
| Product source verification | SOURCE_VALIDATED |
| Canonical source inventory | 102 sources and 200 local public exports |
| Source-backed reachability | 100 conditional cells; new Spotlight/capture publication explicitly MiniApps-only |
| Swift syntax parse | 5 affected files passed on Linux; Apple typechecking is separate |
| Discovery/capture native inventory | 9 XCTest methods, execution pending |

Source retains the approved camera lifecycle fixes: fresh stored-generation admission, active-window ownership, qualified dismissal and one outstanding camera-context load across window release. The original eight discovery/capture methods remain, with a ninth narrow product-policy method. Root's existing headless Shortcuts method is byte-identical to the base.

## Evidence and unresolved acceptance

The integration-proof.json records exact base/upstream commits, source hashes, roles, selectors and limits. The receipts directory retains failed attempts and final passes. Failures were resolved in production generation or corrected expanded-contract expectations without weakening original release identity checks.

Portable authoring checks use original fixtures and the actual existing TypeScript compiler; they do not establish a freshly staged complete SDK or Apple execution. A fresh exact-source SDK/Host, affected Apple tests, original paired-product fixtures, three new signing roles, signed product validation and applicable OS/physical-device surface checks remain required. Prior-source native results are not relabeled as this candidate's acceptance.

Two original failure logs contain terminal trailing whitespace. They are stored as deterministic gzip files; compressed-original-logs.json records their original paths and byte hashes. Decompression restores the exact original log bytes.
