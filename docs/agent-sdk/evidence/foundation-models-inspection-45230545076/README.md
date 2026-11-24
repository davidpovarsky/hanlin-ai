# Installed FoundationModels API and host availability — 45230545076

## Observed result

The bounded availability query **PASS** means that the official framework compiled and returned its availability property. The actual value is **`deviceNotEligible`**. This GitHub runner does not provide eligible local-model execution. Model generation and tool execution are **NOT_RUN**; tool capability is **NOT_QUERIED**. No iOS Simulator or physical-device availability result is inferred from this macOS observation.

- Original [run 45230545076](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076), exact source `7523f45cf8ea180a8e30f511ff0fbd3bb5ccae6d`.
- Unique [artifact 14847222630](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076/artifacts/14847222630), `hanlin-foundation-models-interface`, 29,954 bytes.
- Archive SHA256 `2d9b488d5379041733f3a5a4e4bab68cf832e40caee4bfe2eacf153619413e64`, authenticated GitHub digest/size/run/source match and all ZIP CRCs PASS. Downloaded once; original bytes retained here.
- Xcode 27.2 (27B52), Apple Swift 6.4.2, actual macOS host 27.0.1 (26A434), arm64; availability program compiled with the installed macOS 27.2 SDK.

The outer run was still `in_progress` at acquisition. This independently completed diagnostic is not a native producer, application build, selected-test, or release acceptance claim. Native publication remains gated on the completed successful original producer.

## Exact sources and retained evidence

The declarations are from the installed **iOS Simulator** interface, `arm64-apple-ios-simulator.swiftinterface`, 217,372 bytes, SHA256 `7d29c5b8e1aa76f8b362f2b17f3b29e87418ff4f730822c3f725aa41989bed14`. The expanded original-line-numbered excerpt is 193,265 bytes, SHA256 `d1d50574ae65c19a319d7f8427944cc36a0373affcd8db3fba3fd6a3d531e2e0`, in `declarations.txt` inside the retained ZIP. The full interface hash is unchanged from the prior capture; this capture includes more declarations.

The availability program runs on the **macOS runner host**. Its source is byte-identical to `AVAILABILITY_SOURCE` in the source-pinned inspector; SHA256 `27b70911b258ba1eaa53502eef3e61f9efe594a6cdf87341fb8d104c70cdaba6`. The inspector blob has SHA256 `074697f9c4e2ca92b990e63bfcc818a3d46a79ea7f321561f1e26686d8cf5995`. All twelve retained stdout/stderr files match their nested command receipts, including the empty successful compiler output. The archive retains exact commands, time bounds, toolchain output, Swift source, query result, and ephemeral executable hash. The query calls only `SystemLanguageModel.default.availability`; it does not construct a model session, generate text, call tools, download a model, or access credentials.

The expanded interface establishes public `Transcript.ToolDefinition`, `Transcript.ToolCall`, `Transcript.ToolOutput`, dynamic schema, and hook signatures for the separate adapter implementation review. It confirms that `GeneratedContent.Kind.number` carries a `Double`; reserialization is not evidence of original numeric JSON. `ToolCallingMode` declares allowed/required/disallowed, without a manual-call mode. Public declarations alone do not prove hook ordering, pre-effect handoff, continuation, multi-call behavior, cancellation, or host authorization. Those runtime obligations remain open on eligible hardware.

`verification.json` records each original archive member hash, source binding, command-log checks, and the exact limits of this result. No existing passing tests or Apple job were replayed for this acquisition.
