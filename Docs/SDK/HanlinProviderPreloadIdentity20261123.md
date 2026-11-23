# Original provider catalog identity correction — 2026-11-23

## Observed defect and affected path

`AppDataManager.preloadDataIfNeeded` invokes the original catalog loaders during
application bootstrap and conversation creation. The provider loader previously
reconciled `APIKeys` by the editable `name`: distinct custom routing identities
with equal display names could lose a row, a custom `OPENAI` route could gain an
ambiguous built-in duplicate, and a renamed built-in could lose its original
credential reference. The original model loader also refreshed custom model
provider/capability metadata outside its `systemProvision` guard.

This correction changes the existing `PreLoad.swift` implementation. It does not
add a second catalog, persistence layer, credential store, or startup path.

## Preserved ownership and behavior

- Provider lookup and reconciliation use exact, case-sensitive `company` routing
  identity, consistent with the original model/provider routing contract.
- Custom rows are never replaced or refreshed from built-in defaults. Equal
  display names are valid across distinct routing identities.
- A unique built-in row keeps its original persistent identity, editable name,
  credential representation, visibility and capability-probe preference. Only
  its catalog-owned endpoint/help/API metadata follows current built-in defaults;
  the existing LAN/LOCAL metadata exception remains.
- An explicit endpoint/API-dialect override through the public settings adapter
  marks the same original row custom within the existing protected metadata
  writer. The writer still checks the exact durable credential reference and
  rolls back a failed metadata save; it never rotates the unchanged credential.
- Ambiguous legacy routing duplicates remain intact, including their credentials.
  The existing `duplicateProvider` error remains visible. No timestamp/display-name
  heuristic chooses an account or erases a row.
- Removed built-in defaults are pruned only when the routing identity is
  unambiguous and the original stored credential is nil/empty. Nonempty values,
  protected references, malformed identities and all custom rows are retained.
- Before provider refresh, original pending edits are checkpointed. A failed
  refresh rolls back only its uncommitted catalog mutations; raw SwiftData errors
  are not logged because they may contain original row values.
- Original model metadata refresh now stays inside `systemProvision`. Original
  model naming, built-in metadata, ordering, local-model ownership and Apple
  catalog registration remain in the same loader. Existing model duplicate
  handling is unchanged by this focused provider correction.

The original built-in provider catalog contains 29 explicit routing identifiers;
a source inventory found no duplicate identifier. No key material was used in
this inventory or placed in this receipt.

## Focused native acceptance additions

All six methods extend the existing `HanlinApplicationEmbeddingTests` suite,
which is already selected in the combined native acceptance workflow. Fixtures
use actual in-memory SwiftData rows and isolated Keychain services, not additional
full application contexts or a replacement runtime. They clean up only their
own synthetic test credential namespace.

- `HanlinApplicationEmbeddingTests/providerPreloadingPreservesDistinctRoutingIdentitiesWithEqualNames`
- `HanlinApplicationEmbeddingTests/providerPreloadingKeepsCustomBuiltinRoutingOverride`
- `HanlinApplicationEmbeddingTests/providerPreloadingPreservesRenamedBuiltinCredentials`
- `HanlinApplicationEmbeddingTests/explicitBuiltinRequestOverrideStaysHostOwnedDuringPreload`
- `HanlinApplicationEmbeddingTests/providerPreloadingRetainsAmbiguousLegacyCredentialRows`
- `HanlinApplicationEmbeddingTests/modelPreloadingKeepsCustomMetadataForMatchingCatalogName`

The assertions cover original persistent IDs, unchanged stored references,
resolved synthetic credentials, exact routing uniqueness/ambiguity, host endpoint
and dialect ownership, and preservation of custom model capabilities.

## Validation boundary

Oracle Swift syntax parsing passed for the three changed Swift files, and
`git diff --check` passed. The provider catalog routing inventory above is a
source check. No native SwiftData/Keychain test has been run for this change on
Oracle, and no historical test receipt is relabeled as validation of this new
behavior. The prepared combined Apple gate must execute the six added methods
before their native results can be accepted. Existing DATA-05 receipts remain
applicable only to their original unchanged inputs.
