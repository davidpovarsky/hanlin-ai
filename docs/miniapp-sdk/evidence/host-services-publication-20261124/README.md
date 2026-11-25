# Expo Host Services publication and installed actions

The baseline positional publisher retained a legacy tree in a path with no reader.
The retained source search is `baseline-orphan-writer-search.log`. No original
Expo layout, renderer or WidgetKit surface is replaced by this change.

The tagged overload commits complete props to the actual prepared Expo instance
state under the existing store lock. The original program consumes that state.
A session-owned callback binds the operation to the correct installation and
generation, including independent external MiniApp scenes. The receipt reports
persistence, catalog and reload-request facts; `osRendered: null` is deliberate.
The legacy storage/wire remains compatible and now reports `published: false`.

## Executed here

- Actual facade transport: one red case, then one pass, zero skips. Its native
  transport is a protocol test double; this proves the public JSON boundary only.
- Existing source-operation audit: two red cases after the initializer changed,
  then two passes. Exact callback/generation and missing-operation negatives stay
  strict; this is source evidence, not a runtime pass.
- Swift syntax and builder syntax pass. Apple module typechecking is pending.

## Native acceptance prepared

Two named hosted tests install the actual freshly built Metro archive through the
production importer. They wait for real JavaScript action replies/errors. The
publication test calls the public facade inside the actual bundle, reopens the
real store and checks that the original Expo layout consumes the committed props.
No test substitutes a native provider, synthesizes an acknowledgement or treats
a reload request as an OS render. The existing synchronized AI_HLYTests group
includes the new source/resource automatically; no project target changes are
required. Root owns selector integration and Apple execution.

The public authoring guide documents the overload and receipt. Live Activity
mutation wrappers and Expo external-sharing wrappers remain outside the new
native evidence, as recorded in `receipt.json`.
