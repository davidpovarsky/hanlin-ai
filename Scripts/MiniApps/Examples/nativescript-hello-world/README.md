# NativeScript Hello World

A complete source project using original NativeScript Core Application, Page, Label and Button APIs. It also reads the real iOS `UIDevice` metadata bridge. The native button event updates a tap count; `Application.run` supplies the root page.

Use the installed SDK's authoring workflow to validate and build the whole directory. `hanlin.authoring.json` identifies `index.ts`; `tsconfig.json` selects the source. Compiler policy and Core/iOS declarations come from that SDK. Copy the project into a writable workspace before editing or building; do not install another compiler or rewrite the SDK.

Expected native behavior: the screen shows “Hello from NativeScript!”, the device's iOS system name/version and “Button taps: 0”; pressing “Say hello” increments the count. A successful source build alone does not establish installation, rendering or native event execution.
