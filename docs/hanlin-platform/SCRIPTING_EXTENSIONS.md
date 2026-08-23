# Generic Scripting extensions

Hanlin ships one precompiled `HanlinScriptingWidgets` extension. Installed
packages do not generate Swift types or executable extension bundles. The same
extension hosts three bounded surfaces:

- an App-Intent-configured Widget whose dynamic entity selects an installed
  package snapshot;
- generic App Intents whose dynamic entities are read from the shared snapshot;
- one generic ActivityKit attributes type for package-owned Live Activities.

The main app publishes versioned, integrity-checked snapshots through
`HanlinScriptExtensionStore` in the App Group
`group.cherryai.com.AI-Hanlin`. Extension processes consume only canonical
data and the extension-safe ScriptUI subset. They do not link or invoke Node,
Python, a shell, the compiler, package source, API keys, or arbitrary services.

Widget snapshots are capped at 4 MiB. Unsupported interactive or navigation
nodes render an explicit foreground continuation rather than executing package
code in WidgetKit. Generic intents enqueue a bounded, uniquely named resume
command, open the main app, and leave acknowledgement to the owning runtime so
`Script.onResume(...)` cannot be lost before delivery.

Live Activities use one static `ActivityAttributes` type. A package supplies
only canonical state and renderable content; start, update, and end remain
host operations. This follows Apple's documented model that App Intents may
live in an extension or Swift package and that WidgetKit configuration uses
`WidgetConfigurationIntent` plus dynamic `AppEntity` queries.

Xcode/SDK verification is required for the new target, provisioning profile,
App Group, WidgetKit registration, App Intent discovery, and ActivityKit
lifecycle. No remote build is started in normal editing mode.
