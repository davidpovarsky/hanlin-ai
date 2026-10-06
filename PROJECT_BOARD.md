# Project Board

This is a living working-memory document for this repository.
It is intentionally lightweight. Humans and coding agents should update it when useful discoveries, ideas, plans, optimizations, problems, or follow-up work arise during normal development.
Do not turn this into a duplicate issue tracker or a dump of temporary thoughts.

## Inbox

Quick captures that still need classification.

## Ideas & Opportunities

Potential improvements, features, optimizations, or architectural ideas.

## Discoveries & Tips

- **Modular React Cxx Header Compilation in Swift Frameworks**: When compiling modular frameworks imported into Swift (such as `ExpoModulesCore`), Clang builds underlying C++ modular headers under Objective-C++/C++17 by default unless `-std=c++20` is explicitly enforced across all targets. Any C++20 `concept` declarations (e.g., `RawPropsFilterable` in `RawProps.h`, `DeclaresOwnSetProp`/`HasSetProp`/`HasIteratorSetterCtor` in `Props.h`) must be guarded with `#if defined(__cpp_concepts)`. In addition, `folly::dynamic` stubs used in isolated module contexts must supply range iterators (`begin()`, `end()`), item key checks (`isString()`, `getString()`), and value-casting operators to satisfy `RawValue.h`.

## Experiments / Investigations

Things worth testing or researching before deciding whether to implement them.

## Open Questions

Important unresolved questions or uncertainties.

## Planned / Todo

Concrete work that is worth doing but is not part of the current task.

Use Markdown checkboxes where useful:

- [ ] Example item

## Done

Completed items that are still useful to retain because they document an important decision, discovery, or implementation.

Example:

- [x] Example improvement
  - Implemented: YYYY-MM-DD
  - Commit/PR: ...
  - Notes: ...

## Archive

Older completed/superseded items that still have historical value.
