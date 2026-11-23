# ScriptWidget authoring in Hanlin

ScriptWidget is an active widget engine. The frozen Scripting application/ScriptUI engine is a different implementation.

The SDK keeps the original ScriptWidget editor completion catalog, its Apache-2.0 license, notice, source revision and individual SHA-256 values. JSX component declarations are generated from that catalog. They cover native lowercase tags such as text, vstack, button and toggle; custom function components return JSX.Element.

ScriptWidget does not publish complete TypeScript declarations for all authoring globals. Hanlin's separate host-globals.d.ts describes the actual exports of HanlinScriptWidgetRuntime.swift: package storage, prepared package files, imports, widget environment, rendering and HTTP. The original catalog also documents services from the upstream app that are not installed in Hanlin; those are retained as reference data and are not falsely declared as callable globals.

Use the SDK's scriptwidget/tsconfig.json. It references original-catalog component types and actual host globals, without DOM fetch types. The widget HTTP API returns response text. It does not return a browser Response object.

The .scripting extension remains an accepted archive container for existing ScriptWidget widgets. That does not reactivate the legacy Scripting-JSC MiniApp engine.

The main application produces prepared widget code and resources. WidgetKit loads the installed widget renderer and prepared package. Native dependency changes require rebuilding the host application and its extension.
