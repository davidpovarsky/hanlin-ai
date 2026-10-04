# Swift AI SDK Fork Patch Queue

**Repository:** `https://github.com/davidpovarsky/swift-ai-sdk.git`  
**Base Upstream:** `https://github.com/teunlao/swift-ai-sdk.git` (`v0.19.0` baseline, commit `df3e071`)  
**Pinned Revision:** `43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6`  
**Fork delta:** 13 commits ahead, 0 behind upstream baseline.

---

## 1. Patch Inventory and Purpose

| Commit SHA | Commit Title | Category | Hanlin Use Case / Bug Fixed | Upstream Disposition | Can Drop? |
|---|---|---|---|---|---|
| `392b7d8` | `fix(cross-platform): guard CoreFoundation and CoreGraphics for non-Apple platforms` | Portability | Enables compilation and testing on Linux and Windows CI/dev environments where Apple-only frameworks are unavailable. | Candidate for upstream PR (cross-platform Swift support). | No (needed for host test / cross-platform checks) |
| `3c60b34` | `fix(cross-platform): guard CFGetTypeID in provider utils and zod parser` | Portability | Avoids hard CFGetTypeID dependency on non-Darwin platforms. | Candidate for upstream PR. | No |
| `302a2f5` | `fix(cross-platform): add conditional FoundationNetworking import for non-Apple platforms` | Portability | Required by Foundation on non-Darwin platforms. | Standard Swift cross-platform pattern. | No |
| `46a0f5d` | `fix(cross-platform): guard URLSession.bytes and AsyncBytes for Darwin platforms only` | Portability | Guards platform-specific URLSession async stream APIs. | Candidate for upstream PR. | No |
| `6f0b336` | `fix(cross-platform): provide pure Swift IPv4/IPv6 validation fallback for non-POSIX platforms` | Portability | Fixes socket / POSIX IP validation on Windows host. | Candidate for upstream PR. | No |
| `c690a4c` | `fix(cross-platform): guard CryptoKit and Security imports for Darwin platforms only` | Portability | Guards Apple Security framework references. | Candidate for upstream PR. | No |
| `02c5e32` | `Guard UniformTypeIdentifiers import and usage for non-Apple platforms` | Portability | Guards UTType imports on non-Darwin platforms. | Candidate for upstream PR. | No |
| `b24c1ee` | `Guard URLSession.bytes and AsyncBytes for Darwin platforms in MCP transports and OpenAI provider` | Portability | Ensures MCP transport and provider compile portably. | Candidate for upstream PR. | No |
| `eff02ee` | `Explicitly type CheckedContinuation in OpenAIProvider for non-Darwin platforms` | Concurrency | Resolves Swift 6 compiler type disambiguation on non-Darwin platforms. | Candidate for upstream PR. | No |
| `038e251` | `Provide portable pure Swift SHA-256 and pkceChallenge fallback for non-Apple platforms` | Portability | Pure-Swift SHA-256 fallback when CryptoKit is unavailable. | Candidate for upstream PR. | No |
| `ec4cdfc` | `feat(openai-compatible): preserve reasoning_details opaque state during stream and prompt conversion` | Feature | Preserves provider-surfaced reasoning (`reasoning_details`) throughout SSE streaming deltas and multi-turn continuations. Essential for DeepSeek R1 / OpenRouter reasoning visibility in Hanlin. | Candidate for upstream PR. Upstream currently drops opaque reasoning structures in some OpenAI-compatible endpoints. | No (critical for Hanlin reasoning stream) |
| `64d7a09` | `test(openai-compatible): strengthen reasoning_details tests with rich opaque equality assertions and full continuation round-trip` | Testing | Conformance and regression suite validating opaque reasoning data across agent rounds. | Belongs with `ec4cdfc`. | No |
| `43ebcfa` | `fix(test): correct LanguageModelV4ToolCallPart input and ToolResultPart output types` | Testing | Corrects unit test fixture typing in Swift AI SDK suite under strict Swift 6 concurrency. | Candidate for upstream PR. | No |

---

## 2. Fork Maintenance Rules

1. **Keep pinned to immutable revisions or tags:** Hanlin's `Package.swift` references the fork via an immutable revision SHA (`43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6`) rather than a floating branch.
2. **Never vendor SDK source into Hanlin directly:** The SDK must remain an external SwiftPM dependency.
3. **Upstream PR submission:** Upstream patches in 2 batches:
   - Batch A: Non-Darwin portability guards (`392b7d8` .. `038e251`).
   - Batch B: `reasoning_details` preservation and test suite (`ec4cdfc`, `64d7a09`).
4. **Drift monitoring:** When upstream `teunlao/swift-ai-sdk` tags a new release, evaluate diff, rebase Hanlin patches onto upstream, test with `HanlinPlatformTests`, and update the pin. Never auto-merge without running the Hanlin test matrix.
