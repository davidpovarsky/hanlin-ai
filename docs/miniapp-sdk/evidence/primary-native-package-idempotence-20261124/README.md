# NativeScript shared package idempotence

Attempt 3 failed before Expo JSI, RuntimeCore or either application build. The original shared-runtime normalizer reordered the already-generated host-services package, so the next strict generator check correctly rejected byte drift. The manifest values were unchanged.

The correction preserves an explicit own `type` and its original bytes. Packages without it still receive the existing first-position module default. The actual old function reproduced the captured 147-byte drift; the corrected production function was loaded unchanged with its filesystem imports and exercised twice. The original TypeScript 5.9.3 generator repaired the owned package through `--write`, and its unchanged `--check` passed after two actual normalizer passes. Other prepared tracked bytes were preserved.

`focused-result.json` retains all prepared path hashes, commands, timings and exact production function hashes. This is focused Node/TypeScript and filesystem evidence, not full native preparation or application acceptance. The corrected original JSI selection and RuntimeCore artifact route remain pending. Root must integrate the reviewed source and refresh current provenance before the single native resume.
