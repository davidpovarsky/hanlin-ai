# OpenUI Host binding and remaining SDK acceptance — 24 November 2026

## Source and ownership

This work starts at canonical SDK commit bea35c3c2a435d1cc5f7ce93b08a649b104bc10f, on codex/hanlin-three-waves-sdk-20261124. That merge contains latest SDK/MiniApps 788354f8e9e863eb5e4c9007a8b58ea71d028b19 and canonical Sign in with ChatGPT db7dc3a3a545bd41cf7b481bc184a6f9b19515db, retaining compatible public APIs from caa4faa509ebf5ba4164408734bb6e0dd3662203. GitHub comparison reports 214 commits ahead of PR17's older head 5c6aefa2670560447355dcb80799e40003282d70, zero behind.

The built-in ChatGPT SDK agent owns these scoped source edits. The parent integration agent owns Xcode, simulator acceptance, release, TestFlight and Asana updates. Consumer applications in other active sessions are not changed.

## Corrected source defects

### Original React tool-provider contract

The pinned, shipping @openuidev/react-lang 1.1.1 renderer calls its public provider as callTool({ name, arguments }). It interprets that provider's result as an MCP response, extracting structuredContent or text content. Its internal lang-core query manager instead calls callTool(name, arguments) and consumes the raw value.

Hanlin previously passed the same positional/raw provider to both. A React Query/Mutation supplied the request object as the name, left the second argument undefined, and reached JSON.parse(undefined) before dispatch. Even a successful raw result would not satisfy the React wrapper's result contract.

Scripts/OpenUI/tool-wire.mjs now provides the two required call signatures over one original Host message channel. React requests use the original name and arguments and receive a structuredContent envelope. The native runtime retains its original positional call, JSON argument normalization and raw Host result. A Host rejection remains a rejected promise. No tool permission, source provenance, model policy, network endpoint, parser, action interpreter or fallback changes.

The existing pinned builder regenerated the shipping asset on the dedicated Mac. Only bridge.js changed; all seven other generated files are byte-identical. Package pins and the lockfile remain unchanged.

### Embedded application identity

The original HanlinAppRichPresentation scopes message snapshots with the injected application's appIdentifier. ChatView.performRichAction previously required the literal hanlin, so legitimate rich actions in embedded applications were rejected before reaching their existing Host.

The guard now obtains the expected identifier from the existing HanlinApplicationContextRegistry for the current model container. Current conversation, message, selected-model, live-session, approval and cancellation checks remain in place. This is an identity-consistency repair, not a grant of Host authority.

## Meaningful original-app cold reopen

The existing mixed OpenUI UI test used an in-memory SwiftData fixture. It therefore could not establish restoration after a process restart.

Only the mixed test now opts into HANLIN_NATIVE_A2UI_STORE_ID=<UUID>. The existing native fixture enables this property only in its original debug/testing simulator mode. Its store is isolated under Application Support/NativeA2UIAcceptance/<UUID>/Chat.store, with CloudKit disabled. Other native fixtures retain memory-only behavior; ordinary Hanlin and the separate Phase2 fixture retain their storage selection.

The existing selector remains:

AI_HLYUITests/HanlinNativeA2UIChatUITests/testOriginalMixedOpenUIReactAndNativeShareStateAndKeepDraft

It retains the original real React/native controls, native-to-React value 7, React-to-native value 9, single provider request for local edits, original Host continuation and unsent draft assertions. It then terminates and relaunches the process and checks:

- the same original conversation identity;
- both renderer controls restored to 9;
- surrounding Markdown, computed budget/nights and continuation text;
- the unsent draft;
- zero new intercepted provider requests after relaunch.

The persisted state must come from the original message snapshot. No fixture snapshot or post-launch state is injected.

## Executed verification

The bounded Mac Node slot ran once in /Users/m1/builds/hanlin-three-waves-openui-20261124. Its 12 explicitly staged original/current inputs were SHA256 verified before execution and unchanged afterward. Node was 24.5.0, npm 11.5.1; no Swift, Xcode or simulator process was started by this agent.

| Check | Actual result |
| --- | --- |
| Locked npm ci --ignore-scripts --no-audit --no-fund | Exit 0, 3.889 seconds |
| node --test tool-wire.test.mjs | 4 passed, 0 failed/skipped, process 0.099 seconds |
| Existing node build.mjs | Exit 0, 2.265 seconds |
| Output comparison with canonical source | Only the expected shipping bridge.js differs |
| Scoped Git whitespace/error check | Pass |

