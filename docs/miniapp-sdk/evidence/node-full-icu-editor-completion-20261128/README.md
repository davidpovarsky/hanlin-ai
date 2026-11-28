# Node Mobile full ICU: frozen source candidate

## Observed failure and exact compiler authority

The original Editor test on de7758a9 reached the actual authoring language service and failed at TypeScript's createIntlCollatorStringComparer with ReferenceError: Intl is not defined. The original compiler uses Intl.Collator for UI completion ordering. The host invokes that original compiler directly; this candidate changes neither the compiler nor its comparator, language-service API, saved source, UI assertions, or test budgets.

The actual Editor observer's verified tooling aggregates match the corresponding retained Gallery SDK closures. The portable run additionally rehashed all 276 files in the exact TypeScript wrapper/implementation/library directories against those retained manifest rows. This qualifies the consumed compiler inputs, not whole-SDK equivalence.

## Native source change

The pinned Node Mobile commit remains 4768489cd0cfa3bb0c27786e958c6446c004f1bd, version 24.5.0. Its original iOS preparation explicitly sets --with-intl=none in all three existing configurations.

The existing hash-pinned downstream adapter now changes those three settings to full-icu and adds libicudata.a, libicui18n.a and libicuucx.a to the original archive copy list and NodeMobile framework link phase. The pinned ICU GYP defines target icudata/icuucx and target-capable icui18n; icuuc is a forwarding target of type none, while icutools is host-only. Neither nonexistent libicuuc.a nor the host-only tools library is linked. Original platform build commands, linker options, exported symbols, JITless/DrumBrake behavior, pointer compression, explicit bounds checks and native deadlines remain unchanged.

Full ICU is chosen because the target product supports English, Hebrew and Simplified Chinese. The pinned configure script's small-icu default is English-only; a hand-selected partial locale data set would create a separate maintenance contract. Full ICU uses the pinned original ICU source, data and cross-compilation rules, without a comparator replacement or JavaScript stub.

The original native smoke now requires actual Intl.Collator locale support for en, he and zh-Hans and numeric ordering. Runtime assembly also requires that recorded smoke field. Source/lock admission requires the full-icu preparation receipt. The old Node and RuntimeBundle verification states become pending-build; their historical hashes are retained as historical values. The original native identity changes from d1e91cbf... to 495347df..., and its unchanged reuse verifier rejects the old binary.

## Actual portable evidence

Five adapter controls passed using losslessly retained original pinned upstream files, including original full LICENSE. They check real target libraries and framework references, exact preservation of prior WASM outputs and all other PBX settings, read-only describe/idempotence, four tampered inputs rejected before writes, and a symlink escape rejected before writes.

The unchanged four Editor tests were executed with each actual compiler: TypeScript 6.0.3 through the Expo wrapper and TypeScript 5.9.3 for NativeScript. Removing Intl only in a disposable control process produces three real Intl ReferenceError failures and one preserved path-guard pass per compiler. With the real Linux Node24.5 full ICU runtime, all four original tests pass for each compiler. Two direct original host API queries additionally return toUpperCase with declaration details, preserve saved bytes, and observe real en/he/zh-Hans collators. These are portable causal checks, not iOS or hosted Editor acceptance.

Shell/JavaScript syntax and original source-pin validation passed. Original default lock validation correctly rejects pending binaries; original native reuse verification correctly rejects the old artifact. No new NodeMobile framework was built.

## Required native successor

Independent source and native-linkage review precede any producer. A fresh disposable tree from the exact original source archive is required; an older downstream-prepared source tree is not silently accepted. The existing device and simulator producer, existing full framework assembly and original smoke remain mandatory with their original limits. The new source changes build inputs and needs a freshly built, hash-bound, smoke-validated NodeMobile/RuntimeBundle plus the actual final-source SDK qualification. Old Host188, package619 or UI results do not establish this new binary's behavior.

The original Editor test still must pass on the freshly built runtime. No native execution, fresh binary checksum, whole-app acceptance or production completion is claimed in this packet.


## Source seal and independent review

The unchanged reviewed thirteen-path candidate is sealed at 4c81f6eb701ff1c18cdd5211bff5ea4b857f259a. ROOT_REVIEW.json and MAC_REVIEW.json preserve the exact independent source and native-linkage verdicts. SOURCE_SEAL.json verifies every source payload from the committed Git object, including all six original-source gzip fixtures and the complete upstream license.

The initial seal verifier compared a patch without the original --full-index flag. It stopped before committing. Restoring that exact original formatting produced the frozen patch hash; no source bytes or tests changed. The original stopped receipt is retained in the raw evidence archive.

## Pinned full ICU data, observed after candidate freeze

PINNED_ICU_SOURCE_DATA.json records one read of the original pinned Node source archive, SHA256 614b5f1cb6409d7471b80535d3306a5c4a32ac8128c4a2bd9d8147d663e2555c. The source archive contains the full-ICU data notice, ICU77.1 header and actual compressed data input. That later read closes the source-data availability question; it does not build or link the mobile framework.

## Acceptance boundary

Actual portable adapter controls passed5/5. On each of the unchanged Expo and NativeScript compiler payloads, removing Intl produced three original completion-test failures and one passing path guard; the same four original tests passed with real Linux ICU. Direct unchanged host completion calls returned the actual toUpperCase/declaration candidates, with real en/he/zh-Hans collators and unchanged authored source. All276 compiler/library input files were bound to the retained installed SDK authority.

NodeMobile build, framework linkage, iOS locale smoke, RuntimeBundle assembly and the original Editor UI retry remain NOT_RUN. The lock deliberately marks the dependent Node/RuntimeBundle binary boundary pending-build. Old binary checksums remain historical and the original reuse verifier rejects them for this changed native input identity. The zero direct intersection with396 SDK source paths does not establish native binary or full SDK reuse.

portable-source-evidence.tar.gz retains the original raw stdout/stderr, receipts, exact compiler-file map, unchanged host query scripts and pinned configure/GYP authorities. MANIFEST.json provides every inner raw-byte size/hash and the lossless patch identity. No native command, test assertion, compiler comparator, fixture or version pin was substituted during sealing.
