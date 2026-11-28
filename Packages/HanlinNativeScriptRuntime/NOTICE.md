# NativeScript provenance

This package links the official `NativeScript/ios-spm` `9.1.0` release
(`a8e26efad02d792a62d2d015f0f7a632e336b2d1`) and its NativeScript iOS runtime
asset SHA-256 `7fe4225faf085c61cef93d7faaa6c70fa3c97bf0631d53f4c868eea2d819c209`.

`NativeScriptEmbedder.{h,m}`, `NativeScriptUtils.{h,m}`, and
`UIView+NativeScript.{h,m}` are derived from `NativeScript/NativeScript` tag
`9.1.0-core` (commit `35b0add1a879bf28acbde371a3b6868dfde77e26`). They are included under the
upstream MIT license reproduced in `LICENSE-NATIVESCRIPT`.

The Hanlin runtime host, lifecycle wrapper, and validation code are downstream
integration code and are not copied from NativeScript.
