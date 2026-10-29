# HANLIN — Classic Source-First Chat Restoration & Agent Capability Acceptance Matrix

> **2026-10-27 Update:**
> This file has been updated to reflect the 2026-10-27 literal restoration of all five original chat files (`478cdd2c23ae2b1a52044cff52ce720830128ea2` -> Step 1 checkpoint `83ad2725d5d5eb600dc6613f4264461613eeb10e`) and complete `SwiftAISDK.streamText` cutover.
> Full current acceptance and CI details are maintained in `docs/hanlin-original-ui-restoration/ACCEPTANCE_AND_CI_MATRIX.md`.

---

## Historical Archive (2026-10-26 Runs Prior to 2026-10-27 Literal `ChatViewBottom` Restoration)
- Commit `2620d01814e74e6602562a3c6b10af9c04f2bc00` — Run `40307800961` (`176/176` `AI_HLYTests` passed; `1/1` `HanlinRuntimeInstallationUITests` passed).
- Commit `b323eec082b4cfe794b3aeb7641d96502d4924b6` — Run `40316311859` (`176/176` `AI_HLYTests` passed).
- Commit `f62290e0c54a81b94166594ea204f6484856cd40` — Run `40322217987` (`11/11` `AgentRuntimeConversationUITests` passed against the 2026-10-26 branch state; superseded by the 2026-10-27 literal restoration).

## Current 2026-10-27 Literal Restoration Test Matrix
See `docs/hanlin-original-ui-restoration/ACCEPTANCE_AND_CI_MATRIX.md` for the complete test matrix covering:
1. `Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAISDKTests.swift` (`16` tests)
2. `AI_HLYTests/ClassicChatRestorationTests.swift` (`22` tests)
3. `AI_HLYTests/AgentRuntimeConversationAcceptanceTests.swift`
4. `AI_HLYUITests/AgentRuntimeConversationUITests.swift`
5. `AI_HLYTests/LiveProviderMatrixConformanceTests.swift` (`77` live commercial provider tests — `NOT_RUN` / `LIVE_PROVIDER_BLOCKED` without external API keys in CI)
