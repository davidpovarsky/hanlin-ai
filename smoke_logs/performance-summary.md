# 📊 iPad Performance & Regression Baseline Report

### Test Execution Environment
| Property | Value |
| --- | --- |
| **Simulator Platform** | iOS 26 Simulator (iPad, arm64) |
| **Build Configuration** | `Release` (with `ENABLE_TESTABILITY=YES`) |
| **Toolchain** | 26.6 |
| **Architecture** | arm64 |
| **Sampling Strategy** | Multi-sample repeated measurement (N=5) |

> [!NOTE]
> **All hard regression invariants passed.** Informational timings establish the multi-sample current baseline.

*No performance benchmark samples recorded in this validation run.*


### XCTest Instrumentation & Metrics Governance

| Metric | Utilized in Suite? | Operational Role & Rationale |
| --- | :---: | --- |
| **`XCTApplicationLaunchMetric`** | **Yes** | Measures process cold startup duration until the initial scene is responsive (Flow 1). |
| **`XCTClockMetric`** | **Yes** | Measures monotonic elapsed wall-clock latency across repeated sample iterations for navigation, compilation, runtime switching, and UI interaction. |
| **`XCTCPUMetric`** | **Yes** | Measures multi-threaded CPU execution time. CPU results are XCTest metrics tracked as informational baselines under virtualized runner load. |
| **`XCTMemoryMetric`** | **Yes** | Tracks memory footprint delta during XCTest measurement blocks. Memory results are XCTest metrics kept informational alongside the dedicated 50-cycle physical footprint hard gate. |
| **`os.OSSignposter`** | **Yes** | High-precision signpost intervals emitted by `HanlinScriptingPerformanceSignposts` around package loading, compilation, and scripting provider invocation. |
| **`XCTHitchMetric`** | **No** | **Reason not used:** Designed for scroll hitches and display frame presentation glitches on physical displays. On headless virtualized macOS CI runners, display refresh cycles are virtualized without a real hardware v-sync rasterizer or display engine, making frame hitch metrics non-authoritative, highly noisy, and dominated by host runner virtualization jitter rather than app rendering performance. |
| **`XCTStorageMetric`** | **No** | **Reason not used:** Measures raw on-disk volume byte delta during test execution. In this suite, storage import and persistence are measured with exact deterministic verification (`HanlinScriptPackageLoader`) and timing, while memory stability is tracked via Mach physical footprint (`TASK_VM_INFO.phys_footprint`). `XCTStorageMetric` on simulator writes across the shared host container and APFS temp volumes fluctuates due to Xcode derived data and simulator diagnostic logging, making it unstable as an isolated regression gate. |

**Performance Artifacts**:
- Structured JSON Summary: `performance-summary.json`
- Markdown Step Summary: `performance-summary.md`

### Simulator vs. Physical iPad Limitation Notice

**What this suite can prove well:**
- Relative performance regressions under comparable CI conditions;
- Launch/runtime/render timing trends across commits;
- CPU/memory/hitch trends large enough to exceed hosted-runner noise;
- Correctness under repeated lifecycle operations.

**What it cannot prove exactly:**
- Physical iPad A/M-series absolute CPU/GPU speed;
- Device thermals/throttling behavior under continuous sustained load;
- Battery/energy impact with real hardware accuracy;
- Exact real-device memory pressure under low-memory jetsam conditions;
- Hardware/sensor/camera-specific latency and throughput;
- Real physical cellular/Wi-Fi radio conditions.

