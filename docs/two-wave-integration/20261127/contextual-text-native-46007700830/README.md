# Original contextual text tools native acceptance

The original single UI test passed on GitHub run 46007700830, source d165b9fc6a1c4e810a21957c063bfeae52eecb59. Job 140535130609 completed successfully at 2026-11-27T15:24:26Z. The test executed once on the owned iPad Pro 13-inch (M5), iOS Simulator 27.2, build 24B8117.

## Actual result

The original selector HanlinContextualTextToolsUITests/testOriginalTextToolsReceiveTheMessageWithoutReplacingTheConversation passed in 145.888911 seconds. The original xcodebuild test-without-building command retained its exact selector and 300-second case allowance. Its terminal exit status was zero.

The test opens each of the three original translation, polish and summary sheets, checks exact contextual message input, returns from each sheet, and checks that the original conversation message remains visible. This is one test with three tool round trips. It does not exercise provider generation or establish acceptance for other runtime or OS suites.

## Independent reconciliation

All three downloaded artifacts match their authenticated GitHub metadata SHA-256 digests. The 38,313,819-byte simulator artifact retains the original xcresult and logs. Selected result, selector, product and provenance members were read with ZIP CRC validation. The original 31,873,906-byte job log and its lossless gzip were also hash-verified without a second download.

The native result tree contains exactly one Passed Test Case. The three repeated suite summaries refer to that same case. The separate provider-conformance summary contains 78 NOT_RUN entries and zero passed tests; it contributes no additional acceptance.

The before/after manifests bind the same seven actual app and UI-test product files and the same xctestrun hash. The five directly relevant contextual UI, presentation and acceptance-fixture sources are byte-identical between the dispatched commit and comparison commit c1bb16c7d049cccdc7044e11e9e05f15ec860869.

## Effective source qualification

The original workflow intentionally resolved upstream inputs before building. Its diagnostic provenance records a modified tracked workspace, and the authenticated upstream artifact retains the exact 19-path patch and resolution. None of those paths is one of the five contextual source files compared here. The accepted build is qualified to that retained effective input set, rather than treated as a byte-identical build of every current app source.

Runtime warnings in the original result tree remain preserved. This proof neither changes a test nor claims a new execution, a complete current app rebuild, or an all-app pass.
