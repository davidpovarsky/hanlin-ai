# Original ios_system resources in both app bundles

The finalized MiniApps host-services case failed because the original ios_system initializer could not find commandDictionary.plist in Bundle.main. The actual AI app contained both canonical dictionaries; MiniApps contained only the package resource bundle. The existing validator independently passed AI and failed MiniApps on these exact built products.

The canonical SDK project generator now adds two raw-text resource copies to MiniApps, using the original source file references. The generated project companion adds only those two build files and two phase memberships. The existing source validator checks both app targets; the existing paired product loop applies its byte-exact built-bundle validator to both products before installation.

The focused original resource suites passed 12 tests with no skips. The actual prepared project fails the new source gate before projection and passes after projection; a second projection is identical. The first candidate's parser bookkeeping failure is retained, followed by the corrected regression output.

No command catalog, runtime implementation, restriction, selector, assertion or test deadline changed. Rebuilt native consumers and the failed actual runtime case still require execution. This source proof is not a native acceptance pass.
