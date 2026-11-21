# Hanlin native UI catalogue and source map

Date: 2026-11-21. Baseline: `5534d6b249518d29efda6c2a43f4eacbfbc2b973`.

## Design contract

The existing application uses Apple's system typography, native grouped lists/forms, the app's named adaptive colors, SF Symbols, and the approved Liquid Glass Morph composer. The Library screen supplied by the owner is the visual reference for ordinary navigation and settings. This change retains that language and gives app-owned typography and reusable control geometry a shared implementation.

The source catalogue is consumed by the app, HanlinChatUI and HanlinRichUI. It is not a second theme or a demo-only stylesheet. System controls still own their native interaction, internal layout, accessibility, and animation.

## One place for each decision

| Decision | Source of truth | Consumers |
| --- | --- | --- |
| Semantic type scale and family | `Packages/HanlinPresentationSDK/Sources/HanlinPresentationKit/HanlinDesignCatalog.swift` / `HanlinTypography` | App screens, chat, tools, settings, runtime/Skills/MCP screens and rich native results |
| Native UIKit font | `HanlinTypography.uiFont(_:)` | Native search; editor and Markdown integrations |
| Shared app control geometry | `HanlinControlMetrics` in the same file | Inline search, model popover, embedded capability pages and live catalogue |
| Adaptive app colors | Existing `AI_HLY/Assets.xcassets` named colors | Original app controls; reusable package surfaces inherit accent/tint |
| Native control behavior | SwiftUI/UIKit system components | Lists, forms, search, menus, toggles, pickers, buttons, text input and navigation |
| Approved Morph geometry | `HanlinMorphComposer.swift` | The composer owner; not duplicated into a global generic card style |
| App-to-package names | `AI_HLY/Downstream/ChatPresentation/HanlinDesignCatalogBridge.swift` | Module-level aliases for typography, metrics, search and catalogue |
| Reviewable examples | `HanlinComponentCatalogView.swift` | Settings → Developer/Diagnostics → Interface catalogue |

HanlinPresentationKit is already a dependency of both UI package targets. The app already links it and HanlinChatUI. The app's filesystem-synchronized Xcode source group includes the bridge without a second project-file source list.

### Typography

The shared roles map directly to Apple's semantic roles: largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption and caption2. Existing weights and modifiers are preserved. Changing `HanlinTypography.design` changes the family across these consumers while preserving Dynamic Type and multilingual fallback.

`HanlinTypography.fixed(size:weight:design:)` centralizes intentionally fixed glyph dimensions and already-scaled document sizes without silently changing them into body text. Semantic code text uses the matching shared role followed by `.monospaced()`. This preserves the distinction between interface text and code/document content.

The UIKit bridge starts with `UIFont.preferredFont(forTextStyle:)` and applies the same family through a system font descriptor. It returns a system font at its preferred size, rather than inventing a second point-size table.

### Geometry

| Token | Value | Purpose |
| --- | ---: | --- |
| minimumHitTarget | 44 pt | Minimum inline control height |
| pageInset | 12 pt | Existing embedded page padding |
| sectionSpacing | 12 pt | Existing custom section separation |
| rowSpacing | 8 pt | Existing custom horizontal row spacing |
| rowCornerRadius | 12 pt | Model rows and embedded cards |
| popoverCornerRadius | 22 pt | Existing custom popover shell |
| iconSize | 24 pt | Existing model navigation icon container |
| badgeHorizontalInset | 5 pt | Existing model badge horizontal inset |
| badgeVerticalInset | 1.5 pt | Existing model badge vertical inset |

These values belong to app-owned embedded layouts. Native List/Form/navigation metrics are not overridden with a universal padding rule. Rich HTML/document dimensions and user-generated layouts keep their own content semantics.

## Native-control corrections

### Model and Skills search

Three hand-built search surfaces were replaced:

| Surface | Implementation | Reason |
| --- | --- | --- |
| Model picker expanded page | `HanlinSearchField`, backed by `UISearchTextField` | The source-linked model popover intentionally has no navigation bar |
| Skills page inside Morph | The same native inline search | One outer composer scroll/layout owner; a nested navigation search bar would add competing chrome |
| Model management screen | Native `.searchable` in a `NavigationStack` | This screen already has ordinary navigation and a system List |

Existing model and Skills management screens already using `.searchable` retain it.

The inline wrapper uses the system search glyph, clear button, editing interactions, accessibility and keyboard. It preserves its SwiftUI binding, the existing accessibility identifiers, marked text during IME composition, and the current app tint. A finite proposed width is used for sizing, with a shared minimum control height. No custom clear button, magnifying-glass HStack or hand-drawn search background remains in those two embedded controls.

The model picker also computes filtered provider groups once per render and reuses them for the result count and rows. This removes duplicate filtering without introducing a stale cache.

