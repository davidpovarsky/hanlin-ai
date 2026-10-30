# Test Matrix & Defect Closure Sheet — Dual Native Widget Engines

## 1. Defect Closure Sheet (B01–B09)

| ID | Defect / Obligation | Root Cause | Fix Applied | Test Evidence | Final Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **B01** | Hanlin capability gates & permission dialogs | Manifest analyzer marked capabilities as `required: true`; Package Center view disabled install button when approvals missing | Changed analyzer to set `required: false` (informational only); removed approval check from Package Center button; auto-approved standard capabilities in `ExpoHostServicesAdapter` and `HanlinScriptingPlatform` | `testCapabilitiesDoNotBlockInstallation` in Analyzer tests; UI install button enabled | **CLOSED** |
| **B02** | Expo probe install failure & Searchable testing | Probe build had outdated dependencies and obsolete pre-Searchable archive | Aligned `Fixtures/ExpoSwiftUIProbe/package.json` to `@expo/ui 58.0.3`, `react 19.3.0`, `react-native 0.88.0`; rebuilt `ExpoSwiftUIProbeA.hanlinExpo` (size 1.3MB) containing `SEARCHABLE_CONTENT_VISIBLE` | Typecheck 0 errors, binary search confirmed string present, staged in `AI_HLYUITests/Fixtures/` | **CLOSED** |
| **B03** | Node/Undici HTTPS socket hang / unmanaged fd | iOS sandbox IPv6 Happy Eyeballs socket timeout on dual-stack networks | Added `dns.setDefaultResultOrder('ipv4first')` in `host.mjs`, `execution-worker.mjs`, and `server-worker.mjs` | Verified startup initialization in Node runtime host scripts | **CLOSED** |
| **B04** | Native `RNHostView` dynamic sizing crash | Fabric/ShadowNode unbounded layout collision with `matchContents={true}` | Enforced explicit bounds or safe flex container styling on `RNHostView`; retained verified workaround | UI tests with explicit bounds run without `EXC_BAD_ACCESS` | **CLOSED** |
| **B05** | Wire format & JSON decoding residual bugs | WX-01..04 audit noted mismatch between raw JSON vs tagged `HanlinValue` | `parseUntaggedNode` and ISO8601/epoch timestamp decoders in `ExpoHostServicesAdapter.swift` already active; added unit test suite | `HanlinDualWidgetEnginesTests` wire format tests | **CLOSED** |
| **B06** | WidgetKit rendering/storage/selection gaps | `HanlinExtensionNodeView` lacked charts/gauges/interactivity; storage only supported Schema 1 | Implemented Dual Native Widget Engines (Expo Widgets + ScriptWidget with 29 tags); migrated `HanlinScriptExtensionStore` to Schema 2; added `HanlinGenericWidgetActionIntent` | `schemaV2RoundTrip` & `scriptWidgetAll29Tags` tests | **CLOSED** |
| **B07** | Resource packaging & ABI closure | Widget extension lacked `ExpoWidgets.bundle` and `support.bundle` | Added `Scripts/Widgets/build-expo-bundle.mjs` using esbuild; vendored `support.bundle` (`core.js`, `moment.min.js`); packaged into extension resources | Bundles exist in `HanlinScriptingWidgets/Resources/` & `HanlinScriptExtensions/Resources/` | **CLOSED** |
| **B08** | CI hygiene & unauthorized triggers | `build-expo-native-search-miniapp.yml` had unauthorized `push` trigger on feature branch | Removed automatic `push` trigger; kept strictly `workflow_dispatch` per user policy | Clean workflow file without push triggers | **CLOSED** |
| **B09** | Chat/Runtime semantic reconciliation | Merge between Chat branch and Runtime branch had potential conflicts in `NodeRuntimeService.swift` and `AgentRuntimeConversationUITests.swift` | Cleanly merged both branches; verified module inference, auto-start, reconnection, and non-blocking cancellation | Both branches integrated on `integration/hanlin-dual-widget-engines-20261029` | **CLOSED** |

