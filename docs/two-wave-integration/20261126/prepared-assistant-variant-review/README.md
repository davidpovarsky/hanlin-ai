# External prepared-action assistantTool variant: source review

**Decision:** retain the integrated canonical dedicated assistant-tool contract and explicit user selection for each message. Do not merge the automatic foreground-action variant.

Reviewed integrated source: `fba37e3636da21f897d6a86298b52f2149b462dd`.
External addition: `462fe5c579e3fb3d6c394c8fd368faca8792bc6e`; schema follow-up: `3c47d1a21e23c59ed807dc64a5cf9aa7f153c692`; external tip: `13bfad937c9e61e0bea839fdf1f3b5b1e7652b69`.
All five critical external files are byte-identical between the addition and that tip.

## Requirement and current route

The actual approved [Composer task](https://app.asana.com/0/0/1220882717750164) requires a dedicated assistant entry, explicit per-message attachment and configuration snapshots, no app/index fallback in chat, and no action execution merely from selection. The captured full-note SHA-256 is `9fe3676d0cfa511e4877b68b3c5a659e7a040516d5b2c045ad67099083575145`. The exact relevant numbered requirements and their separate digest are retained in [review.json](review.json).

The integrated source already has the authoring contract in `assistant-tools.d.ts`, dedicated source generation in `miniapp-assistant-tools.mjs`, request-scoped `HanlinMiniAppAssistantToolExports.tools(attachments:)` and the original `HanlinMiniAppAssistantToolRuntime`. Configuration comes from the explicit user snapshot, and the existing native/embedded-result route remains responsible for execution.

## Three concrete differences

| Area | Integrated canonical route | External variant and integration consequence |
| --- | --- | --- |
| Message selection | The bridge contributes MiniApp tools from `scope.capabilityAttachments`, validating the selected installation, entrypoint, action and configuration. | Initial preparation and refresh call `catalogContribution()` without the message attachments and append all enabled prepared declarations. That does not preserve the required explicit exposure boundary. |
| Source ownership | A dedicated assistant source/bundle is separate from the foreground app entry; current exports reject sharing the app bundle directory. | The new declaration requires `prepared-foreground-action-v1` and the same source path as the app entry. This additional foreground-action contract cannot replace the required dedicated entry. |
| Existing declaration compatibility | Current declarations contain assistant metadata/actions/configuration and use `prepared-assistant-tool-v1`. | Both the Host validator and analyzer iterate all assistantTool entries and require the new foreground/exportedSymbol form. A straight cumulative merge would reject valid existing dedicated declarations. |

The five critical files bound by exact Git blob and SHA-256 in the receipt are `AssistantToolBridge.swift`, `HanlinScriptCanonicalAdapter.swift`, `HanlinScriptAnalyzer.swift`, `miniapp-authoring.mjs` and the new `HanlinPreparedAssistantToolDeclaration.swift`. The receipt records their complete repository paths and fingerprints at both sources, plus four current supporting implementation files.

The selection finding concerns message-scoped tool exposure and user configuration. It does **not** claim that every existing runtime capability/permission check is removed. The external implementation uses the original runtimes; it adds a different declaration/catalog route. No approved missing requirement for that variant was identified in this bounded comparison.

No product source, runtime, pin or workflow was changed, and no tests or native jobs were launched for this review. Existing native acceptance of the canonical dedicated route remains with root, the Mac owner and CI.
