# Native window-count expectation type

The actual f57 standalone build failed at the original window-count assertion before any UI tests. This correction changes only index + 1 to UInt(index + 1), preserving its exact values 3, 2, 1 and the same reverse-completion comparison. The actual non-system Objective-C module imports the count as UInt. No assertion or original case is removed.

The whole-file inverse and all five selectors / 131 XCTest assertion, unwrap and failure lines are preserved. Independent source review is retained verbatim.

The first real installed-header probe failed because its frontend search found Objective-C XCTest without the installed Swift overlay. That failure remains retained. The same 399-byte probe then passed against the actual iPhoneSimulator 27.0 SDK and real XCTest overlay, with the unchanged original header/module, explicit UInt return binding and the corrected real generic XCTest assertion. It executed no registry call and no tests.

The original hosted build used its own Xcode 27.2 environment; this narrow installed-SDK qualification does not replace compiling the whole corrected test file there. Original app/runtime/OS acceptance is still required. Raw original job/build/probe logs remain in the hash-bound private handoffs named in outcome.json; this compact public proof contains no private task or account data.
