# Focused native chat regression host

This is a small UIKit-hosted XCTest target for the regressions reported in
TestFlight 145801. It imports the actual Hanlin presentation package and its
actual pinned Markdown dependency; it does not build or initialize Runtime,
providers, accounts, cloud services, or the main application's startup graph.

`prepare.py` materializes the exact shipped Composer source from immutable
commit `de9ccac5d38c44f597b2a057701de4757587d6a8` in a separate baseline module.
It preserves the source bytes and records their hash beside the candidate hash.
The baseline remains generated and is not a parallel production implementation.

From this directory on the selected stable Apple runner:

```sh
python3 prepare.py
xcodegen generate --spec project.yml
xcodebuild test -project HanlinChatRegression.xcodeproj \
  -scheme HanlinChatRegression -configuration Debug \
  -destination "platform=iOS Simulator,id=$HANLIN_PROBE_DEVICE" \
  -derivedDataPath DerivedData -resultBundlePath evidence/results.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

The caller must select and boot one owned iPad Simulator with bounded commands.
Do not use global device inventory loops or run this target during TestFlight
upload. This source/renderer-specific probe is separate from release.

The Composer test records 12 native window PNGs and 12 actual-layout JSON
attachments: baseline and candidate at wide/narrow widths, LTR/RTL, empty,
multiline and expanded draft heights, and a moved parent origin. It asserts
that content frames stay identical and native hit testing reaches the actual
UITextView and four UIButton targets beneath the panel material. **Inspect the PNGs:** geometry checks alone
cannot establish a Liquid Glass connection or visual acceptance.

The fixture supplies a native editor and control row to isolate the actual
glass shell and touch routing. It does not claim to validate the application's editor gestures,
keyboard, tool services, or physical iPad behavior. Renderer tests exercise the
real TextKit 2 attachment provider, parser, hosting and source selection.

The same native test also records the production activity label in expanded and
collapsed states. Its active sweep belongs to the visible child or parent,
respectively. These are visual style captures; runtime activity transitions are
verified by the separate state checks.

The existing unsigned-IPA workflow dispatch group `chat_regression_native` runs
`run_native.py` as an isolated pre-upload job. It stages only this harness and
the actual presentation package under the runner's temporary directory. First
it executes the provider lookup method against the immutable 145801 renderer
pin; only its specific generic-provider assertion is an expected baseline
failure. Then it restores the candidate manifest bytes and executes all four
native test methods. Build failures, timeouts, missing tests and other baseline
failures are errors. All other workflow options must remain false/empty.

The runner retains source receipts, exact resolved renderer revisions, logs,
both complete xcresults and all exported PNG/JSON attachments under
`build/chat-regression-native-evidence`. It shuts down and deletes only the one
simulator whose creation receipt belongs to that job.
