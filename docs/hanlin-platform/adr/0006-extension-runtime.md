# ADR 0006: Extension runtime

Status: accepted; implementation gated to Phase 13
Date: 2026-07-23

## Decision

Apple extension contexts use separate targets and an extension-safe
`HanlinExtensionRuntime`. The main app validates and precompiles restricted
artifacts; extensions validate immutable App Group artifacts and run only their
supported subset.

## Consequences

Extensions cannot assume NodeMobile, Python, shell, app memory, app-only
services, interactive permission prompts, or unlimited time. App Group,
entitlements, and targets are added one family at a time only when that phase
begins and signing implications are documented.
