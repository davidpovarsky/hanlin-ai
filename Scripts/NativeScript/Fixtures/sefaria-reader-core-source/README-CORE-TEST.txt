Sefaria NativeScript Core test package
======================================

This is a rewrite of the supplied Sefaria NativeScript MiniApp using
@nativescript/core for the main UI, layout, navigation and HTTP layer.

It intentionally has a different manifest name ("Sefaria Library & Texts (Core)")
so it can be compared side-by-side with the original direct-UIKit package.

Important packaging note:
The Hanlin host already links NativeScript Core native support, but this archive
contains a package.json dependency on @nativescript/core 9.1.0 rather than a
vendored node_modules copy. If Hanlin's current importer does not bundle/resolve
that JS dependency, launch will fail with a module-resolution error. That would
mean the next repo change is to bundle @nativescript/core for imported
NativeScript packages; it is not a limitation of NativeScript itself.
