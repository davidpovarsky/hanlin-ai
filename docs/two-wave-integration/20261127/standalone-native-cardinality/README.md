# Standalone native scope cardinality

Source-only repair after the existing lifecycle test was added to NativeScriptWindowOwnershipTests. Original cross_app/production_runtimes selectors now enumerate23/25 XCTest methods; only expected counts change from22/24. Every selector, test assertion, runner helper and AST node outside those two integers is preserved. No native test was run for this repair.

The production scope uniquely covers13 methods beyond pending paired54/extra26: four CrossApp methods, four preferences UI methods and the original five NativeScript window/package UI methods. It also overlaps11 paired54 methods and the lifecycle method in extra26. No new reuse contract is inferred; the original full scope remains the executable route.

Source commit: 0bed22f524acf82e7cc62e8eac4e89e11b13eb41
