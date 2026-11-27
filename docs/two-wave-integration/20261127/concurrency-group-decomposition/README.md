# Original concurrency fixture compiler decomposition

Three original standalone build-for-testing jobs failed in the same task-group
expression of NativeScriptShortcutConcurrencyTests.swift. The prior explicit
typing rewrite did not compile on those actual runs. Complete original build
members and exact byte-range/CRC evidence remain retained; UI source typechecking
passed, but none of the selected app/runtime/notification/origin tests executed.

This test-only change moves the exact task-group body into one explicitly
MainActor local function. The original structured task group keeps the same
child and result types and calls that function once with its inout group.
Declaring the function executes no action or suspension. The group remains in
the same scope and does not escape into child tasks.

All three submissions still precede the original admission wait. Reverse
release/acknowledgement order, returned values, duplicate delivery, cancellation,
deadline and stale-generation checks remain unchanged. The entire moved body
is byte-identical, all 131 assertion/unwrap source lines and five selectors are
preserved, and the exact two-hunk inverse recovers the entire prior file.

The parent and an independent reviewer approved this source for the original
compile retry. No Swift compiler, native test, timeout adjustment, production
source change or shipping SDK change is part of this proof. The compiler
workaround remains unqualified until an original native build accepts it.
