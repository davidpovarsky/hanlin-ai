# Prepared widget last successful render

## Implemented scope

Prepared Expo and original ScriptWidget widget programs now retain their last successful typed node when a later render of the same currently authorized program fails. Cache references live in the existing extension snapshot, and payloads use the existing content-addressed, atomic, no-symlink verified artifact store. The cache does not persist native action contexts or resource URLs.

Preparation still validates current widget identity, installation/generation, active instance, expiration, program SHA, state SHA, and current resources before considering fallback. Cached metadata additionally requires the same engine, family and instance settings. Disabled, removed, expired, changed-program, different-generation or changed-settings widgets cannot recover stale content through this cache. A failed ScriptWidget render leaves committed state and the last success timestamp unchanged.

Host republish and snapshot replacement retain cache metadata. Uninstall drops references with the removed installation. Previous snapshots decode with an empty cache. The v1 compatibility writer strips this new v2-only field alongside the existing v2 registry/state fields, and downgrade recovery retains committed cache metadata.

## Evidence and remaining acceptance

- Source syntax check: PASS, exact six source/test files listed and SHA-256 hashed in `prepared-widget-lkg-source-receipt.json`.
- Whitespace/patch check: PASS.
- Native suite added: `HanlinWidgetLastSuccessfulRenderTests`, four test definitions / eleven cases (two native engines, seven invalidation reasons, corrupt bytes/uninstall, preceding snapshot/copy preservation).
- Native suite execution: **NOT_RUN**. The suite uses the actual JavaScriptCore runtime and verified store. No fake runtime or Linux test-double result is claimed.
- Apple app/extension build, configured WidgetKit refresh, crash/restart and iPhone/iPad device behavior: **NOT_RUN**.
- Original Expo Widgets timelines are owned by the separate widget implementation lane; this change is the prepared program path only.

Run this focused suite on the root-owned Apple candidate after integration. Do not duplicate the active PR19 full acceptance gate. Include the existing legacy store compatibility tests in that owner's next compatible verification because snapshot metadata changed.
