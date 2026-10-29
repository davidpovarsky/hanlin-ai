# Hanlin AI — Dual Native Widget Engines: Baseline & Source Ref Ledger

**Date:** 29 October 2026  
**Repository Remote:** `https://github.com/davidpovarsky/hanlin-ai`  
**Active Integration Branch:** `integration/hanlin-dual-widget-engines-20261029`  

## 1. Verified Source Refs & Integration Topology

| Component / Track | Upstream / Origin Ref | Integrated Commit SHA | Role / Responsibility |
| --- | --- | --- | --- |
| **Hanlin Integrated Base** | `origin/integration/expo-nativescript-search-20261029` | `333352ac251767b8b42e6ccdf37dbcdc7ae49149` | Merged Expo + NativeScript + Searchable history (PR #3) |
| **Classic Chat Restoration & Agent SDK** | `origin/fix/classic-source-first-agent-acceptance-20261025` | `9bf36a0b97f41687853fc0e3e37e9507c7fa7d0b` | Restored classic Chat UI, SwiftAISDK, composer popover, tool presentation |
| **Runtime Auto-Lifecycle** | `origin/fix/runtime-autolifecycle-20261028` | `5a0168f8beec277ddd7091fbaf9ddbc5e87b664f` | Auto-start engines, reconnect Node host, eliminate manual toggle switches |
| **Triple Integration Head** | `integration/hanlin-dual-widget-engines-20261029` | `098a1d06377e6827fc430c45dae65c01b1c313a4` | Non-destructive merge of Chat + Runtime on top of Integrated Base |
| **Known-Good On-Device Baseline** | TestFlight Build 86201 / Sefaria 1.1.2 | `62ee5ed19ac081d50071c2512d1824e7da2e9b5a` | Working direct native SwiftUI `List`/`TextField` + NativeScript `NSURLSession` |
| **ScriptWidget Upstream Source** | `everettjf/scriptwidget` `main` | `68f04194f00222558c44d5a832e7617a96f62574` | Immutable upstream ref for 29 native SwiftUI tags, JSX runtime, and elements |
| **Expo Monorepo Reference** | `expo/expo` `main` | `c73eacd6b81cb742d53f88102971ec2a72b2fa8a` | Upstream reference for Expo Widgets JSC runtime, ViewRenderer, and dynamic layout registry |
| **Hanlin Pinned Expo Stack** | `Packages/HanlinExpoRuntime`, `Scripts/Expo` | Expo 58.0.3 / RN 0.88.0 / React 19.3.0 | Compatible native XCFramework closure |

## 2. Triple Integration Reconciliation Notes

1. **`AI_HLY/Downstream/RuntimeCore/Node/NodeRuntimeService.swift`**:
   - Integrated `inferModuleKind(for:)` (ESM vs CommonJS detection from Chat branch).
   - Integrated resilient auto-launch, reconnect, non-blocking cancellation, and process-exit tracking (`NodeRuntimeBridge.didExit`).
2. **`AI_HLYUITests/AgentRuntimeConversationUITests.swift`**:
   - Preserved real chat UI tool execution/activity assertions.
   - Preserved observational runtime diagnostics (verifying `waitForRuntimeReady` without manual switch toggles).

## 3. Conflict Reconciliation Against Historical `main`

Historical `main` (`454bd90c463e77ada9fa8290246d19fc2c7ca0e1`) conflicts in 13 documentation, rule, and workflow files remain unmerged per mandate §0.2. No merge into `main` will be performed during this work; isolated development and verification occur strictly on `integration/hanlin-dual-widget-engines-20261029`.
