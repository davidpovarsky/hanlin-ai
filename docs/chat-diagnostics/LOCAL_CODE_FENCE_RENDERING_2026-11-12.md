# Original-chat Mermaid and Diff rendering

## Integration and source identity

The app's exact SwiftStreamingMarkdown pin is `f59bd0d533b6d94e01408bf6bdf9f5b09db57891`
([draft fork PR](https://github.com/davidpovarsky/hanlin-streaming-markdown/pull/1)).
The optional renderer hook receives the existing parsed code block, including its
original selection ID, literal source and verified fence-completion state. It does
not split Markdown or create a second document parser. Unknown or unfinished fences
keep the library's ordinary selectable code rendering. Only completed `mermaid`,
`diff` and `patch` fences use the local preview. Other Markdown and LaTeX retain
their original rendering path.

`ChatCodeFenceView` provides source selection, copy/share, expanded navigation,
Dynamic Type, appearance-sensitive rendering, and unified/split comparison when
the available width permits it. Code and rendered documents retain LTR geometry
inside an RTL conversation. A render failure leaves the entire source available.
SVG/PNG export and physical-device acceptance are not implemented or claimed here.

## Reproducible local assets

`Scripts/ChatRendering/package-lock.json` pins Mermaid 12.3.0, diff2html 3.4.56 and
their transitive dependencies. From that directory run `npm ci`, `npm run build`
and `npm test`. The tests currently use installed headless Microsoft Edge. No
browser download is required. Generated JS/CSS, legal notices, all dependency
license files and SHA-256/byte-count manifest live in `CodeFences/Resources`.
The production dependency audit reported zero vulnerabilities at implementation;
this records that particular locked dependency graph, not a perpetual guarantee.

The worker loads only verified bundled assets into a private nonpersistent
WKWebView. Trusted `callAsyncJavaScript` receives source as structured data.
Maintained Mermaid/diff2html parsers produce the markup. Mermaid uses strict
security, no HTML labels, guarded configuration and bounded graph size. A second
DOM filter removes active elements, event attributes and external references.
CSP independently blocks network, frames, forms, plugins and external resources.
The visible document has JavaScript disabled in both WebKit configuration and
CSP, cannot navigate, and contains only static sanitized output. No credentials,
remote service, runtime CDN, script-message handler or source-to-JS interpolation
is used.

## Scheduling and limits

One private worker serializes actual JS completion. Cancellation waits for the
active JS operation to drain before admitting the next one, and rejects the stale
result. Up to eight requests may wait; source input is bounded to 1 MiB, Mermaid
to 200,000 characters/1,000 edges. Oversized or invalid output fails to source.
No input is silently shortened. An eight-second execution deadline disables the
worker until app restart. Asset validation/HTML preparation/cache hashing run on
a utility task. Cache admission is explicitly bounded to 8 MiB/32 entries in
addition to NSCache's advisory eviction. Preview height is bounded; expanded
WebKit supports scrolling and pinch zoom. Native diagnostics record identifiers,
counts, digest and elapsed time, without source content.

## Evidence and remaining gates

- **EXECUTED_PASS:** app run [43255693521](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43255693521),
  app SHA `b667a281b793010a33ddb07860267a8eb2860afa`, exact fork pin above:
  six actual XCTest cases (CodeBlockRendererTests/CodeBlockConfigTests), Xcode 27.2.
  This proves the library hook, literal IDs and closure metadata, not the app's
  new WebKit implementation.
- **EXECUTED_PASS:** four actual Edge cases in
  `build/code-fence-browser-tests-v2.log`: seven Mermaid families, Unicode,
  natural SVG geometry, unified/split diff, 1,000-line input, long lines,
  malicious source/directives, blocked external resources and asset digests.
  Browser screenshot reviewed at `build/code-fence-browser-evidence/mermaid-families.png`.
- **EXECUTED_PASS:** portable Swift syntax parse of new files; 91 existing affected
  CI-routing tests after adding native/JS ownership. A portable parse does not
  typecheck Apple APIs.
- **EXECUTED_PASS:** [43260034743](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43260034743)
  at app SHA `f9243d8d`, Xcode 27.2/27B52: all four actual production WebKit cases
  passed (seven Mermaid families/cache, full unified/split Diff, tampered assets
  and script-disabled visible WebKit, cancellation). The focused manual workflow
  staged byte-identical production sources/resources/test cases into an isolated
  iOS package and retained every input hash and raw xcresult leaf. Job duration
  8m4s; this neither rebuilt native engines nor published an app. It does not
  replace the original-bubble UI journey or physical-device profiling.
- **EXECUTED_PASS compilation / FAILED UI case:** full app at67e42a74 in
  [43267408632](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43267408632)
  compiled the actual Markdown hook/resources and ran the original-bubble UI
  journey. Both actual Mermaid and Diff WebViews appeared. The case failed when
  its query assumed the native Show code Toggle was a Button. Retained hierarchy
  instead shows a Switch labeled Show code/value0 inside each original block.
  Stable control/source-text IDs and a type-independent query now preserve
  native semantics; source Unicode/toggle/expand assertions remain required on
  the next focused rerun. No UI PASS is substituted for the failed case.
- **NOT_RUN:** VoiceOver/selection/rotation/multitasking, performance
  and memory profiling on a physical iPad; final CHATUX-08/09/10 acceptance.

Keep these statuses separate when updating task acceptance. Existing Runtime
passes are not evidence for this new rendering path.
