# Actual pending installation receipt and the repair provider correction

This supplements the immutable V8 import-presentation failure packet. It does not promote that failed UI case to PASS.

## Actual evidence

The fresh V8 repair transfer was 56f463ee-f2a6-4f6c-ad43-7614f7dcf2b1. The real import tool returned queued in round 12, then received in round 13 (execution 14:48:13–14:48:15 UTC). Round 14 completed at 14:48:27 UTC with MINIAPP_AUTHORING_INSTALL_NOT_VERIFIED_received. The receiver subsequently wrote its actual installed receipt at 14:48:36.843681 UTC, with package ID install-script-d7e81598bd3fabb072c5e57c. The original UI case failed because a newly reopened importer blocked Search Apps; native 42 and final agent verification were not reached.

raw-model/receipt.json binds all three unchanged diagnostic files by original path, size and SHA-256. actual-status-observations.json extracts the three relevant rounds without changing their meaning. The actual installed receipt and UI failure belong to the preceding primary-repair-import-presentation-attempt19-20261125 packet.

## Exact correction

The simulator acceptance provider now follows pending queued, received and submitted receipts through the real import_miniapp tool, using the same transfer UUID and a new provider call ID for each observation. Each subsequent observation is delayed asynchronously by two seconds. Instance locking protects cancellation state. A successful final response requires the actual installed status and a nonempty installed package ID. Mismatched transfer IDs and actual failure states remain failures.

The provider does not synthesize compiler output, installation receipts or native output. The original UI case, its 600-second ceiling and native 42/installed-receipt assertions remain unchanged. Original tool dispatch keys include the provider call ID, so subsequent unique IDs read the receipt anew rather than replaying the earlier result.

Source dc53a6c8ff1bb68bfbc52a64667e14ce688055b0 includes this fixture correction and the preceding MiniApps presentation fix. Both affected products require their original build-for-testing commands. The SDK and original probe closure remain unchanged. At this packet's capture, those new builds and repair case have not yet run; original52, NativeScript five-engine and notification OS outcomes are not claimed here.
