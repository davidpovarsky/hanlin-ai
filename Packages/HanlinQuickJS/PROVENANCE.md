# Hanlin QuickJS source dependency

This package vendors the minimal QuickJS-NG library source set required by the
Hanlin isolated Scripting runtime. No CLI, standard-library host modules,
dynamic modules, or runtime downloader is included.

- Upstream: `https://github.com/quickjs-ng/quickjs`
- Tag: `v0.16.1`
- Commit: `954dc53628e36891f93c359aa60895c2ae3dac6b`
- Source archive SHA-256:
  `4b3c11f37dab2c58bdeccbaeb23b923fa4a9798a45e50be6af55f3e75b616ea0`
- License: MIT, reproduced in `LICENSE`
- Imported sources: `quickjs.c`, `dtoa.c`, `libregexp.c`, `libunicode.c`,
  and the headers those translation units require.

The library is built from source by Swift Package Manager for each Apple
destination. Hanlin's wrapper creates a bare `JS_NewContext`; it does not link
`quickjs-libc.c`, `qjs`, or `qjsc`, so the engine has no filesystem, process,
environment, network, or dynamic-module host API.

Downstream patch: the allocator records when the configured QuickJS memory
ceiling rejects an allocation and exposes a namespaced reset/query pair to the
Hanlin C wrapper. This preserves typed memory-limit errors even when QuickJS
cannot allocate its own `out of memory` exception object.
