# ADR 0001: Platform kernel

Status: accepted
Date: 2026-07-23

## Decision

Hanlin will expose one canonical platform kernel to compiled native modules and
dynamic script packages. Identity, manifests, capabilities, permissions,
storage, files, secrets, network, routes, actions, tools, audit, policy, and
diagnostics are implemented once behind typed service protocols.

The kernel begins as focused targets in one local `HanlinPlatform` package.
Concrete AI_HLY persistence, chat, RuntimeCore, MCP, and UI integrations remain
in `AI_HLY/Downstream/HanlinIntegration`.

## Consequences

Runtime engines stay below the kernel. The package cannot import app models.
Adapters preserve current systems during migration. Adding a second
script-specific service or permission implementation is rejected.
