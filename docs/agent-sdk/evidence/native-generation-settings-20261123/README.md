# Native generation settings propagation — 2026-11-23

The original application path accepted caller temperature, top-P and token-limit values but discarded them at the native catalog adapter. This repair forwards those three values into the existing immutable Hanlin configuration. Native catalog identity, readiness, provider validation, the shared agent engine and provider implementation remain unchanged. Defaults retain the original -999/-999/2048 semantics. Explicit unsupported top-P reaches the existing provider error before a native session is created.

## Change and source evidence

Only AI_HLY/Model/HanlinAppleModelCatalogAdapter.swift and AI_HLY/Services/ChatServices/APIManager.swift change in production. The adapter's internal generation builder copies the original native identity/capabilities and applies caller settings through the original configuration initializer. The existing catalog validation and actual-availability guard still execute in the original public application route. APIManager differs only at the three-argument call. Existing test bodies are byte-identical after removing the two new cases and their required import. Exact input hashes and bounded source checks are recorded in receipt.json.

## Focused acceptance

Two new methods in the original ModelPopoverZoomOrderTests suite test default preservation/custom temperature and token limits, and actual HanlinAISDKAgentEngine plus HanlinAppleLanguageModel rejection of explicit top-P. The second test uses the original production provider, no substitute; a prerequisite requires that top-P survived configuration before entering the provider, which rejects it before availability or session creation. The pinned SwiftAISDK nonretryable error path was inspected to bind the exact typed error expectation.

Both Apple tests are NOT_RUN here. All three changed Swift files passed Swift 6 frontend syntax parsing on Oracle; that is neither Apple typechecking nor behavioral execution. The parent will include only these two newly necessary methods in the existing native continuation. Previously passed tests were not replayed. Actual eligible-device availability/text generation/cancellation and lossless native tool orchestration remain separate SDK02 acceptance items; this change claims none of them.

## Actual consumer impact

The installed SDK32da receipts for Maktabah, Lorvex and Anytype retain the same selected source paths. Neither changed application production file is in any of the three profiles. The four production files from the parent's separate32b3168d callback/import repair are also outside all three selections. Each exact membership result is recorded. All22 previously identified generator inputs have identical path/mode/blob records between32da and32b; no generator or consumer suite ran for this check. Old device/UI passes keep their original source attribution.
