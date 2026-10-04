# Hanlin Real Platform & Environmental Limitations

**Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `codex/agent-skills-embedded-results`  
**Document Purpose:** Record verified technical limitations imposed by iOS platform architecture, hardware capabilities, or external requirements. Every item is backed by technical evidence. No artificial Hanlin policy limitation is disguised as a platform constraint.

---

## 1. Verified Platform Limitations

| Limitation ID | Category | Description | Technical Evidence & Root Cause | Affected Scenarios / Runtimes |
|---|---|---|---|---|
| `LIM-01` | Operating System | **Process Spawning on iOS:** iOS prohibits unprivileged user applications from calling `fork()` / `posix_spawn()` to spawn arbitrary subprocesses. | Apple iOS sandbox security model; PEP 730 iOS specification. Attempting `fork()` terminates the caller process. | Subprocess execution in Node (`child_process.spawn`) and Python (`subprocess.Popen`). In-process execution through NodeMobile and ios_system is used instead. |
| `LIM-02` | Dynamic Linking | **Arbitrary Native Shared Objects (`.so`, `.dylib`, `.node`):** iOS requires all executable Mach-O code to be signed and embedded in the app bundle at install time. Dynamic downloading and loading of unsigned native binaries via `dlopen()` is prohibited. | iOS kernel code-signing validation. Wheels or npm packages containing unbundled native C/C++ extensions cannot load dynamically unless compiled into the app. | Native Python wheels (e.g., numpy with custom C extensions not pre-compiled), Node `.node` native addons. Pure Python (`py3-none-any`) and pure JS packages function normally. |
| `LIM-03` | Hardware / OS | **Apple Foundation Models On-Device Requirements:** Apple Intelligence (`SystemLanguageModel`) requires supported Apple Silicon hardware (A17 Pro, M-series chips or newer) and iOS 27. | Apple Developer Foundation Models documentation. Unsupported hardware or simulator without on-device model weights reports `LanguageModelError.unavailable`. | `APPLEAI-04`, `APPLEAI-05`, `E2E-P`. Managed via typed graceful fallback to other local or remote providers without crashing. |
| `LIM-04` | External Hardware | **Physical Device Verification for iOS System Entitlements:** Certain Apple system capabilities (HealthKit, Camera, system calendar write prompts) require real physical device testing (`D` layer) with an authorized Apple Developer provisioning profile. | Apple sandbox requires real user interaction and physical device sensors. Simulator tests provide mock/simulated data. | Tests labeled `D` (Device layer). Executed via automated tests on simulator and marked `NOT_RUN` with explicit step-by-step instructions when physical device is disconnected. |

---
