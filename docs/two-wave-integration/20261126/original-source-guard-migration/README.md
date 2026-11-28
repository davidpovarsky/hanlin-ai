# Original source-preservation guard V2

The two original test method identities remain in the native acceptance queue. This is an explicit ownership/baseline migration for the approved shared Chat SDK and cache work, not a native PASS.

The previous whole-file baseline already disagreed with c34dd6ae and PR18 before this session's extraction: the original expected component/API sizes were245684/197303 bytes; the pre-extraction inputs were247703/223094 or225611. Current approved extraction has216385 component bytes. The untouched ChatandFile remains1966 bytes with its original SHA256. Raw portable reproduction is retained in before-migration.json.

V2 fixes the expected ownership of all seven original accessibility identifiers. User and assistant bubbles are owned by HanlinMessageBubble; action row by HanlinMessageActionBar; search/info/code/HTML by the original app component. The guard checks these exact owners and the app's three real delegation calls. It does not concatenate arbitrary source files.

The reviewed contract freezes normalized length and SHA256 for19 original/shared owners, and the Swift test freezes the contract's entire SHA256. Expected values are never generated at test runtime. The original ChatandFile and three V3.3 reference metadata assertions remain verbatim. A direct affected-validation mapping prevents a contract-only change being classified as documentation-only.

The19-file list includes the original three files, three app Markdown/preview adapters, twelve extracted shared files and the prior shared Bubble. reviewed-proposal.json identifies the approved extraction lineage, PR22-identical APIManager and the scoped original LauncherLab native5 receipt. Full ChatPresentation, CanonicalSurvival, ClassicChatRestoration and viewport UI acceptance remain required; source hashes cannot certify those behaviors.

No application source or runtime assertion is changed by this migration. New test syntax and portable contract checks are recorded separately; actual XCTest/Swift Testing execution remains pending in the original app gate.
