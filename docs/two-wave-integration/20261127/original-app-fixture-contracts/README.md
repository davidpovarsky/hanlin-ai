# Original app fixture contract corrections

The actual source-466c6187 downstream unit run exposed two stale fixture contracts.
`crossCallerConcurrency` requested the obsolete Expo runtime string `jscore`, while
the existing adapter validates the five canonical `RuntimeKind` raw values (and
its retained Python alias). The fixture now supplies `javaScriptCore`; all three
operations still start with `async let`, and their original result and storage
assertions are unchanged.

The original conversation-metadata test still expected the earlier Chinese or
English rename wording. The actual mutation uses the shared localization catalog's
`Conversation renamed to %@` key. The test now resolves that same public catalog
contract and inserts the same literal `Renamed שלום` title. This is an explicit
correction to an obsolete expected message, not a claim that the assertion text
was unchanged. Original row identity, persistent IDs, pinning, draft preservation,
namesake isolation, no-op, empty-title, detached temporary-record, and row-count
assertions remain unchanged. No locale or global settings are modified.

The added `HanlinLocalization` import is already used by
`AI_HLYTests/HanlinConversationMetadataTests.swift` in the same test target and is
also exported by the existing `SkillL10n.swift` owner. No target graph or package
dependency is changed.

Both source preimages are byte-identical between the failed native source
`466c6187309f86da9d20b389de3c424cd93c9bdd` and reviewed base
`5b39e0efb107331f9be8200b99924467e75bcd26`. The recorded inverse substitutions recover
each complete original file. This packet records source review only: neither a
Swift compile nor a native rerun was performed in this lane. The original native
cases must execute on the integrated source before acceptance can be claimed.

The complete original failure logs and private operational triage are retained
in the authorized handoff outside the public repository.
