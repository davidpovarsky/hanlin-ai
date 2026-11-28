# Original direct-request fixture correction

Base: `d165b9fc6a1c4e810a21957c063bfeae52eecb59`.

The original simulator run `45977172889` on `466c6187` exposed `.staleContext` from direct remote-provider tests. All 16 direct `sendStreamRequest` calls in these three test files omit the canonical original-owner request. The current production provider route requires `requireDataAccess()`; the two production callers already construct the request from their actual original conversation and assistant row. Those production files and guards are unchanged here.

## Exact scope

- Add one test-data fixture inside an existing test file. It inserts and saves an actual `ChatRecords` object, keeps one scene and conversation for that APIManager, creates and saves a fresh assistant `ChatMessages` row for each existing group/run, and constructs the production `HanlinAppAgentSessionOwner.Request` using those identities.
- The fixture checks the actual original conversation with the production store validator and fetches the persisted assistant to require exact object, group and parent identity. These two additional setup requirements do not replace any original assertion.
- At the 16 existing calls, materialize each existing fresh UUID once, preserve already-named IDs, retain all original request arguments, and add the explicit owner request. Native-only scope retains all original flags and only gains the bound conversation ID.
- The five reused-manager relationships retain one fixture: the two remote supersession cases, the conformance second-turn history case, the local streaming/cancellation case, and immediate local cancel/restart. P12A receives the same fixture in its existing result tuple's result object; no new manager, owner, provider or engine is introduced.
- Setup for the provider-error case occurs outside its existing expected-error catch. Setup for task-based cases occurs before the original task launch. The original task bodies, error handling and cancellation actions otherwise retain their original ordering.

## Preservation and verification

The patch changes setup and call argument expressions, so it does **not** claim literal unchanged test bodies. The source audit applies a documented inverse of precisely those additions/argument substitutions and recovers all three original files byte-for-byte. This proves every other statement, original assertion, fixture response, timeout and ordering is unchanged. The original 363 `#expect` and 31 `#require` occurrences remain, with two added saved-row setup requirements. All 49 original selectors and 16 direct calls remain.

The portable audit rejects eight concrete source mistakes: wrong owner request, run mismatch, group mismatch, lost scope identity, missing assistant save, a replacement P12A conversation, a weakened original deadline, and a removed ghost-work assertion. These are source qualification controls, not a substitute for Swift compilation or native acceptance.

Production code, permissions/approval behavior, model lookup/selection, URLProtocol responses, test selectors, budgets and workflows are unchanged. No UI08 or model-record-race correction is included. Additional independent native failures, if exposed once the requests enter the real provider path, remain subject to their original assertions.

Native compilation and all original Swift cases remain NOT_RUN on this candidate; the original native gate is required.
