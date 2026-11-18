# Reuse the actual app simulator for original Motion B/C

Run 44243185407 did not execute Motion B/C. The selector searched the marketing name for iPad and omitted the already-prepared simulator named Hanlin-Phase2-..., then rejected an unused shutdown iPad. This was environment selection, not a failed animation assertion.

The combined native workflow now supplies the exact app simulator UDID file. The shared selector verifies that observed device's actual hardware identifier, installed matching stable runtime and availability, with no fallback to a different device. The existing ready-only check still requires Booted and does not cold-boot a replacement. Default standalone selectors preserve their prior behavior; a renamed hardware device is no longer excluded solely by its task name.

A focused selector regression covers the owned renamed device alongside an unused iPad and rejects wrong hardware, missing identity and mismatched SDK. Native Motion B/C acceptance remains pending.
