# Original producer wiring — 23 November 2026

Base: published SDK revision a12cf4bac4de9c3d2a60f7620b73306046f40d7a, merged with installer c0e26d6b608f067c05ee11220931fdee6329fe88.

- Original Apple workflow export/upload wiring: YAML, shell syntax, preparation ordering and exclusive artifact-owner checks PASS.
- Bundle-resource regressions: 3 methods PASS. These exercise SDK-bundle placement, changed packaged bytes and ambiguous duplicate module bundles; fixtures are not native acceptance.
- Frozen 42926628418 Host overlay: original dependency/patch closure PASS, six source-only module updates, 3,070 other entries unchanged, 0 builder calls. Expensive frozen native data reused.
- Native exporter and bundle guard Python compilation PASS; git diff whitespace check PASS.
- Full14 native export, Apple build, EventKit/CalendarToolTests and physical iPad acceptance: NOT_RUN here. Owned by the integrated original Apple producer and device validation.
- Actual public14-binary release: NOT_PUBLISHED; docs/native-artifacts.json intentionally remains unpublished until producer acceptance and URL checksum readback.

Only the main original Apple workflow was edited in this change. No workflow dispatch, native rebuild or release publication was performed.
