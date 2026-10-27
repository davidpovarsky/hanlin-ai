# Acceptance & CI Verification Matrix (`G8`, `G9`)

- **Repository**: `davidpovarsky/hanlin-ai`
- **Branch**: `fix/classic-source-first-agent-acceptance-20261025`
- **Original Baseline SHA**: `478cdd2c23ae2b1a52044cff52ce720830128ea2`
- **Literal Restore Checkpoint SHA**: `83ad2725d5d5eb600dc6613f4264461613eeb10e`

---

## 1. Local Preflight & Regression Suites (Executed on Workstation)

| Suite / Command | Scope | Result | Status |
|---|---|---|---|
| `python -m unittest discover -s Scripts/CI/Tests -p "test_*.py" -v` | CI affected-validation router, cache keys, modular header staging, simulator fixture staging | `147/147` passed (`1` skipped) in `6.63s` | `EXECUTED_PASS` |
| `python -m unittest discover -s Scripts/Runtime/Tests -p "test_*.py" -v` | `ios_system` runner, runtime tooling acceptance parser, dyld closure, shell workflow | `43/43` passed in `0.90s` | `EXECUTED_PASS` |
| `node Scripts/Runtime/validate-runtime-lock.mjs` | `RuntimeDependencies.lock.json` integrity | Validated `RuntimeDependencies.lock.json` | `EXECUTED_PASS` |
| Node regex sanitizer verification (`server-worker.mjs`) | `sanitizeUnicodePropertyRegexes` + `installRegExpUnicodeShim()` on `/[\P{ASCII}]/u`, `/[^\P{ASCII}]/gu`, `/\p{ASCII}/u` | Transformed to valid ASCII hex ranges `[\u0080-\uFFFF]` & `[\x00-\x7F]`; `RegExp` test passed | `EXECUTED_PASS` |

---

## 2. Swift Package & App Test Suites (Targeted for CI Execution)

| Target / Suite | Test Selectors | Coverage |
|---|---|---|
| `HanlinChatCoreTests` (`Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAISDKTests.swift`) | `HanlinAISDKTests` (`16` tests including `testNonPositiveMaxStepsClampedToAtLeastOne`, `testSourceAndFileStreamEventMapping`, `testMultimodalUserMessagePartsPreserved`) | Provider factory, `SwiftAISDK.streamText` multi-step loop, parallel tool calls, `prepareStep` dynamic tool filtering, 40-step cap, `maxSteps <= 0` guard, `.source`/`.file` stream events, multimodal user message parts |
| `AI_HLYTests/ClassicChatRestorationTests.swift` | `ClassicChatRestorationTests` (`22` tests including `16..22` for multimodal SDK conversion, `ClassicChatAgentProjection`, Build 84001 defects `7A..7D`) | Literal classic UI restoration (`ChatBubbleView`, `ChatViewBottom`, `ListView`), `ClassicChatAgentProjection`, multimodal `convertFormattedMessagesToSDKMessages`, Skill-vs-Tool disambiguation (`web_research` vs `search_online`), MCP package validation, `pwd` shell builtin, CommonJS `require()` inference, schema byte budget (`24,000` / `28,000` bytes) |
| `AI_HLYTests/AgentRuntimeConversationAcceptanceTests.swift` | `AgentRuntimeConversationAcceptanceTests` | End-to-end `APIManager.sendStreamRequest` -> `processSDKAgentEngine` multi-round Python/JS/TS/Shell, `load_skill` + same-turn tool call, error recovery, cancellation isolation |
| `AI_HLYUITests/AgentRuntimeConversationUITests.swift` | `AgentRuntimeConversationUITests` (`UI-01..UI-08` + runtime & cancellation E2E) | Classic `ListView`, `ChatBubbleView` (`userMessageView`, `assistantMessageView`, `searchMessageView`, `reasoningView`, `toolContentView`, `codeBubble`, `htmlBubble`), original blue `ChatViewBottom`, Stop/Retry recovery, conversational MCP 2-turn lifecycle |
| `AI_HLYTests/LiveProviderMatrixConformanceTests.swift` | `LiveProviderMatrixConformanceTests` (`77` parameterized live external provider tests) | Gated by `HANLIN_RUN_LIVE_PROVIDER_TESTS=1` and external commercial API keys (`LIVE_PROVIDER_BLOCKED` / `NOT_RUN` when keys are absent in CI) |
| Physical iPad Verification | Real iPad hardware check | `DEVICE_PENDING` until verified on physical iPad hardware |
