# NativeScript metadata framework discovery repair

The original full app build in [45230545076](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45230545076) passed three original AppIntents target exports, then failed genuine Clang duplicate-module detection for libssh2. The [authenticated original artifact](../appintents-export-libssh2-45230545076/README.md) binds the exact source, both same-XCFramework staging actions, raw search arguments and error. All 310 selected method definitions / 342 authored invocations remained NOT_RUN.

## Change

The existing metadata wrapper now supplies a temporary, ordered framework search view to its child process. The original ownership resolver is shared with umbrella generation. It checks every reachable public/private header and module-map digest before coalescing copies, keeps original search priority, retains all unique frameworks and real symlink alias spellings, and rejects differing declarations. Each unique name has a separate temporary search directory, preserving the existing React/react framework families on case-insensitive macOS volumes. Duplicate libssh2 spelling/interface occurrences reuse the first physical owner.

The reason this must cover search paths is in pinned NativeScript source 5d4569c197810cdd4c1e02e7c16d42a01a77d5c0: HeadersParser/Parser.cpp collects modules from all -F roots and then adds -idirafter for plain modules such as libssh2. Filtering the host umbrella alone does not prevent the second module map from being discovered. The wrapper retains the original generated umbrella, SDK default/subframework handling, -I paths, actual native generator, serialization format, provenance checks and fatal-Clang completeness check. Xcode products, package dependencies, binary targets, app linking and runtime capabilities are unchanged.

FrameworkSearchView.inventory.json retains both original interface manifests, selected physical ownership and temporary search paths. Failure retains that inventory and original tool provenance; the wrapper removes only its owned temporary directory.

## Verification and limits

Five new targeted controls cover same-producer plain-module duplicates with unique frameworks in both roots, changed transitive-header rejection, copied aliases, actual symlink aliases and distinct React/react owners. Eleven affected existing controls preserve original umbrella/public/private/module identity/error behavior. All 16 passed on Oracle in 0.076 seconds. The original wrapper integration control now inspects the real child environment with a duplicate-framework fixture.

The initial three new API cases errored because that API did not yet exist; this is recorded accurately and is not presented as a native-Clang reproduction. An independent read-only review found and resolved alias and case-folding risks before the final controls. No accepted native test was replayed for this review.

Actual Apple framework-manifest equality, metadata generation, complete app build and all selected native test invocations are still NOT_RUN for this repair until the next exact-source native continuation. This repair does not make the failed producer eligible for Native asset publication.
