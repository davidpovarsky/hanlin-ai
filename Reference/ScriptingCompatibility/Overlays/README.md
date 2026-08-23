# Hanlin-owned overlays

Hanlin additions and module augmentations belong here or in a later canonical
Hanlin IDL output. Imported files under `Original/` must never be edited.

`compatibility-classification.json` is the Hanlin-owned classification layer
for every immutable declaration record. Its declaration-file defaults make
missing runtime work explicit as `not-yet-implemented`. A symbol override may
claim `partial` or `implemented` only with a Hanlin symbol, observable behavior
notes, and repository test evidence. `unsupported-by-platform` additionally
requires a concrete rationale; it is not a synonym for unfinished work.

The generator merges this overlay into the immutable inventory and emits the
canonical matrix. `verify-compatibility-classification.mjs` rejects
`planned`/`unknown`, incomplete partial claims, and missing test paths.
