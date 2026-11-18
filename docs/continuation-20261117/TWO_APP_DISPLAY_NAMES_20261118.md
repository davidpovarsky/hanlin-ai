# Two-app displayed identities — 2026-11-18

The original paired-run SpringBoard screenshot showed the AI app as ChavrusaChat, while the approved product split specifies Hanlin AI and Hanlin MiniApps.

The AI target's Debug and Release display-name settings now use Hanlin AI. Human-readable permission descriptions, Share/Translation extension labels, and the three existing English/Hebrew brand catalog entries use the same name. The MiniApps display name remains Hanlin MiniApps. No bundle identifier, App Group, URL scheme, keychain/iCloud identifier, provisioning profile name, product binary name, extension target, or storage path was renamed.

The paired runner additionally validates CFBundleDisplayName and CFBundleIdentifier from each actual built Info.plist and records its hash. Existing code-signature and actual App Group checks remain mandatory. Property-list parsing, catalog key preservation and unchanged non-brand translations were verified before commit. Binary acceptance is pending the new paired run; prior archives are still identified by their original SHA.
