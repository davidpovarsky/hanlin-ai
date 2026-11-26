# CLI compiler module resolution

Apple run45310162809 reached the real repository CLI after the preceding path fix. Its test passed the bare installed package name `typescript` through `HANLIN_AUTHORING_TYPESCRIPT`; the CLI wrongly converted that name directly into a file URL. The first log reproduces the same failure before correction. The final existing case resolves the bare original module from a copied working tree, builds and unpacks a real archive, and revalidates via the supplied SDK with no compiler override. The SDK fixture now includes the same `typescriptPath` contract field as the real exporter. An intermediate log records that fixture correction rather than concealing it.

The final focused case passed1/1 with zero skips. This is a portable real-CLI regression, not Apple application acceptance. Raw commands, input hashes and log hashes are in result.json.

The existing authoring acceptance workflow now runs this same copied CLI case on the actual Mac before native dependency compilation, using its already installed original Host compiler. This catches the demonstrated working-directory/module-resolution failure early; the complete staged Host test suite still runs afterward.
