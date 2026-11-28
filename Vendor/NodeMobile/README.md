# Node.js Mobile runtime

Hanlin uses the verified Node 24.5.0 iOS XCFramework built from `heylogin/nodejs-mobile` tag `v24.5.0-mobile` at commit `4768489cd0cfa3bb0c27786e958c6446c004f1bd`.
The generated `NodeMobile.xcframework` is intentionally not stored in Git because of its size.

Run from the repository root before opening/building the Xcode project:

```sh
bash Scripts/Runtime/prepare-runtime-core.sh
```

The script downloads the immutable same-repository RuntimeCore release selected by `RuntimeDependencies.lock.json`, verifies the bundle checksum and Node XCFramework checksum, and installs the framework here. `Scripts/Runtime/prepare-runtime-host.sh` separately packages the current JavaScript host as `AI_HLY/RuntimeHostResources.zip`; it does not rebuild Node.
