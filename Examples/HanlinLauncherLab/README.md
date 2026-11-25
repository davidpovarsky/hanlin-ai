# Native Hanlin Launcher Lab

The new HanlinChatPresentation product is part of the canonical HanlinPresentationSDK. Hosts keep their existing chat session, draft and stream owner. The product owns only native SwiftUI sheet/inspector presentation and Liquid Glass entry controls, with an optional native zoom transition.

Use a host-owned HanlinChatPresentationController, with a HanlinChatPresentationConfiguration specifying [.sheet], [.inspector], or both. Attach hanlinChatPresentation(controller:labels:transition:chat:) once to the host root. Supply the existing Hanlin conversation view in its content closure, with a session owned outside that closure. Place HanlinLauncher(style:controller:draft:labels:transition:onQuickSubmit:) in a ToolbarItem, overlay or safe area. The quick-submit closure routes directly to the host's existing send action. The switch control is hidden if the policy permits just one mode. The native inspector retains system appearance and adaptive behavior; clear glass is a sheet setting.

The example is an offline UI harness, not a provider integration: HanlinChatView, HanlinUserMessageBubble, HanlinAssistantMessageBubble, HanlinMarkdownView, HanlinMorphComposer, NativeMultilineTextEditor, and HanlinComposerDraft are actual HanlinChatUI components. The transcript and scripted stream are owned by the host and do not require a network or credentials. The three launcher styles, permitted modes, initial mode, RTL and optional zoom can be changed in the app.

Target iOS/iPadOS 27. The new presentation API is iOS-only; the independent policy model compiles on macOS for tests. For a full consumer app, use the normal SDK SwiftPM product graph rather than copying sources.


## 2026-11-25 device IPA evidence

The new presentation module and demo host were compiled for arm64-apple-ios27.0 on Scaleway Mac, Xcode 27 (27A266a). The demo linked authentic HanlinChatUI, HanlinPresentationKit, HanlinLocalization, HanlinRichUI and their dependency artifacts from the existing ca6310219ca104d5db44c7fbbb64766eb6d78c19 device archive. Shell, user/assistant bubble, Morph composer, draft and Markdown source blobs match the d2d47489dcd70ae3f40389758fe5d78278b66f3e base; NativeMultilineTextEditor and HanlinAnimatedDisclosure donor sources differ. This is not a complete rebuilt current SDK graph or provider integration. Unsigned IPA SHA256: 46957f961b6016c10901d9512492894fe3e946dcd42b851d0cc983e235204b7b. Size: 18175432 bytes. Archive integrity, binary target and Info.plist checked. Physical iPad interaction acceptance is pending. The project.yml below describes a normal source consumer for independent validation; that full package-graph path was not executed for this IPA.

## 1.0.1 — physical iPad feedback

Native toolbar launchers use the system's own automatic toolbar styling (no nested GlassButtonStyle). Floating capsule uses sparkle and title only; no outbound arrow. All three entry styles are absent while the conversation is open or transferring between native Sheet and Inspector. The header close button is the only conversation-close entry. The demo removes the entire native ToolbarItem or floating overlay while the controller's showsLauncher is false. Quick composer retains its local collapse button before the conversation opens; drafts remain host-owned. Optional native zoom is retained as an experiment; because entry controls are removed while open, the system can fall back to the normal dismissal transition. Native geometry and animation still require a physical iPad check.

Build 1.0.1 (2): the changed presentation module and demo host were freshly compiled and linked on the same Mac against the existing original chat SDK objects, as described above. IPA SHA256 28f99252c0e451ac604b7f36c6e4c8b11647e6b81beeacff6a4acbab338c9500; 18174367 bytes. Archive integrity, plist, arm64 and iOS 27 binary load command verified. No physical-device QA of the new visual fixes is claimed.
