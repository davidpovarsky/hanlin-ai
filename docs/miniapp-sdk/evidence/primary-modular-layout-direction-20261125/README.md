# Modular native direction change

The actual attempt10 search-results screenshot (SHA2564e0306706a72ad9e5a5eea9e8b7d22af51eb00b28a6fa3a26d208dd424bc9d33,02:41:36.578UTC) shows horizontally mirrored glyphs throughout the native List while the system/search chrome is normally oriented. The actual detail screenshot19.764seconds later (c257bd61c88b07f48ce42bd81e860948fa89fa5ba6307627a9c6d966007db95f) is normally oriented. Both root and the evidence peer inspected these exact images.

The source starts in Hebrew and switches the same original Host/List subtree from RTL to LTR when the English button is pressed. The newly opened detail List is constructed after that switch. No explicit negative scale or mirror is present in the Modular source or its original Searchable adapter. Retained source supports investigating reuse across that direction update; it does not establish an upstream root cause by itself.

The bounded candidate keys the original Host by locale, so its native subtree is created with the selected direction. App remains mounted: query, navigation path, search/text options, filters, results, loaded text data, metadata, request refs and registered actions remain in their existing React state above Host. Native focus, scroll and uncontrolled disclosure presentation may reset when switching language. No query/data reset, inverse transform, vendor patch, runtime or SDK change is introduced.

This is a one-line fixture-source change. The current required Modular run will rebuild the package through the original SDK toolchain, switch languages and retain its live search/detail/full-text images. Visual correction is PENDING; this source checkpoint is not a claim of a passing image or native case. The separate already-passing parity case is unaffected.
