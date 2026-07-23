# ADR 0007: Distribution policy

Status: accepted
Date: 2026-07-23

## Decision

The platform models `personalDevelopment`, `enterprise`, `testFlight`, and
`appStoreRestricted` distribution modes. Mode controls catalogs, new dynamic
functionality, source visibility/editability, remote updates, native
capabilities, extension execution, consent, and indexing. Production defaults
are conservative.

## Consequences

Scripting compatibility is not evidence of App Review approval. Unsupported or
approval-dependent features remain visible in compatibility metadata with
structured reasons. No release or App Store approval claim follows from this
architecture decision.
