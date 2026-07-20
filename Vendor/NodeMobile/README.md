# Node.js Mobile runtime

Hanlin uses the official iOS binary from the `nodejs-mobile/nodejs-mobile` release `v18.20.4`.
The generated `NodeMobile.xcframework` is intentionally not stored in Git because its simulator slice exceeds GitHub's regular file limit.

Run from the repository root before opening/building the Xcode project:

```sh
bash Scripts/MCP/bootstrap-node-mobile.sh
```

The script downloads only this pinned asset:

- URL: `https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v18.20.4/nodejs-mobile-v18.20.4-ios.zip`
- SHA-256: `8c5ca3a0d1e38de7f182a5642593e82593b820efd375a14b3ecafc4bcfee620e`

It verifies the checksum, installs `NodeMobile.xcframework` here, downloads the pinned upstream license, installs the locked host dependencies with lifecycle scripts disabled, and creates the deterministic-input `AI_HLY/MCPHostResources.zip` resource.
