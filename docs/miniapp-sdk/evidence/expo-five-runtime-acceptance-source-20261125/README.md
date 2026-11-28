# Expo original five-runtime acceptance source

This change extends the existing paired acceptance case `testStandaloneExpoHostServicesUseRealStorageRuntimeAndWidgetPublication`; it does not replace its storage, JavaScriptCore, widget, or activity checks or change the original selected test counts.

The original exported `hostServices.executeRuntime` API is called for Node, TypeScript, local Python, JavaScriptCore, and Shell. Each actual response must include a distinct execution UUID, a successful non-truncated non-cancelled non-timeout result, and stdout matching a fresh per-run challenge. The complete responses are read from the native accessibility text and attached as JSON. The shell invocation uses the existing Host source-command shell backend; it does not establish direct ios_system argv execution.

The original Expo fixture TypeScript compiler and tsconfig were run once on Oracle: exit 0, empty diagnostics, strict=true, skipLibCheck=false, compiler 6.0.3. The raw command receipt and empty log are preserved here. An author-owned temporary node_modules symlink to the existing prepared dependencies was removed after the check. No native build, runtime execution, native accessibility readback, or new acceptance pass is claimed by this packet.

A separate read-only peer review traced the exported types through the original Expo native invoke, shared runtime wire decoder, broker, and existing implementations. Original native Text receives the complete string; lineLimit only affects layout. Full JSON accessibility and runtime outcomes still require the native acceptance run.
