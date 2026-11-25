# GSD and Lorvex SDK integration — 24 November 2026

## Source and integration

- Latest integrated SDK/MiniApps base: `788354f8e9e863eb5e4c9007a8b58ea71d028b19`.
- Canonical Sign in with ChatGPT donor: `db7dc3a3a545bd41cf7b481bc184a6f9b19515db`.
- Selected compatible public APIs and diagnostics retained from `caa4faa509ebf5ba4164408734bb6e0dd3662203`.
- Local integrated regression source: `383419e77b4a88b00836499f196bd9ef5fcf6aaa`.
- Local native-tested production source: `f87d14f874994e6dfd38a48b91c76c3f568ba113`.
- Publication through the GitHub connector can create a different commit ID with the identical tree; the published tree must equal the local delivery tree. Receipts contain every original source input SHA-256 so native evidence remains verifiable after publication.

The dedicated plan route uses `apiType: "openai-chatgpt-plan"` and `https://api.openai.com/v1`. Ordinary `openai-responses` keeps ordinary Responses behavior. Canonical `hanlin` tool namespaces, exact streamed provider bytes, completed-event requirements, subject-bound account registration, refresh single-flight/rotation and revocation deduplication remain intact. Public `earliestRefreshAt`, OAuth error diagnostics, explicit authorization hints/consent, `prepareRequest` and `makeFetch` remain available. Strict route and callback checks from the earlier GSD SDK are retained. The token response requires `token_type: "Bearer"`; revocation discovery requires the OpenAI issuer and same trusted endpoint origin.

The unified SDK dependency is `swift-ai-sdk` revision `07431abccbfb151ca2dab67bca6cf86fcb2bd3b8`. Hosts that directly import provider test utilities must use that same dependency identity/revision.

## Persistence repair

Darwin provides `/var`, `/tmp` and `/etc` aliases to corresponding `/private` directories. The original private store rejected these ancestors, so a valid new store under `/var` and an existing record addressed through that alias failed with `invalidRecord`.

The store now resolves only a known system prefix with native `realpath`, verifies the result is the same physical directory or its expected `/private` spelling, and appends the untouched private suffix. It never resolves arbitrary private root, parent, namespace or record symlinks. Existing component checks remain in place, and no stored record is moved, migrated or rewritten by initialization/load. The format, namespace encoding, conversation identity, compare-and-swap revisions, checkpoint behavior and iOS file protection are unchanged.

## Native evidence

Runner: new Scaleway Apple silicon Mac, Xcode 27.0 build 27A266a, Swift 6.4 (`swiftlang-6.4.0.34.1`), Swift 6 language mode for SIWC. No simulator or live account was used.

| Check | Before | After |
|---|---|---|
| New `/var` root: missing-store load, save, physical-path reload, update, alias reload, delete | `invalidRecord` | Pass |
| Existing version-one record: alias reload preserves record identity and exact bytes | `invalidRecord` | Pass |
| Private symlinks at root, ancestor, namespace, record, dangling root: load/save/delete reject, original bytes preserved | 5 cases pass | 5 cases pass |
| Existing version-one checkpoint/restore and unknown future-version rejection | Pass | Pass |
| Canonical SIWC OAuth/wire native contract | Donor evidence reused for context | 16 checks pass on integrated original source |

The persistence result is four Swift Testing functions, one parameterized into five cases: eight scenario executions. Before the fix exactly the two system-alias tests failed; afterward all passed. Original `HanlinPlatformContracts`, `HanlinHostContracts` and persistence adapter sources were copied byte-for-byte into an isolated dependency-free SwiftPM closure with the original resource processing rule. Every input digest is recorded. The first harness attempt omitted the resource declaration and failed at `Bundle.module`; the corrected harness then produced the behavioral before/after proof above. No production source was substituted to make the harness compile.

Reproduction from the SDK repository:

```sh
python3 Scripts/Tests/run_private_store_tests.py --output /path/to/new-proof-directory
swiftc -swift-version 6 -parse-as-library \
  Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatGPTPlanClient.swift \
  Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinChatGPTPlanWire.swift \
  Scripts/Tests/verify_chatgpt_plan_contract.swift -o /path/to/siwc-contract
/path/to/siwc-contract
```

## Installer

Canonical installer artifact: `Scripts/SDK/install.py`.
SHA-256: `4cf99955317a83e3d882834fe0235f505af41e335fd1e84e475524081d301677`.
Use the final published full 40-character SHA in each host lock. Use the existing selected-product installer and compare its receipt with the lock; do not vendor alternate source implementations. Installer command/flags are discoverable using `python3 Scripts/SDK/install.py --help`.

## Scope

These results close the shared private-store alias defect and establish the integrated native SIWC contract. They do not claim either host app's integration/build/UI/release gates, physical-device proof, a live OpenAI account test, or full broad SDK/MiniApps acceptance. Host owners own those remaining gates and their app pins.
