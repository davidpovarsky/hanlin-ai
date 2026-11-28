# Current source inventory repair — 19 November 2026

The canonical inventory generator still read every source anchor from dd700c03, even when the application had advanced. The original exact-revision repair in99af1a183ad81ea2ef4269cc5a60403889ec1d2f had not reached this branch. This change adopts those two original generator/test files without alteration and generates the inventory against048e431cc55b10290c03ec4b2c0162e5f9dfcf9c.

All278 original IDs, historical descriptions, decisions, target owners, migration/accessibility obligations and acceptance statuses are preserved. The prior complete matrix is retained here.623 source anchors now bind28 actual current files and their SHA256 values; the actual PBX project hash is bound independently. Baseline-to-target file changes are in../../target-source-delta.tsv. The unchanged historical baseline and original blob digest remain separate.

Twelve adversarial inventory tests passed, including rejection of a symbolic target, an altered project hash and a mismatched anchor revision. The original target graph validator also passed with63 shared source members and the existing distinct AI/MiniApps product graph. These are source checks; they do not execute or approve any feature, signed app or device.

Per-feature acceptance remains269 NOT_RUN and9 BLOCKED. Native run observations are preserved separately in the continuation acceptance register; a passing subset from an earlier source is not silently promoted to full current-feature acceptance. The26 original UX summary choices are unchanged, and the unavailable full historical visual prompt is not reconstructed.
