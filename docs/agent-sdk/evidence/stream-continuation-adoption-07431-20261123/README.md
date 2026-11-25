# Adopt the shared completed-tool continuation repair

The unified SDK now pins the existing SwiftAI producer07431abccbfb151ca2dab67bca6cf86fcb2bd3b8 in place of e7bf34111e603ca977becd007dd4e5bb109af857. The exact upstream production change and source-enforced successful Apple evidence are retained in ../release-readiness-45256955142/swiftai-07431.

Only the producer's existing private StreamTextActor.shouldStartAnotherStep changes in production: completed client-tool outputs or pending deferred calls determine whether to consult the unchanged stop conditions. A compatible provider's stop finish label no longer incorrectly ends a tool-bearing step. There is no transplant of the divergent Otzaria Host, new engine, provider API, transport or authentication change.

## Integration

Nine existing manifest/lock files receive one exact revision replacement each. The original full-profile generator produces the tenth operative replacement in root Package.swift and changes only the two expected manifest input digests in the canonical inventory.

-44 public products,108 targets,507 original application Swift source files,18 original manifests and zero local package edges remain.
-Every operative pin file is byte-identical to its old version after inverting just the one revision replacement.
-Every other dependency pin/settings field remains unchanged.
-The three generic HEAD-bound IntegrationValidation routes now clone/verify the current07431 producer. The producer fetch is by exact SHA, no longer dependent on an old branch containing a future descendant.
-Frozen native candidate/baseline evidence and the tool-policy JSONValue fixture retain their original e7 attribution. JSONValue is byte-identical across the two producers; historical evidence is not relabeled.

The peer reviewer verified the complete10-file substitutions, actual18 input hashes and unchanged counts, and found the three generic CI route assertions that were then updated. Shell syntax parsing passed for those three changed routes. No application or upstream test suite was replayed during this edit.

## Acceptance boundary

The upstream successful4185-method gate and six focused invocations retain x86_64 macOS26/Xcode26.6 scope and the original authenticated owner's evidence. This adoption does not turn them into new arm64 iOS27 execution.

The original full-app selection still has342 NOT_RUN invocations. The next necessary run must bind this producer. The existing EventKit case performs actual inline-tool execution between owner streams; it does not exercise provider-issued tool-call followed by a stop finish. Three new original-engine delta cases are being prepared separately for approved tool, denied tool and rejected native numeric input under that finish label.

The Native18 preparation input set is unchanged. All three Host dependency profiles and final installed pins nevertheless require current integration qualification. No final Host native pass, publication, release or task completion is claimed by this adoption.
