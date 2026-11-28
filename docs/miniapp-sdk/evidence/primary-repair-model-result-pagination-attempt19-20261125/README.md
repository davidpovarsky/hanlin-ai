# Read the original stored tool results in the controlled repair model

The actual focused recovery on consumer `62dfff9aebd0a272486c7770d4f77ba603d535ab` completed 7 PASS / 1 FAIL in its AI group. The repair UI reached the original composer and three model requests, then the controlled model returned `MINIAPP_AUTHORING_NONJSON_RESULT_miniapp-sdk`. The later foreground assertion failed before an import had been requested. This is not evidence of an OS handoff failure.

The original `get_miniapp_sdk` Node job completed successfully. Its exact retained result payload is 13,935 UTF-8 bytes, SHA256 `ee850d95930744b63a10e9e07557e0803e48bc297e2f56df8ccb70f08c26763d`, parses as JSON and identifies the actual SDK19 manifest `4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92`. The production tool adapter correctly stored the complete eligible result and returned an opaque result reference. The model fixture incorrectly attempted to parse that reference envelope as direct JSON.

## Minimal correction

Source commit `b060fea9bd2ff59d437d420ff374f947d40734a6` changes only the existing MiniApp acceptance branch under `(DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)` in AgentRuntimeUIAcceptanceProvider.swift. It follows the original reference through real `read_tool_result` calls, using the advertised 4,096-byte pages. It verifies the exact reference, offset, declared byte counts, UTF-8 boundaries and original pagination footer, then parses the actual accumulated JSON.

The same resolution applies to every original MiniApp authoring result, since validation and build reports can also be stored. Genuine non-JSON, missing-reference and malformed-slice responses still fail. The original source repair, TS2322 check, returned sourceRoot, revalidation/build success, transfer ID and installed/nonempty-package-ID guards remain unchanged. No compiler output, edited file, archive or installation receipt is synthesized.

Production result storage, transport behavior and original tool implementations are unchanged. The dedicated read_tool_result adapter returns the original slice directly. No production result threshold or app capability restriction was changed to make this test pass.

## Evidence and impact

The full 48-file durable packet (150,882 bytes) and its untouched receipt `d159918a7c7c0758e47f54d0b1458ad42b61b3032da57d9ffebb61e8d1de9601` are retained in raw/durable. All original content lengths and hashes were independently checked. The original Mac mode metadata is preserved: 29 data files originally had mode 0600 and arrived as 0644 in the Oracle evidence transport; the remaining 19 were 0644. Content identity, not mode equality, is asserted for this transport.

The actual AI accessibility tree, full AI test log, finalized summary/nodes, original selector result and terminal charge/state are retained separately. Their untouched original 81-member packet receipt is included for provenance; only the explicitly selected terminal members listed in this evidence receipt are copied here.

The changed provider and separate image fixture are absent from all 235 declared SDK19 inputs, independently checked in the complete delivered SDK ZIP. The SDK producer remains `a2c8a1b1be746461272ba77254603304567c309d`; integrated source `6c006c948f0a6f371f7fc68b90e393f43734f8dd` contains this correction and the independently documented image fixture correction. Source-and-impact bindings and the exact provider diff are retained.

This record documents the observed failure and reviewed correction. Corrected native execution, full original 25+27 acceptance, actual OS delivery and physical-device results are separate evidence and are not inferred from this source review.
