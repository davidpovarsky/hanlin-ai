# ADR 0011: TypeScript compiler versioning

Status: accepted for the full Scripting platform
Date: 2026-07-23

## Context

The authorized Scripting workspace locks TypeScript 7.0.2. The existing Hanlin
runtime host locks TypeScript 6.0.3. The exact original `tsconfig.json` uses
strict CommonJS and classic JSX with `createElement` and `Fragment`.

## Decision

The shipped Scripting compiler is exactly TypeScript 7.0.2. The compiler,
package lock, integrity, configuration, baseline hash, Hanlin ABI, and target
context participate in every artifact fingerprint. Scripting projects use a
full TypeScript Program/incremental project build; one-shot `transpileModule`
is not a compatibility or install path.

RuntimeCore may retain a separately named compiler only for unrelated trusted
developer functionality. It cannot compile installed Scripting packages or
contribute artifacts to their cache.

## Consequences

No source declaration is edited to accommodate compiler drift. Windows-native
compiler executables and local `node_modules` are never packaged. Imported
source is data provided to the trusted compiler protocol; package scripts are
never invoked. Diagnostics, fixtures, language services, source maps, and cache
records identify TypeScript 7.0.2 explicitly.
