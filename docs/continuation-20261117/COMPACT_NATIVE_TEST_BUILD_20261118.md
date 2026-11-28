# Compact native test build correction — 2026-11-18

Run 44245400237 at 1d579b7903905c5cf2ba0fc7a683aabd1bb7cdd6 failed while compiling the test target, before executing the selected UI scenarios. Four new AllModels fixtures omitted the existing required displayName initializer argument. The dependent key-path diagnostics were cascading errors.

Only those four fixture display names are supplied. Original initializer requirements, model readiness policy, catalog identifiers/indices, enabled provider checks, local download checks and all assertions remain intact. Windows Swift 6.3.3 parsing passes; this is not native acceptance.

The replacement native selection combines ModelPopoverZoomOrderTests, CompactRecentConversationsTests (including the Unicode crash regressions), and the two original compact Composer UI cases. The obsolete Unicode-only run used the same uncompilable test target and is superseded, with no acceptance claimed from it.
