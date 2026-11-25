# Native generation and dependency resolution for ZIPFoundation 0.9.20

Status: actual canonical generation/check and six original SwiftPM package resolutions passed. Archive runtime regression, final Maktabah consumer resolution/ownership, and application Live acceptance remain open.

The reviewed source change is 23040c6c95147d100a8729a9964bd09f984c0435, a descendant of qualified union a11c6734eba0ce9206bf80d5e981645bfbc0c73b. It changes the original HanlinPlatform ZIPFoundation requirement from exact 0.9.19 to exact 0.9.20, matching Maktabah and the single original Anytype SDK provider. No SDK implementation was copied. Core remains abf0921c6e89e6521cc2b510ff11016b45a0ef08.

## Actual Mac evidence

The exact 1,300-file source closure, including all original Platform sources/tests and the original widget fixture hierarchy, was verified on the Scaleway Mac. Archive SHA256: ed478ead1552ee767dc38023fefe75627fab21c24c3af8b06a8cd19e9c6bf129. Source-manifest SHA256: a6588d16f6f7f14d85d3258cb02e25407ff06979ef08507db9891cd32e77c6b5.

Original Scripts/SDK/generate_manifest.py and its --check passed in job_18da9b3294a6 on Xcode27.0/Swift6.4, with 523 original application sources, 114 targets and zero remaining local-package edges. The only generated changes are the root Package.swift ZIP requirement and the original Platform manifest input hash. RESULT SHA256: 2c481da9f20ecbddd10628f964523d6f5fab51ce39ee248313978e599cbb632c.

Job_ca6581793074 ran actual swift package resolve sequentially for HanlinPlatform, HanlinAgentSDK, HanlinParityMiniApp, HanlinTextStudioMiniApp, HanlinSefariaMiniApp and HanlinWikipediaMiniApp using one owned scratch directory. All six passed; every checkout matched its expected Git revision and had clean tracked files. RESULT SHA256: 76e7e6ae1ca9a89d85a1ee64539ad2b7f2d8860857e9f470c117476f950c834c.

The committed locks are the exact raw SwiftPM output, including each original originHash. They retain all unrelated old pins, change ZIPFoundation to 0.9.20/22787ffb59de99e5dc1fbfe80b19c97a904ad48d, and add the already declared OpenTelemetry2.6.0/c6fcee77cfc21ba400366f12475217c7b6e1d605 plus its Atomics1.3.1/0442cb5a3f98ab802acb777929fdb446bda11a34. These additions exactly match the qualified original app graph. No lock was hand-stamped.

Raw evidence, including both pre-execution resource-blocked generator attempts, lives in zip-alignment/native-generation-resolution-20261125/. Transfer archive SHA256: 64ed0cb5eae067a561a5431d4f699047a42c26a9bbdb60da9e1d526d399b25d1. Original files and checksums were verified again on Oracle before integration.

## Remaining affected acceptance

Run the original, unmodified HanlinPlatform archive/package/widget cases from this committed source: six PackageCenter invocations, twelve ArchivePolicy invocations and twelve real widget archive/import/install invocations, seventeen methods and thirty invocations total. Preserve individual identities, all raw results and the actual dependency graph.

The Hanlin app lock is retained at its original qualified inputs; it is not asserted to be newly resolved by these six package operations. Final Maktabah consumer resolution and SDK/host symbol ownership remain separate mandatory gates. C8/App05 and Core7 receipts retain their exact original attribution. Later upstream App07 was reported as 48/48 on 948bdb1fe75d31559dc8d65ae8d2e70fa69de276; newer App08/App09 failed and App10 is in progress. This source does not claim those later runtime results.
