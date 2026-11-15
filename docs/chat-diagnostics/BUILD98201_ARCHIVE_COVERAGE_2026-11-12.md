# Build 98201 owner archive coverage

The owner supplied two local ZIPs on 2026-11-12. They were inspected as diagnostic data only, without executing or following embedded content. Source archives remain unchanged and are not committed.

| Archive | ZIP bytes | SHA-256 | Entries |
| --- | ---: | --- | ---: |
| 7(1) | 14,833 | `01311a0aab07d489c7b3885b572a302fa4a65f0faf3d0b6b982944bea1b66506` | 9 |
| 6(1) | 15,312 | `614109530558e83dc0d57c269c048ddadb4d27f1798942e1b5f8c85cb2e0d347` | 11 |

All eight session JSON files declare schema2, Build98201, provider OPENROUTER, model identity `nvidia/nemotron-3-ultra-550b-a55b:free_repeat_OPENROUTER`, and **metadataOnly**. Internal persisted model identity is not evidence of the exact model string sent on the wire. Request byte counts/hashes exist, but request bodies, visible response content and provider-visible reasoning are absent. Neither archive contains raw response/SSE, encrypted raw sidecars, SDK/agent snapshots or rendered UI snapshots.

| Run prefix | UTC start 2026-11-11 | Engine | Session status | Stream events | Recorded finish |
| --- | --- | --- | --- | ---: | --- |
| 0C360CAA | 19:46:24 | swift_ai_sdk | cancelled | 782 | absent |
| 629ABEBC | 19:53:41 | swift_ai_sdk | cancelled | 58 | absent |
| B1906833 | 19:55:54 | swift_ai_sdk | completed | 9 | stop |
| 83B8978F | 19:56:32 | swift_ai_sdk | completed | 1 | stop |
| 2A9B16D7 | 14:31:52 | plain_text | completed | 6 | stop |
| C5E31F2B | 14:32:09 | plain_text | completed | 42 | stop |
| BC74E791 | 14:32:26 | plain_text | completed | 255 | stop |
| F694FA35 | 14:33:02 | plain_text | completed | 496 | length |

The additional trace-only log in archive6 contains two earlier SDK runs using a custom provider identity. It also contains no response body. Counts of events, repeated ModelRequestPrepared trace records, HTTP200, or a session status of completed do not establish a nonempty answer, unique HTTP attempt count, or correct rendering.

The `length`/completed combination is concrete evidence that the historical session did not distinguish provider output-limit termination in its top-level status. It supports the separate CHATUX-12 length warning/continuation work; it does not identify the origin of corrupted Unicode or prove the historical answer was empty.

The old NativeToolTraceLogger redacted numeric `inputTokens`/`outputTokens` fields by substring matching `token`. The current correction uses the shared structured redactor before stringification, preserves numeric usage fields, masks nested/camel-case credentials, and removes the separate silent30-file/20MiB trace deletion. This is diagnostic repair, not evidence that the logger caused the visible corruption.

**CHATUX-14 remains OPEN.** No first text divergence can be established from these archives, and no provider, SDK decoder, stream adapter or UI renderer is blamed. A new affected capture with actual response and correlated downstream snapshots is required. The response-only offline replay at37c56058 was executed in run43212840949: five tests passed in one suite; that synthetic/reference evidence does not reconstruct missing historical bytes or certify physical iPad rendering.
