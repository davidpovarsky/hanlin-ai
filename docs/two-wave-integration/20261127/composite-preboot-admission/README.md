# Composite54 preboot source admission

Original run 46000285780 on source 1ee9c457 stopped before any app build or XCTest. Its complete working-tree git diff exceeded the original 120-second bound.

The retained upstream patch is 191,005 bytes across 19 text paths, with zero binary-patch markers, matching the retained foreground working-tree status. RuntimeHostResources.zip and generated framework artifact directories are not tracked at that source. This argues against assuming a huge binary patch; it does not prove the unavailable final diff was identical.

The original source captures extra26 inputs only after fresh Simulator boot and a 70.35-second bootstatus. On the actual 3-CPU, 7,516,192,768-byte host, wired pages grew from 85,223 to 188,068 and cumulative swapouts from zero to 156,476 (16KiB pages). Independent simctl diagnostics subsequently took approximately 130 seconds (device listing timeout) and 62 seconds (listapps). Resource pressure is the supported infrastructure inference. No retained Git stack establishes the exact internal cause.

The change moves only the exact three-line RUN_EXTRA26/capture_inputs block immediately before boot, after the existing resource reads. All working-patch/index/untracked/selected-source checks, current392 SDK fingerprint, Host/toolchain binding and later source/product equality checks remain unchanged. The original 120-second bound, job/native clocks, selectors, assertions and counts are unchanged. No excluded paths, cached patch, retry or additional native probe are introduced.

source-validation.json proves the exact block move and whole-module inverse/AST equality. diagnosis.json binds the complete original archive retention receipt and individually CRC-verified members. No native test or optional repeated test was executed for this source-only sequencing repair.
