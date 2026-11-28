# Original atomic-store native acceptance — 45163990486

The existing focused scripting-package job [137656161482](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45163990486/job/137656161482) passed at exact source `32da9e314e22bbf22391fcf8902302acfbb281e2`. Both GitHub job metadata and the original checkout log bind that source.

The actual Apple runner1000024616 used Xcode27.2(27B52), Swift6.4.2 and the original `Packages/HanlinPlatform` manifest, dependencies and store/test source. Original package compilation took164.63seconds. The unchanged existing command received an exact filter; the output explicitly reports all3 methods and the two distinct `duplicatingEntry=false/true` arguments, for4 executed cases. All passed in0.096seconds. This is native macOS package acceptance, not an iOS app or device run.

| Original method | Actual cases | Outcome |
| --- | ---: | --- |
| `persistedRegistryIdentity(duplicatingEntry:)` |2| PASS: mismatch and duplicate identity reject both cold init and restore; original registry bytes and existing in-memory snapshots preserved |
| `persistedBackupRegistryIdentity()` |1| PASS: malformed selected backup rejects through the existing error; original files preserved |
| `validRegistrySelection()` |1| PASS: valid primary precedence and valid backup recovery retain original data and files |

Full original job log64,366bytes has SHA256 `4d9b7d20c0c5b130a9ba1b0f4d910bd6285c9f317b551fe46a2497f2410f2ad2`. It and the original job metadata/test-output excerpt are retained here, with exact source bindings in `receipt.json`. Existing unrelated manifest/unused-binding/test-macro warnings are recorded rather than hidden.

No prior accepted tests were replayed. SwiftPM compilation of other original test targets does not mean they executed. No live EventKit, native app, WidgetKit UI, device, artifact publication or overall SDK acceptance is inferred. The parent workflow's independent full-app26 gate is still pending at the time of this readback.
