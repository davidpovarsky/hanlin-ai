# Give the original application one package-product owner

Candidate base: `f870abda090a7ac0f382b7b9396599d1b474a7ef`. This is a targeted correction to the existing Xcode/SDK generator. It adds no SDK implementation, changes no Swift source and replaces no original acceptance test.

## Original executed evidence

Paired native run https://github.com/davidpovarsky/hanlin-ai/actions/runs/45283243206 attempt 1 executed source `4cfa52348e80cf635caf04c541fd84ee1ddb50bd`. Its original app console records the same NativeMultilineTextEditor coordinator, MultilineInnerTextView, ChatAutoFollowController and ChatScrollViewHandle classes in both the HanlinApplication package-product image and AI_Hanlin.debug.dylib. The attached exact excerpts bind the original console and original artifact hashes. These duplicate loaded implementations are observed; they are not established as the cause of the separate keyboard-focus failure.

The previously integrated a82 framework-phase repair is an ancestor of that actual producer. Its app framework phase links only HanlinApplication plus a native/system reference, but the app still declares 49 package products and the unit target 18. The original Xcode build graph explicitly includes HanlinChatUI-product and the other original products as HanlinApp dependencies; the original app linker command still contains many package framework arguments beside HanlinApplication. The original SDK and app linker commands are retained losslessly. LinkFileList contents were not retained in the artifact, so this packet does not invent exact object membership.

## Candidate

`Scripts/SDK/application_products.json` becomes the canonical declaration of the original AI_Hanlin implementation's 48 product dependencies. It preserves their original order, product identity and package identity. The SDK generator reads this declaration independently of the thin executable and retains the same explicit runtime/support targets. Its input receipt includes the new file hash. The existing installer's `/Scripts/SDK/` sparse bootstrap already includes the file.

The project updater removes only products proven to belong to HanlinApplication's complete target/product closure from both the app and unit test packageProductDependencies. Each keeps HanlinApplication. Native/system framework references and independent host products are retained. All other executables and extensions remain unchanged. The checked-in graph gate now checks both declaration and framework-phase ownership, preventing the earlier phase-only repair from appearing sufficient.

Only two PBXNativeTarget objects change: HanlinApp declarations 49 to 1; AI_HLYTests declarations 18 to 1. All other project objects, framework phases, settings, module/product identity, resources and source membership are byte/structure equivalent. HanlinApp remains the executable target/module; AI_Hanlin remains the SDK implementation module and original app product/executable name.

## Focused validation

PASS: the full generated Package.swift is byte-identical before/after, SHA256 `9d479c23f1e3609f4da4252abf120f9ce0349948bd0367955099168e5a3f9ed1`. All 44 individual public-product profile manifests are also byte-identical: 45 comparisons total. The complete graph retains 44 public products, 108 targets and 507 original application Swift sources. All 18 canonical module manifest inputs are unchanged.

PASS: project generation is idempotent, both original graph validators pass, and all 6 focused ownership controls pass. These cover the actual reintroduced duplicate declaration/link edges, preservation of unrelated objects and independent Host libraries, preserved app identity, full original dependency reachability, and fail-closed missing/ambiguous/recursive/duplicate seed validation. Python syntax and git diff whitespace checks pass. No previously accepted native baseline was rerun.

NOT_RUN: repaired native linker graph, absence of duplicate loaded SDK classes, original unit product compilation with the new declaration graph, and paired focus/return acceptance. The next already-required original native continuation must verify these. Native duplicate-image removal is not inferred from local graph checks alone. The original paired transfer/relaunch/rollback PASS remains attributed to its executed4cfa producer; this correction changes no importer/storage/transfer implementation.

This candidate is reviewable and frozen before any new native dispatch. No new CI run is part of this commit.
