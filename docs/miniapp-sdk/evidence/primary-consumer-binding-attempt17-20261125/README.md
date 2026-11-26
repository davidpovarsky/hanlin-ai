# SDK16 consumer and notification-extension binding

The immutable Mac capture on source cffe7f75436aa2e37ec5d82891937965c0407d2d records both completed consumer builds and both original deep/strict signature verifications as successful. Oracle verified all six raw files, parsed both actual built Info plists and reconciled all five recorded Host resource copies to the independently verified SDK16 archive.

The five resource copies contain the same 81,823,972-byte Host ZIP (4c71d23f...), SDK manifest (0ef02a70...), 235-input identity (d381e9db...) and authoring module (fa512190...). Full identities and exact copy paths are in reconciliation.json.

Both built notification extension plists match the source host configuration. MiniApps uses HanlinMiniApps/v1; the AI extension retains the original unnamespaced host configuration. Both declare the original notification-service extension point and their actual product-specific principal class. The existing simulator entitlement reader records both AppGroups from the executable's Mach-O section. The ad-hoc code-signature entitlement dictionaries are genuinely empty; they are not substituted for simulator entitlements.

The original packet binds each extension's 37,888-byte entitlement-bearing executable. A separate immutable observation at 07:42:38.931900 UTC additionally binds the MiniApps 21,564,144-byte debug dylib and AI 28,194,512-byte debug dylib. Both records are retained unchanged; the second completes the implementation-image inventory without rebuilding either product.

This is resource/configuration and retained-command reconciliation. It does not claim that the original 52 cases passed, that the OS invoked either extension, or that a simulator result proves APNs-provider or physical-device delivery. The previous collector failure is preserved separately; the correction uses the original simulator reader and the actual nested HanlinExtensionHost dictionary.