Apple references:
- [UISearchTextField](https://developer.apple.com/documentation/uikit/uisearchtextfield) permits a real search field outside a UISearchBar.
- [Adding a search interface](https://developer.apple.com/documentation/swiftui/adding-a-search-interface-to-your-app) documents native SwiftUI search placement in navigation.
- [searchable(text:placement:prompt:)](https://developer.apple.com/documentation/swiftui/view/searchable%28text%3Aplacement%3Aprompt%3A%29)

### Capability buttons

The embedded Action Center keeps its capability grid, routes, selected states, identifiers and the approved outer Morph. The inner controls now use native bordered button styling and inherited app tint. The duplicate hard-coded blue fills, nested interactive glass decoration, forced white labels, and 80% text scaling have been removed.

Titles and subtitles can wrap to two lines. They use shared semantic fonts and system primary/secondary text colors. Shared hit-target and spacing metrics replace ad hoc values where the geometry already has the same role.

### Live catalogue

The catalogue is linked from the existing diagnostic area. It presents the actual shared typography, system controls, inline native search, adaptive foreground styles and selected metric values in a native List. Sample controls hold only local state; they never dispatch tools or change application preferences. New labels have English, Hebrew and Simplified Chinese translations in the existing string catalogue.

## Application map

The JSON inventory records every scanned source path, SHA-256, declared View names, native component occurrences, shared typography/metric references, original palette tokens and any remaining direct-font or custom-search candidates.

| Area | Principal files/directories | Native structure / shared catalogue use |
| --- | --- | --- |
| Chat, composer and transcript | `ChatView.swift`, `Views/Components/ChatViewBottom.swift`, `ChatViewComponents.swift`, `Downstream/ChatInput`, `Downstream/ChatPresentation` | Native text input and menus inside the approved composer; shared transcript and rich-result typography |
| Library, history and saved material | `ListView.swift`, `KnowledgeListView.swift`, `HanlinPersonalLibraryView.swift`, `MemoryArchiveView.swift`, `PromptRepoView.swift`, `ChatSavedExcerptsView.swift` | Existing navigation/list/form language retained; typography routed to catalogue |
| Models and providers | `ModelsView.swift`, `ModelsViewComponents.swift`, `ModelManagementView.swift`, `APISettingView.swift`, `HanlinModelPickerPopover.swift` | System search in navigation; real native search in embedded picker; native menus, toggles and lists |
| Skills | `Downstream/AgentSkills/UI`, embedded Skills page in `HanlinComposerPopupView.swift` | Existing searchable List/Form management; unified inline search and semantic labels |
| MCP and runtimes | `Downstream/MCP/UI`, `Downstream/RuntimeCore/UI` | Existing native settings, package lists and diagnostics; shared text and monospace roles |
| Settings, evidence and diagnostics | `SettingsView.swift`, `SettingsViewComponents.swift`, `Downstream/AgentDiagnostics`, `Downstream/AgentActivity/Evidence` | Native forms/sections/menus; live catalogue linked in diagnostics |
| Native apps, scripting and structured results | `NativeAppPlatform/AppsHub`, `NativeAgentExtensions`, `Downstream/ScriptingPlatform`, SDK `HanlinRichUI` | Shared interface type roles; content-driven rich-document layout preserved |
| Vision, study, sharing and media | `VisionView.swift`, `Downstream/TorahStudy`, `Downstream/SystemIntegrations`, `ChatPresentation/Media` | System controls and current content semantics retained; shared application typography |
| App extensions | `ChavrusaChatShare`, `ChavrusaChatTranslationProvider`, `ChavrusaChatNotificationService`, `HanlinScriptingWidgets` | Included in the inventory; retain native system defaults and independent target dependencies |

The separate HanlinMiniAppsApp product, vendored runtimes, generated bridges and tests are outside the UI-theme migration. System internals and arbitrary user-generated rich content are not presented as globally themeable by these tokens.

## Scope and evidence

The catalogue work changed 75 existing Swift files, routing 580 semantic font sites, 49 fixed-size factory sites and 24 monospaced semantic sites. Four Swift sources implement the catalogue, UIKit search, app aliases and the linked live example screen. This count excludes parallel chat/composer/streaming work.

The refreshed inventory covers 511 Swift files, 171 UI-related files, and 252 View declarations. After integration of the parallel chat changes it contains 845 shared typography references and 53 metric references. No direct semantic/system/custom .font call sites remain in the main app and Presentation SDK outside the central factory implementation. Four extension font sites intentionally retain the system defaults. Remaining candidates are reported rather than hidden. The one search-field candidate is the catalogue's non-UIKit fallback.

Source validation:

- Windows Swift 6.3.3 `-frontend -parse` succeeded for 79 changed/new Swift files. This proves parseable Swift syntax only; Windows cannot typecheck UIKit/SwiftUI.
- The migration manifest records exact touched paths and counts.
- The inventory is a lexical source map, not a measurement of runtime layout or performance.
- Apple-platform compilation is performed by the integrated device archive. Physical iPad validation of layout, accessibility sizes, RTL, keyboard interaction and live streaming remains a separate acceptance activity.
- No simulator was launched for this catalogue work.

Artifacts:
- [Migration manifest](design-catalog-migration.json)
- [Source syntax report](design-catalog-syntax.json)
- [Native UI inventory](native-ui-inventory.json)

Refresh the source inventory after integration:

```sh
python Scripts/Audit/audit_design_catalog.py --output docs/continuation-20261121/native-ui-inventory.json
```

The audit never changes application source. Without an output argument it prints only a compact summary.
