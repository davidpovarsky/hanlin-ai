# Actual failed validation projection and production correction

The original focused19-v5 run used source 6c006c948f0a6f371f7fc68b90e393f43734f8dd and the unchanged SDK19 archive. The original ManualInput UI case passed (153.166 s), including real HTTP 200 and 404 image requests. The original repair UI case failed (281.492 s) before any new archive was built or imported. The run was charged 713.0760274589993 s, and its terminal state, ledger and decision remain failures.

## What the retained evidence establishes

The original invalid package displayed a structured sheet with file, TypeScript code, line and column, Copy Report and Send to Hanlin AI. The screenshot is an actual simulator capture. The original SDK tool completed, and the controlled model followed its stored result references successfully. The original validation then returned the real TS2322 and MINIAPP_SOURCE_CHANGED diagnostics. Its stored JSON payload is preserved byte-for-byte.

The model-visible tool message instead became: “A previous operation may have committed. Reconcile it in the original context before retrying.” The actual session transcript and durable tool payload establish the difference. The simulator fixture reported MINIAPP_AUTHORING_NONJSON_RESULT_miniapp-invalid at request count 8. This was not an OS import-delivery failure: write/build/import had not started.

## Source correction

Production commit 958cf666da7be83b9b63e46e3013e3344fb31585 changes only HanlinAppHostIntegration.swift. Canonical native.system get_miniapp_sdk and validate_miniapp are classified as readOnly. The original authoring implementation returns validation results before build emission; expected compiler errors therefore have no host-managed write to reconcile. Existing failed read handling preserves the real report and stored result reference. Write, build and import classifications, tool errors, routing, result schemas and compiler checks are unchanged.

The patch and exact source bindings are included. An independent peer reviewed the source path and classification. The pinned upstream OpenAI and OpenAI-compatible serializers preserve text and errorText values unchanged. SDK19 has no changed producer input from this Host-only fix. The source advance retains the exact prepared files and identifies the affected AI rebuild and repair test.

## Scope and next acceptance

This packet includes the actual Manual PASS, actual Repair FAIL, actual source correction and source advance. It does not establish a repaired package, successful import, native result 42, fresh full 25+27 acceptance, five-engine acceptance or OS event delivery. Those require separate actual native results. The focused19-v6 continuation is not relabeled as a pass here.

The four source packet receipts are retained verbatim as source-receipt.json. Every payload is verified by its original recorded length and SHA-256. The manual supplement includes the six newly generated original probe archives and a lossless gzip copy of the build log. Historical failures remain visible.
