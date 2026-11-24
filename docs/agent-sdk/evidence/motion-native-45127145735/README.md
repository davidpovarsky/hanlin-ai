# Motion native build and provenance guard — 23 November 2026

Run [45127145735](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45127145735) at `705f1bd8` passed its real Xcode 27.2 test build. The exact original Equatable macro pin was admitted before compilation. The canonical ChatUI sources and original Motion test target compiled.

The post-build source recorder then rejected the authentic directory symlink `.claude/skills` from `hanlin-streaming-markdown` at `5cbb4b6c`. Its Git mode is `120000` and its 17 source bytes are `../.agents/skills`. The recorder incorrectly required a regular file before handling links. Original B/C tests did not start, so this is not an animation failure and no screenshots were produced.

The fixture now records symbolic-link target bytes and verifies their Git object/mode. It retains all tracked paths, does not traverse link destinations, and continues to reject missing regular files, changed link text and changed path types. All eight real resolved dependency trees were inspected: only the three documented links are present, and no Git submodule entries occur. Six focused controls passed using the authentic upstream link bytes and deliberate malformed cases.

The complete ZIP was downloaded once and verified against the API size/digest. Original successful build tail, raw failure excerpt, macro admission, resolved pins, upstream link identities and focused controls are retained here. The full original build log and source archive remain in the authenticated native artifact. `receipt.json` binds the exact source and evidence limits.

Native B/C execution remains pending. The original A cycles and diagnostic D have not been dispatched.
