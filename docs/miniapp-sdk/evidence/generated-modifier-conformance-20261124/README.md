# Generated SwiftUI modifier conformance probe

Base: `6d9a59bfc1bd1830a8d56e694c42b19c6bd7d468`.

This lane adds only `Fixtures/ExpoSwiftUIProbe/GeneratedModifiersProbe.tsx` plus retained evidence. The component uses the public `@hanlin/expo-ui` and modifier barrels. The source map contains 87 locally generated factories; the four explicit upstream-precedence names are excluded, leaving **83 effective local public modifiers**. All 83 have meaningful typed call sites in the probe, bound to the installed native registry, exact native Record fields and corresponding SwiftUI forwarding method. No generated adapter, original library, policy, registration mechanism or production test hook changes.

## Evidence levels

`source-conformance.json` records all 83 cases with exact calls/parameters, source lines, context, native record body/hash, and an explicit observation boundary. The capture uses the actual retained TypeScript 6.0.3 parser and checks source identity/field binding. **It is not semantic type validation, a Metro build, or native execution.** Those are separate results.

The actual original `@expo/ui` 58.0.29 `createModifier` implementation preserves the provided `$type` and parameters; its identity is retained in `original-factory-provenance.json`. The probe does not recreate a bridge or return mocked native results.

`PanelFrame` exposes a marker only after an event from the original public native `onAppear` modifier. That marker acknowledges a mounted panel. It does not say that each modifier's complete behavior passed, and it cannot substitute for visible/event assertions.

## Real observable cases

The source supplies native observations for accessibility value changes; tracking and position geometry; disabled/restored hit testing between two real native buttons; blocked/restored ancestor submit handling; disabled/restored native List selection; actual table header visibility; native search completion; and navigation title/bar/back-button visibility. `native-observation-plan.json` gives exact IDs, labels, action sequences and expected values. Entry owns the corresponding App route and UI target integration.

Companion controls exercise real slider, swipe, inspector and accessibility-action callbacks. Their success is not automatically proof of every nearby modifier. Geometry tests must inspect actual native frames; state markers alone are insufficient.

## Required contexts that this embedded probe does not create

Preview naming applies in Xcode previews. Document-launch and file-dialog modifiers require an actual host-owned document scene or SwiftUI importer/exporter presenter. VoiceOver speech/direct touch and accessibility drag/drop require their services/sessions. Window activation, Assistive Access, system overlays/gestures/status-bar policies, external URL handling and RTL flipping require corresponding OS conditions. These remain source-forwarding and bounded context-application evidence, not invented full-behavior passes. The probe explicitly displays this distinction for document/host settings and does not launch a fake presenter.

The four upstream-precedence names are `navigationBarTitleDisplayMode`, `preferredColorScheme`, `presentationCornerRadius`, and `sectionIndexLabel`. The last is used only as an upstream supporting factory for the real section-index context and is not counted among the 83.

## Validation and acceptance status

- TSX syntax and 83 source/registry/payload bindings: captured with zero parser errors.
- Public CLI semantic validation and Metro build: pending the one combined entrypoints lane using the actual original compiler/dependency closure and current facade bytes.
- Native UI/device acceptance: **NOT_RUN** in this lane; root owns dispatch.
- Original SDK-only authoring proof: frozen and unchanged.

No `as any`, suppression, compiler override or native-success stub is added. The complete source-capture command and output hashes are retained alongside the machine-readable case map.
