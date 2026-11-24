# Expo widget option and publisher type correction

MAIN14 reported two compiler errors in the widget options source: a second
optional chain on AppIntents' already-unwrapped parameter and a HanlinObject
returned where the public method promises a Swift Dictionary. The independent
source review found the same object-to-dictionary mismatch in the prepared
widget publisher adapter before its declared callback.

The query now keeps only the optional dependency access. Option processing
continues to use the original byte-exact HanlinObject and the complete original
validation/selection/mutation loop. A checked conversion occurs only at return.
The adapter converts immediately before the unchanged publisher callback.
Both conversions throw the existing duplicateObjectKey error when distinct
UTF-8 keys cannot be represented as distinct Swift dictionary keys. This also
covers a canonical alias introduced by an explicitly selected parameter.

## Focused evidence

One compiler/executable probe passed on the primary Mac with Swift 6 and C++
interoperability enabled. It imports the actual AppIntents, CryptoKit and
Foundation frameworks. The relevant original entity/query/configuration and
value/conversion bodies are compiled from the current source. Eight assertions
cover value types and override precedence, representation collisions, existing
option errors, callback arguments/result and rejection before callback.

The Expo lookup/registry and localization bundle are explicit project fixtures.
The original Expo engine, storage, complete target, application and simulator
acceptance are outside this probe. The previous authentic value/error module
is reused only after source and toolchain identity checks; it was not rebuilt.

Raw source inputs, precise exclusions, SDK interface paths/hashes, current Mac
capacity, command output and original failure excerpts are retained here.
The installed primary-Mac toolchain remains Xcode 27.0, while the full gate
requires 27.2. Root owns that fallback and the unchanged 52 native cases.
