# Authoring correction: embedded Host and SDK impact

Read-only audit of published source 77971ea159ed54a473f3c1536edfcd1c6d6e446c, whose inspected production files match actual attempt6 source bd6da170da7936fe3c5353ddaf8b25c97477a380. The candidate resolver correction belongs to the native execution owner; this audit makes no new compiler or application claim.

## What must update

The production module is AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs (current SHA-256 d89d2ed4337e56f95b5f4815987281048c68f05ac60f31ba5e2f7f97d7312856). It ships at the top level of RuntimeHostResources.zip. It is not a direct MiniAppSDK member/input, but the exact module SHA occurs in source-inventory.sources and reachability.sdkSources. These documents are direct SDK inputs. Consequently the correction affects both the outer Host payload and the indirect SDK manifest/input identity.

The existing Host producer refreshes those audits **before** checking reuse, fingerprints all Host source and tests, stages the SDK and performs its original Host/archive checks. Retain that producer and the existing copy to AI_HLY/RuntimeHostResources.zip, actual-archive documentation check, native artifact export/verify, input capture and paired acceptance sequence. No new pipeline is needed.

The native catalog's direct16 input list is not sufficient for this change: HanlinNodeHostSupport contains the Host ZIP, and its checksum contributes to catalog contentSHA256. Export/verification updates resource provenance without compiling unchanged native frameworks.

## Why source CLI success is insufficient

miniapp.mjs and prepare_authoring_fixture.mjs directly import the source module. App authoring instead uses the embedded Host ZIP. MiniApps copies that resource directly; the shared AI_Hanlin package copies the same original archive as a package resource. The original incremental product builds/sign/install must deliver changed bytes to both consumers.

NodeRuntimeService selects an extraction directory named for the bundled archive SHA, and installed identity also includes that archive. Thus fresh installed resource bytes select a new Host. This is source behavior, not an assertion that the upcoming candidate has already run.

Do not stop at the earlier RuntimeCore source-only sync: its module-overlay route can retain an otherwise accepted old SDK if provenance has not been regenerated. The existing final Host hook and copy resolve that distinction.

## Scope and evidence

receipt.json contains18 exact source-file SHA-256 values, line ranges, actual SDK inventory bindings, the retained original phase identity and the minimal existing regeneration sequence. No production source changed and no generator/compiler/test/native query ran here. Unchanged native binaries may retain authenticated exact prior evidence; changed authoring behavior and pending selected application cases remain for the owning execution lane.
