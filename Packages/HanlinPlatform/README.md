# HanlinPlatform

`HanlinPlatform` is the downstream, app-independent platform package defined by
the Hanlin execution contract.

Phase 1 exposes one real target:

- `HanlinPlatformContracts`: validated identifiers, contract/package versions,
  deterministic `HanlinValue`, recursive JSON schema values, application
  descriptors and validation, stable platform errors, and the versioned script
  wire envelope.

The package targets iOS 26 and Swift language mode 6. It imports no AI_HLY app
model. The bundled `HanlinAppManifest.schema.json` is the machine-readable
structural manifest schema; Swift validation enforces semantic conditions such
as supported versions, canonical IDs, safe entry points, uniqueness, schema
validity, integrity format, and required contexts.

Future targets are added only when their phase has functional implementation.
This package deliberately contains no empty service, native SDK, runtime, UI,
catalog, or tooling targets.
