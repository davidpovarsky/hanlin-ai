# Otzaria host package compatibility — 2026-11-18

The Otzaria single developer's current owner instruction explicitly authorizes
necessary fixes and normal pushes across the existing repositories. This narrow
consumer fix is isolated on **codex/otzaria-host-sdk-compat-20261118**, from original
Hanlin **8c10ebd066826511e4d20d0c763491764eb44a95**. The canonical Hanlin continuation
worktree, its branch and all existing local work are preserved.

## Concrete dependency conflict

Maktabah's actual Xcode project requires ZIPFoundation **exactly 0.9.20**, and
its accepted application lock selects revision
22787ffb59de99e5dc1fbfe80b19c97a904ad48d. HanlinPlatform's manifest previously
required **exactly 0.9.19**. Those requirements cannot coexist in the same
SwiftPM graph, even when the consumer links only HanlinHostContracts.

The library now allows **0.9.19..<0.10.0** using SwiftPM's upToNextMinor requirement.
The existing standalone SDK locks remain pinned to their original 0.9.19
revision. Otzaria retains its existing exact 0.9.20 requirement and lock.
Neither host needs a dependency downgrade or a duplicate ZIPFoundation module.
Every unrelated dependency and package source remains unchanged.

## Evidence boundary

The installed Swift 6.3.3 manifest interpreter executed swift package
--package-path Packages/HanlinPlatform dump-package before and after.
Its JSON output differs only in this requirement: exact:0.9.19 becomes
range:0.9.19..<0.10.0. This proves manifest interpretation, not Apple package
resolution, compilation, ZIP behavior or native acceptance. The real integrated
Maktabah Xcode build must resolve the original complete sibling packages, verify
every committed dependency pin and compile the registered HostIntegration.
Existing native results retain their original source identities.

The SDK is consumed as its original monorepo Git submodule with the literal
Packages/HanlinAgentSDK and Packages/HanlinPlatform sibling layout.
No SDK source modules, agent loop, chat view, composer, store or permissions
implementation are copied into the host.
