# Original code-fence rendered-payload ownership

Source-only follow-up to published full original UI union `f3afac65296e843ced1f7ddd7a55c2452e90b270`. Apple compile, the six new ownership tests, visible previews and performance measurements are NOT_RUN. No change to the owner's active companion source, extension fix, SDK preparation or build queue is made by this source work.

## Concrete gap and scope

The original renderer bounds its cache to8 MiB/32 entries, pending work to8, input to1 MiB, decoded HTML to16 MiB, JavaScript execution to8 seconds and cold startup to30 seconds. The cache bound alone did not bound completed payloads retained by inline/expanded views or task results. Multiple rendered fences could therefore retain output after cache eviction.

The same original renderer now admits each completed payload through one shared lifetime quota: at most48 MiB of renderer-issued UTF8 HTML/CSS/display-HTML bytes and64 distinct payloads. The byte quantity is explicit; it is not WKWebView allocation, process RSS, all caller-created strings or transient JavaScript memory. The existing serialized queue independently bounds pending input and one in-flight render. A single maximum allowed decoded HTML result plus its static display document fits the global byte limit.

Each value copy shares an immutable ownership lease. Cache, inline, expanded, remounted and completed-task copies cannot prematurely release another owner's bytes. The lease releases exactly once when the final payload copy disappears. A new cache hit reuses the original lease. If capacity is exhausted, the engine first drops only its own cache references; live copies remain charged. If still full, the existing busy/error path shows the original complete source with its original copy/share/expand/retry controls. No source truncation or substitute renderer is introduced.

The public payload constructor and presentation APIs remain unchanged. The quota measures original engine-issued immutable HTML/CSS and the display document at publication; arbitrary later changes by trusted callers to the existing public displayHTML property are not claimed as tracked allocations. Actual Anytype and original code-fence view consumers do not mutate issued payloads. Static display WebKit still disables scripts, navigation, popups and persistent storage; rendering CSP/assets/dependencies are unchanged.

## Source changes and verification required

Only original `HanlinChatUI/CodeFences/ChatCodeFenceDocument.swift`, `ChatCodeFenceEngine.swift`, the new `ChatCodeFencePayloadRetention.swift`, focused `HanlinChatUITests/ChatCodeFencePayloadRetentionTests.swift` and this document change. Original AgentSDK and Platform cancellation/explicit-handler source remain unchanged. The prior SDK385 seven-case proof may retain only its exact unchanged source scope; it does not qualify these new rendering bytes.

Six authored tests cover UTF8 counting/shared inline-expanded copies; cache eviction/remount ownership; byte/count exhaustion and reuse; cancellation while unpublished work still retains its payload; distinct quota owners and overflow rejection; and concurrent reservations against one shared cap. They are source-level test additions, NOT_RUN. Actual iOS typechecking and original preview/fallback/selection/appearance behavior still require the coordinated later Apple build.

Original owner coordination is Asana comment `1220942203673046` on task `1220916800603484`. The first Anytype shared build/retry remains frozen on its separate SDK385/native8ac input. The final integrator owns all source pinning and Mac launch decisions.
