# Original Canvas Python integration

## Product behavior

The existing Canvas now lets the user choose the existing local CPython runtime or the existing remote Piston path. Local execution goes through AgentHostServicesAdapter and the original Host broker/runtime. It respects the existing Local Python tool setting. There is no alternate interpreter, agent, chat, grant store or remote fallback.

The chosen source is captured before execution. Remote execution requires a separate confirmation identifying emkc.org, external code transfer, provider authorization and possible network/service costs. HTTP 401/403 now reports the missing provider authorization accurately. The upstream public API no longer allows unauthenticated public execution:
https://github.com/engineer-man/piston/blob/master/readme.md

The local operation uses the existing RuntimeUserOperation, native interruption and durable runtime job output. Cancellation stays pending until execution returns. Remote cancellation stops the HTTP wait and cannot promise to terminate code already running on the server. Closing Canvas requests cancellation. Existing Canvas content, UUID, versions, SwiftData binding and renderer are preserved; native Done now closes the existing sheet.

New labels have English, Hebrew and Simplified Chinese translations matching the existing RuntimeLocalizable catalog. This does not claim complete app localization in eight languages.

## Evidence and acceptance

Added original-app selector:
AI_HLYUITests/HanlinCanvasRuntimeUITests/testOriginalCanvasRunsEmbeddedPythonAndRetainsSourceAfterRelaunch

It opens the real Canvas from the original Composer, computes 6 * 7 with embedded CPython, checks the remote disclosure/cancel UI, closes and cold-relaunches the app, and computes again from the persisted original source. Initial input uses the existing isolated UUID-scoped acceptance SwiftData store. It does not use fake runtime output or a replacement Canvas.

Windows Swift syntax parsing passed for all changed Swift files. Native compilation and the actual selector remain PENDING. Remote Piston success remains BLOCKED_EXTERNAL until a compatible provider authorization/configuration exists; no successful remote execution is claimed.
