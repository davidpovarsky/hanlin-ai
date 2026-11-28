# P01 real runtime consent fixture

The original P01 provider-conformance case now opts into the existing scripted consent participant used by the Conversation acceptance fixtures. It still exposes the real tool through load_skill, executes the real Python source, requires42 in the next provider request, and checks final completion through the original validators.

The production consent implementation is unchanged. The test participant answers only an exact pending scripted call bound to the current owner, conversation, scene, persisted row, UI run and canonical run. It uses the real consent.answer entry point, preserves the owner's callback and pre-existing grants, and removes only grants it created when the conversation helper exits.

Only P01 enables the new default-false helper option. Every other provider caller, the raw protocol fixtures and malformed-input cases retain their original behavior. The participant's implementation is byte-identical; only its test-module visibility is extended.

## Evidence and limits

The two source files preserve all30 original test annotations and212 original assertions. One additional UTF-8 requirement admits P01's existing scripted responses to the existing parser. A four-substitution inverse recovers both complete preimages. The source change intersects zero SDK inputs and no product/package source. No Swift, native, SDK or portable test execution occurred for this candidate.

The old9a failure remains recorded: P01 failed its original Python42 round2 validator after31.003 seconds. Its actual tool-denial payload was not printed, so this is a source-supported fixture repair, not a retrospective claim about an observed denial.

Remembered grants are deliberately scoped to app/account/workspace/tool/manifest/permission, not to a conversation. The participant's answer is request-bound, but the durable grant may be shared with another matching owner. The original nonparallel CLI flag and observed old non-overlap are retained as evidence without claiming they prove global Swift Testing serialization in installed Xcode27.2. No new global mutex, approval bypass or timeout change is added. The original native route must retain actual suite outcomes and disclose any real overlap.

The separate TypeScript worker-entry failure follows the direct runtime-service path and receives no consent opt-in from this change.

## Source review

Source donor:497e25fafd27cc5801dcf1f65c326450065bd5e4, based on3634078f89c5fa469199da1f69d6f4bad6686d96.

The independent root review is retained verbatim. Native acceptance is still NOT_RUN for this donor. The original exact selector and expected business results are recorded in native-verification-plan.json; a listed or zero-case test is not a pass.

The compressed source patch is lossless. Every manifested proof payload is verified against its committed Git object when this proof is sealed.
