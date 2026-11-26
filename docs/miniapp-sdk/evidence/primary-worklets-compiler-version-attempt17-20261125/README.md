# Original Worklets compiler version correction

The finalized attempt17 simulator output reported a Worklets native/JavaScript mismatch. This record binds that observation to the actual retained native compiler response files and object, the original npm publication, the reviewed production correction, and two focused portable contract tests.

The original package, exact dependency lock and SDK16 JavaScript all identify Worklets 0.13.0. The authored SwiftPM target supplied a quoted 0.13.1 macro. The original C++ source stringizes its macro, so the retained native object contains the literal value with quotation marks. The original podspec supplies a bare version token; the correction follows that existing upstream format and the exact selected package version.

## Source correction

Commit 20de36b7 changes only the authored local native Package.swift, original upstream resolver, shared runtime audit and its test module. Future resolution updates the local compiler definition through the existing write/rollback set, followed by the existing canonical root manifest generator. The audit checks both local and generated root declarations against the same original graph and rejects quoted, stale, missing or duplicate flags. Original package bodies, public APIs, locks, runtime version comparison and C++ code remain unchanged.

Commit 683a9601 separately synchronizes the canonical Generated/SwiftUIBridge Swift file with the already reviewed packaged mirror and original generator output fragment. It adds no generated Apple API surface.

## Actual evidence

The eight Worklets files selected from the immutable native transfer receipt are retained. The object is losslessly compressed with its original hash and size bound in the receipt. The three unrelated storage rows in that original transfer receipt are intentionally outside this record.

The first portable attempt had one pass and one failure: the existing canonical generated-mirror guard detected the missing mirror update. Its original log and receipt remain unchanged. After the exact mirror synchronization and bare-token correction, the two focused contract cases passed with zero failures or skips. These candidate tests explicitly supply child/root manifest text to the actual audit; they do not claim native compilation or actual root generation.

The existing full eight-case module must run once after the normal producer regenerates the real root Package.swift. The normal Host audit invokes the production contract, while the Host package test glob does not select this separate test module. Native recompilation, fresh SDK/consumer binding and affected application execution remain pending in this frozen record.

See analysis.json for all source before/after hashes, original publication/member identities, raw object byte offset, test results and required normal producer closure. SDK16 is the historical baseline; it is not presented as the SDK after this correction.
