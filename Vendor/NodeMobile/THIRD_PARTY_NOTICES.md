# Third-party notices

## Node.js Mobile 18.20.4

Copyright Node.js contributors and the Node.js Mobile contributors.

The primary Node.js license is MIT. The complete license and notices for bundled Node.js dependencies are preserved from the pinned upstream tag by `Scripts/MCP/bootstrap-node-mobile.sh` as `NODE_LICENSE.generated.txt` and are distributed with the prepared runtime.

Official source and license: <https://github.com/nodejs-mobile/nodejs-mobile/tree/v18.20.4>

## Embedded host dependencies

The host uses the exact versions in `AI_HLY/Downstream/MCP/Runtime/Host/package-lock.json`. Each package's license file is retained inside the generated `MCPHostResources.zip`:

- `@npmcli/arborist` 8.0.5
- `pacote` 20.0.1
- `semver` 7.8.5
- `ssri` 12.0.0

All selected direct and transitive packages declare an engine range that accepts Node 18.20.4.
