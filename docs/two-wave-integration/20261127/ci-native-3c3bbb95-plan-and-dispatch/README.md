# Original affected plan and CI dispatch

The original default planner passed on 3c3bbb95 and selected 90 app selectors (80 unit, 10 UI), plus separately tracked non-app validation groups. CI run 45927192346 uses the original exact-selector route with those 90 selectors. This preserves app tests but does not assert that the separate platform, router, shell, MCP, device or IPA gates ran. Empty initial run-list readback was a dispatch race; GitHub independently confirmed the run ID and exact head.
