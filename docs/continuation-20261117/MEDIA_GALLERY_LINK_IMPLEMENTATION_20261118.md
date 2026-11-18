# Image galleries and link cards — implementation and acceptance scope

Status: IMPLEMENTED / APPLE COMPILE AND UI ACCEPTANCE PENDING.
Owner task: https://app.asana.com/1/1219597879016953/task/1220491240486416

## Product path

The existing Hanlin media catalog now registers ImageGallery and LinkPreview beside its original YouTube component and the 18 official basic components. The original A2UI processor validates the schemas, resolves data bindings, owns the graph and renders into the original model/tool-result transcript. No new chat, renderer, permission authority or Agent is introduced.

The existing present_a2ui tool advertises the new fields and source requirements. The original app presentation consumer supplies the same catalog instructions to the existing SDK session's model request. The native acceptance provider now requires that these instructions actually reach the original HTTP request, in addition to its existing structured-output, action, sequence and conversation assertions.

ImageGallery.items contains 1–10 entries. Each has a stable id, url, sourceUrl, nonempty description (alt text), and optional title. URLs must be admitted HTTPS sources. The original SDK resolves dynamic string bindings. Duplicate IDs or invalid entries yield a visible unavailable state. Each image retains its own source; no source, attribution or license is invented.

LinkPreview accepts url and optional title, description, thumbnailUrl. The explicit load action fetches a bounded HTML response and reads its title/description/representative image through Hanlin's already-pinned SwiftSoup 2.8.7. Parsing executes no page script and fetches no nested page resources. The card continues to show the original source if a preview fails.

Gallery images load only after a local user action. Native SwiftUI Quick Look provides full-size image viewing, paging and system sharing from the bounded local files. Backgrounding and host disable remove local loading permission. URL-bound view identity requires another request after source replacement. Historical media controls remain local; form, RPC and tool authority stay revoked.

## Retrieval limits

The new custom components use one actor-backed store with at most four distinct in-flight requests, deduplication and consumer-counted cancellation. Transport sessions are ephemeral, with no cookies, URL cache or credential storage. All redirects are refused. Responses require HTTP 200 and permitted MIME types; bodies stop at 4 MiB per image and 1 MiB per HTML page. Timeouts are 8 seconds per request and 15 seconds per resource.

ImageIO checks dimensions before decode (20 million source pixels, neither dimension above 20,000), creates a thumbnail of at most 2,048 pixels per side and re-encodes one JPEG frame. The disposable file cache is capped at 48 MiB and 20 entries, with a five-minute age limit on reuse. Prior-process disposable files are removed by the singleton before reuse. Full-page bodies and user credentials are not persisted.

Every resolved address is checked against a conservative special-use address policy before URLSession begins. IPv4-mapped and well-known NAT64 addresses must embed an admitted IPv4 address. This preflight does not pin URLSession's separate DNS resolution: DNS rebinding remains a documented limitation. The original official basic Image/Video/Audio networking and the existing Markdown renderer are not replaced by this custom-gallery store; the new limits must not be advertised as applying to those original paths.

## Verification

- Original provider URLs for three Apple developer icons and the SwiftUI source page returned HTTP 200, their expected MIME types and no redirect on 2026-11-18. Exact byte hashes are recorded in MEDIA_GALLERY_LINK_PORTABLE_EVIDENCE_20261118.json. These are acceptance inputs, not a claim of image-search provider or copyright-license verification.
- 39 portable Swift destination-policy controls passed with Swift 6.3.3, complete concurrency checking and warnings as errors. This does not validate Darwin DNS, URLSession, SwiftUI, ImageIO or Quick Look.
- Changed Swift sources parse; JSON component schemas and both proof preparers validate locally. Parsing is not Apple framework compilation.
- The native media UI contract increases from 7 to 12 methods without dropping any prior assertion. New obligations cover three real HTTPS images and native Quick Look, real link metadata, URL replacement, parent disable/background, and rejection of private/credentialed sources.
- The exact-pin SDK contract adds two methods for original graph/binding resolution and rejection of overlarge collections, missing source URLs and script properties. Its former catalog count changes from 19 to 21 because precisely two custom components are added. Original basic catalog isolation stays asserted.
- The native source-policy suite adds the same 39 IANA-derived destination examples. The component harness resolves the identical existing SwiftSoup commit; no product dependency or version changes.
- Original Chat/SDK delivery, provider execution, physical-device behavior, remote video playback and performance acceptance remain separate gates. No phase or media-task completion is inferred from implementation or portable checks.

## Primary API references

- https://developer.apple.com/documentation/swiftui/view/quicklookpreview(_:in:)
- https://developer.apple.com/documentation/foundation/urlsession/bytes(for:delegate:)
- https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)
- https://www.iana.org/assignments/iana-ipv4-special-registry/
- https://www.iana.org/assignments/iana-ipv6-special-registry/

Apple SDK-interface fallback via the installed apple-devtools failed before dispatch with HTTP 422 (Unexpected inputs: modules). No toolkit or unrelated repository was modified; readable official signatures and the actual focused project build are the validation authorities.
