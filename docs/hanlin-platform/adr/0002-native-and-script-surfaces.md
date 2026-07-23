# ADR 0002: Native and script surfaces

Status: accepted
Date: 2026-07-23

## Decision

Compiled Swift modules and runtime-installed TS/TSX packages are separate SDK
surfaces over the same kernel. One application descriptor and catalog represent
native, script, and hybrid implementations.

Native modules use explicit registration and scoped contexts. Script packages
use versioned manifests and bridge values. The exact original `scripting`
module is the compatibility surface; `hanlin` is the separate Hanlin-owned
extension surface.

## Consequences

The Apps Hub may filter by implementation but does not create disconnected
products. Existing native modules migrate through adapters. Original Scripting
imports do not require mass rewrites. Availability remains distinct from
declaration presence.
