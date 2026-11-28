# Host customization of the original Hanlin presentation

The host selects the original public components and supplies its layout and live bindings. `HanlinConversationView` supports the original transcript and Composer placement APIs; `HanlinMorphComposer`, `HanlinUserMessageBubble`, `HanlinMarkdownView`, activity views, OpenUI and A2UI remain independently importable. The SDK owns the implementation. Host-specific content and actions belong in the existing public slots and callbacks.

## Appearance scoped to a view

Import `HanlinChatUI` and apply `hanlinChatAppearance` to a whole conversation or any smaller subtree. The optional fields override original semantic colors only. Nil retains the original per-component light/dark color and original assets. There is no process-wide palette or mutable singleton.

```swift
let appearance = HanlinChatAppearance(
    composerAccent: .indigo,
    composerHighlight: .cyan,
    capabilityAccent: .indigo,
    toolAccent: .indigo,
    activeTitle: .indigo,
    userMessageBackground: .indigo,
    userMessageForeground: .white
)

HanlinUserMessageBubble(text: message, containerWidth: width)
    .hanlinChatAppearance(appearance)
```

The same modifier applied to the original full conversation reaches its nested Composer, capability chips, messages, approval surface and tool activity. `toolInk`, `toolSurface`, `shimmerColors` and separate temporary-message foreground/background overrides are also available. Sibling embeds can use different appearances. Existing SwiftUI layout, Dynamic Type, locale, layout direction and accessibility environment values continue to apply.

The original corner paths, widths, input-height ownership, measured toolbar, transitions, motion curves and interaction handlers are unchanged by these color overrides. `HanlinChatAppearance.original` is the default.

## Original activity motion presets

`hanlinChatMotion(.quietFade)` chooses an original activity/disclosure preset for this subtree. It takes precedence over an internal `chatMotionPreferences()` modifier and does not write the app's saved preference. System Reduce Motion still selects the original static configuration. The existing preference picker remains the default when no host override is supplied.

This selects the existing chat-activity preset. Composer opening and message entrance retain their original separate animations and accessibility behavior; no animation engine is replaced.

## Original Markdown configuration

The original streaming Markdown renderer exposes its full `MarkdownRenderConfig` through a per-view transform. Hanlin first builds the original typography, citations, media settings and selection callbacks; the transform receives that configuration. The default transform returns it unchanged.

```swift
HanlinMarkdownView(text: answer)
    .hanlinMarkdownConfiguration { original in
        original.withBlockSpacing(value: 16)
    }
```

Hosts can also use the renderer's public font, text, code, heading and image configuration methods in that transform. Retain any configuration fields whose built-in behavior is required. This keeps one parser and one renderer while making the design adjustable at the embedding boundary.

## Verification scope — 2026-11-23

Nine changed/new Swift files passed a syntax parse. A mechanical reverse-substitution check reconstructed all six original color-consuming source files byte-for-byte outside the explicit environment overrides; original fallback expressions are preserved. The Markdown transform is applied after the complete original configuration, and its default is identity. The motion preference change retains the original stored preset when no host preset is present.

These are source/parse checks. The next coherent Apple build and original visual acceptance are required for the new source pin; no native or screenshot pass is claimed here. Earlier presentation logic tests are reusable only for their unchanged model/cancellation/source behaviors, not as a substitute for rendering this source.
