# Studio cloud-root lifecycle correction

The iCloud container lookup and local workspace creation previously ran synchronously in the SwiftUI library task. Apple's public FileManager documentation requires the ubiquity lookup to run off the main thread. Returning to an already opened library could also start another root lookup while editor/navigation state existed.

This change executes the blocking root lookup and workspace creation in a detached task, propagates cancellation, qualifies completion by the active request identity, and retains an already opened workspace. A stale success, error or cancellation cannot replace the current workspace. The existing editor, draft persistence, compare-before-save, coordination, import and move implementations remain byte-identical.

The current source declares the existing iCloud container and CloudDocuments/CloudKit services, as well as Files sharing and opening in place. Actual signed entitlement and container availability are still an Apple gate. A nil container displays the existing unavailable-state route with a message that does not assume the user alone caused the problem. No placeholder API, tagNamesKey call, new engine, entitlement or new system extension is introduced.

## Validation

The original Foundation source and test files were copied byte-for-byte into the documented portable package. All four existing workspace methods and four new root-lifecycle methods passed under Swift 6.4.3 on Oracle. The initial Swift Testing macro compile failure is retained; the same mutating begin() calls now occur before their unchanged assertions. The source and all three Swift files also passed syntax parsing. This is not UIKit typechecking, iCloud/FileProvider execution, a device test or native app acceptance.

The four additive native selectors are recorded in source-and-test-receipt.json. Retain the existing workspace4 and StudioProject6 invocations; the relevant Studio native inventory becomes14. A root-only async lifecycle fix does not itself certify cloud placeholders or remote sync conflicts.

Sources: [Apple FileManager contract](https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)); [Apple iCloud services](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-services). The exact installed SDK header identities and source configuration are recorded in configuration-and-api-boundary.json.