The four new checks cover original React/MCP requests and structured results, the unchanged native positional/raw contract, omitted React arguments, and rejected original Host permissions through both adapters.

Raw logs, input/output hashes, capacity observations and command receipt are in [evidence/openui-host-wire-20261124](evidence/openui-host-wire-20261124/). Shipping bridge.js SHA256 is a1e800746e8281f6e487a0dc279e502bda9d2ae35c5a910a19a28375f9b1c9de.

## Exact pending native checks and impact

AI_HLYTests/HanlinOpenUIBridgeTests contains two parameter cases, React and SwiftUI. Each loads the actual shipping OpenUI bundle in WebKit, executes the original upstream Query, verifies the exact Host request, and requires the returned value to reach actual React text or the upstream evaluated native tree. Its Host response is explicitly a boundary fixture, not a live business-action proof.

That new suite and the extended mixed UI selector are **NOT_RUN** at this source handoff. The Swift changes have not yet been Xcode compiled. The parent owns their execution on the integrated source and the ordinary app archive.

The changed dependency closure is the OpenUI tool bridge and generated renderer bundle, the current app's rich-action identity guard, and the opt-in native acceptance store/test. Original renderer-state parsing/evaluation, catalog prompts, package locks, private SDK stores and provider algorithms are unchanged. Previously passed tests must retain their own source/environment provenance. This packet does not convert old failures, skipped tests or build-only passes into current execution.

## Task-by-task completion obligations

This table records the original task scope beyond the historical 37 failed/missing app invocations. It does not close any Asana task.

| Task | Implemented/current evidence | Remaining acceptance or separately owned work |
| --- | --- | --- |
| [OPENUI-01](https://app.asana.com/0/0/1220596988729175) | Original React bundle and native SwiftUI rendering, mixed stream, model-selected target, per-message shared store, existing Host actions and durable snapshot source; this patch repairs React tool binding and embedded identity | Execute the two original-bundle cases and mixed/cold-reopen app case. Confirm original iPad interaction/RTL and existing model-selected output during the owner’s TestFlight checks. |
| [SDK-02 core](https://app.asana.com/0/0/1220542419128390) | One existing SwiftAISDK engine and injected provider/Host ports. Native15 run45292176348 recorded15 actual passes on e325147a/SwiftAI07431abcc; its old lock-drift result stays BLOCKED. Exact-pin build-only follow-up45303091700 at f428747a is completed/success per original run/job metadata | Preserve original Native15 evidence separately from the successful zero-test build. Real eligible SystemLanguageModel generation/availability/cancellation remains a separate device obligation. Shipping native tool gates remain closed; deterministic executor cases are not live system-model execution. Final standalone import/app/provider acceptance belongs to the integrated source. |
| [SDK-03 Host](https://app.asana.com/0/0/1220542199992529) | Existing typed Host API1.2, scoped schema/authority dispatch, cancellation/revocation checks, receipts and exact scene acknowledgement. Original host navigation run44567189233 recorded58 source-qualified passes | Actual host context/action/scene behavior remains bound to each consumer owner and its exact pin. The embedded rich-action identity repair needs native integration evidence; no external consumer or business store was upgraded here. |
| [SDK-05 data/security](https://app.asana.com/0/0/1220542199999956) | Current original SwiftData conversation writer plus credential, memory and attachment ports. Existing tests cover namespace/epoch/credential boundaries, original disk reopen, clear-history rollback and retained ownership. Canonical bea35c3 carries the already accepted Darwin system-alias repair (8 persistence scenarios), plus16 native SIWC contract checks | Signed Keychain/access-group/file-protection behavior, real account/CloudKit transitions and physical-device claims require their own evidence. The SDK private single-actor store explicitly does not promise concurrent cross-process App Group writing. No speculative migration, entitlement or data rewrite is introduced. |
| [SDK parent](https://app.asana.com/0/0/1219613181643838) | Current consolidated source is newer than PR17 and the historical SDK handoff. Existing implementation-product/source evidence and original accepted host results remain traceable | Successful original app/release gates, qualified Native distribution artifacts and coordinated final consumer pin adoption are separate obligations. A source merge, Node pass or TestFlight upload alone does not satisfy all SDK/host/device requirements. |

The latest old Main37 packet, run45292517683 at a051e6a, proves a full app/test build and resource/localization checks but zero executed tests: its pre-test Git context command timed out. Its 37 cases remain NOT_RUN in that run. Current original cases are needed where missing/affected; this handoff does not request replay of unrelated authenticated passes.

No OpenUI output-repair system, model allowlist, replacement agent, parser, network backend or general QA framework was added.
