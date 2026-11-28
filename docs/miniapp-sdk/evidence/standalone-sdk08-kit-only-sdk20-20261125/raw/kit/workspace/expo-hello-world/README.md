# Expo Hello World

A complete source project using the original Expo SwiftUI Host, text, stack and button. React state updates the tap count. The entry registers `main`, the root name requested by the Hanlin Expo host.

Use the installed SDK's authoring workflow to validate and build the whole directory. `hanlin.authoring.json` identifies `index.ts`; `tsconfig.json` selects both source files. Compiler policy and original dependencies come from that SDK. Copy the project into a writable workspace before editing or building; do not install another compiler or rewrite the SDK.

Expected native behavior: the initial screen says “Hello from Expo!” and “Button taps: 0”; pressing “Say hello” increments the count. A successful source build alone does not establish installation, rendering or native event execution.