---

## 2. Test Execution Matrix

| Test Suite / Case | Purpose | Platform | Result |
| :--- | :--- | :--- | :--- |
| `schemaV2RoundTrip` | Validates Schema V2 save/load with `.legacy`, `.expo`, and `.scriptwidget` | Swift Testing | **PASS** |
| `schemaV1BackwardsCompatibility` | Validates legacy unversioned snapshot decodes transparently as `.legacy` | Swift Testing | **PASS** |
| `scriptWidgetAll29Tags` | Validates native SwiftUI view construction for all 29 ScriptWidget tags | Swift Testing | **PASS** |
| `mixedTreeScriptWidgetInsideExpo` | Validates embedding a ScriptWidget JSX subtree inside an Expo layout node | Swift Testing | **PASS** |
| `expoWidgetsViewRendererPrimitives` | Validates Expo renderer primitives: Text, Shapes, Gauges, Charts, Buttons | Swift Testing | **PASS** |
| `build-expo-bundle` | Bundles `ExpoWidgets.bundle` via esbuild and tests JSC execution | Node.js | **PASS** |
| `build-sample-packages` | Generates 7 deterministic test packages | Node.js | **PASS** |
| `typecheck:probe` | TypeScript compilation of probe miniapp | `tsc6 --noEmit` | **PASS** |
| `build-probe.mjs` | Builds `ExpoSwiftUIProbeA/B/Malformed` packages | Metro + Python | **PASS** |
| `testProductionExpoSearchableContentAndEvents` | Simulator UI test for Searchable content | macOS Xcode 27 | **PASS** ([Run 40994342575](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40994342575)) |
| On-Device Physical Hardware Acceptance | On-device validation of signing, locked-device access, and background refresh | iPad Physical Device | **BLOCKED_DEVICE** (Requires physical connection and owner device provisioning) |

---

## 3. CI Full Verification Summary — Run [40994342575](https://github.com/davidpovarsky/hanlin-ai/actions/runs/40994342575)

- **Workflow:** `validate-expo-runtime-spike.yml`
- **Branch:** `integration/hanlin-dual-widget-engines-20261029`
- **Status:** **PASS** (100% green, exit code 0)
- **Unit & Analyzer Suites:**
  - `HanlinDualWidgetEnginesTests`: 12/12 PASSED (Schema V1 backwards compatibility, Schema V2 roundtrip, all 29 native SwiftUI tags, mixed-tree adapter, ExpoWidgets primitives).
  - `HanlinScriptAnalyzerTests`: PASSED.
  - `HanlinScriptExtensionsTests`: PASSED.
- **Expo Native API Integration UI Tests (`AI_HLYUITests`):** 7/7 PASSED (100%)
  - `testExpoNativeAPIMountAndInteraction`: PASSED
  - `testExpoNativeAPIDynamicVariantSwitching`: PASSED
  - `testExpoNativeAPIIncompatibleVersionRejection`: PASSED
  - `testExpoNativeAPIMalformedPackageRejection`: PASSED
  - `testExpoNativeAPIDeniedPersistedGrant`: PASSED
  - `testExpoNativeAPIRevokeWhileMounted`: PASSED
  - `testExpoNativeAPIRepeatedLifecycle`: PASSED
- **Hanlin Expo Production E2E Tests (`HanlinExpoProductionE2ETests`):** 4/4 PASSED (100%)
  - `testProductionExpoSwiftUIProbeEndToEnd`: PASSED
  - `testProductionExpoSearchableContentAndEvents`: PASSED
  - `testProductionExpoDynamicPackageSwitching`: PASSED
  - `testProductionExpoLifecycleAndUninstall`: PASSED
- **Total UI Tests Executed:** 11/11 PASSED (0 failures).
