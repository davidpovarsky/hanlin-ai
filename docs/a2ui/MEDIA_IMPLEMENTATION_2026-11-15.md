# Existing chat media — current implementation slice

Task A2UI-09 `1220491240486416` remains open. This slice prepares a sanctioned
YouTube component for the existing rich-content adapter; it does not claim a
production model part currently mounts it or that a video played on iOS.

`HanlinYouTubeVideo` accepts exact HTTPS YouTube hosts with validated eleven-character
ASCII video identity. It normalizes watch, short share, shorts and official embed
URLs. Credentials, unsupported ports/schemes, spoofed/trailing-dot hosts, extra path
segments, repeated video query IDs and malformed/encoded path injection are rejected.
The source link is rebuilt from the identity and has no tracking or secret query.

`HanlinYouTubePlayerView` creates WKWebView only after an explicit Load action.
It uses the [official IFrame API](https://developers.google.com/youtube/iframe_api_reference),
preserves controls, disables autoplay and requires a WebKit user playback gesture.
The local document's base URL uses the installed bundle identifier, following
[YouTube's WebView client-identity requirement](https://developers.google.com/youtube/terms/required-minimum-functionality).
No model-provided HTML/JavaScript enters the document. Only a validated video ID
and native bundle origin enter JSON settings. The scoped document reports ready/error
events through a main-frame-only handler; it has no agent tool/action bridge.

The player is nonpersistent, unloads on disappearance/background, destroys the
iframe and removes its script handler at teardown. Navigation stays with the
official player. Errors and a bounded15-second readiness deadline show a retry
and canonical Open in YouTube source link. Player errors100/101/150/153 are not
bypassed; removed/private/embedding-denied media remains unavailable in-app.

## Validation and remaining scope

Eight portable URL/document controls executed PASS with Swift6 strict concurrency
and warnings-as-errors on Windows. This does not validate WebKit or playback.
The existing manual workflow's `chat_media_component` route creates a scratch
package from the actual three production files and eight controls, checks Xcode,
SDK/runtime/device/architecture and scheme/destination, then compiles/tests on
iOS27. It retains xcresult, source hashes, logs, and bounded failure diagnostics.
This is SDK/component verification. Actual original-app XCUITest playback,
VoiceOver/RTL/fullscreen/background observations and signed physical iPad remain
NOT_RUN. Do not count portable controls as UI cases.

Native component verification completed:8 EXECUTED_PASS/0 FAILED at
`42f1e7a9da1ee968af61189a03a67b0bb62dca1e`,
[run43724157995](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43724157995),
job132842329366 (327seconds). Xcode27.2/27B52, Swift6.4.2, iOSSDK27.2, actual
iPhone18Pro iOS27.0 arm64 destination. Artifact14166201264,91556bytes, SHA256
`0cf7b90dfddd3e4d9b788e0bac1b546718a1a82324896e65f508c0f83f1f910b`.
All8 unique passed xcresult nodes and original source hashes were verified. See
`evidence/media-component-43724157995.json`. This still does not prove playback.

The canonical SDK structured-model type/adapter is still needed to mount media
without inferring executable UI from arbitrary Markdown. Custom A2UI media catalog,
galleries, safe metadata/image pipeline and direct MP4/HLS/audio acceptance remain
open, with no second A2UI renderer.

The source now adds a separate versioned Hanlin media catalog at
`https://hanlin.ai/a2ui/catalogs/media/v1`. It retains all18 official v1 component
definitions and adds a schema-validated YouTube component whose url supports a
literal or official @path binding. Unknown script fields are rejected. The official
Basic Catalog URI does not gain custom components. MessageProcessor registers both
catalogs, and iOS Surface receives the corresponding official catalog implementations.
The custom builder delegates only to the sanctioned player above. Native compilation
and actual original-app UI acceptance of this combined path are still pending.

Impact before catalog verification: ingress catalog admission and the shared session
processor constructor changed, so their full36 SDK+8 portable definition closure is
affected/uncertain. The `a2ui_media_catalog` manual route therefore executes44 exact
cases rather than reusing the prior31/17 historical proofs. It does not expand into
unrelated Composer/runtime/provider suites or imply iOS app acceptance.

The next iOS proof compiles the actual A2UI+media source closure, including the
custom catalog builder and upstream Surface call, and executes only the two
new catalog controls. The `a2ui_media_ios` route selects an actual available
iOS27 destination and preserves failure xcresult/screenshot/logs where available.
It does not repeat the8 unaffected identity/document controls as a timestamp refresh.
Actual original-app/provider/XCUITest and network playback gates remain open.

## Verified existing Markdown API

The app's exact pinned renderer remains
`f59bd0d533b6d94e01408bf6bdf9f5b09db57891`. Its public `ImageConfig` enables
HTTPS remote sources and built-in fullscreen zoom. `MarkdownParser.parse(text:config:)`
automatically sets imageSupport from imageConfig.enabled; a second parser or custom
image-tap viewer is unnecessary. Its remote domain matching accepts subdomains and
the default AsyncImage loader exposes no injectable response/redirect/decoded-pixel
limits. Do not describe merely enabling an unrestricted config as completion of
the task's private-network/redirect/size/privacy acceptance. No fork pin was changed.

The source now enables the existing renderer's HTTPS-only remote image mode and
built-in fullscreen viewer under the existing `HANLIN_A2UI_POC` prototype flag.
Flag-off behavior remains disabled. This is not a production security acceptance;
response/redirect/decoded-size and actual app XCUITest image/zoom checks remain open.
