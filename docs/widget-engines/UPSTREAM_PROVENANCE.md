# Upstream Provenance — Dual Native Widget Engines

## 1. Upstream Commit Pins & Provenance

### A. ScriptWidget
- **Source Repository:** `https://github.com/everettjf/scriptwidget`
- **Pinned Commit:** `68f04194f00222558c44d5a832e7617a96f62574`
- **Original Author:** everettjf
- **License:** MIT License
- **Attribution Notice:**
  > Portions of the ScriptWidget component rendering engine and JavaScriptCore runtime evaluation are derived from Everett's ScriptWidget project (`everettjf/scriptwidget`), licensed under the MIT License. Copyright (c) 2020 everettjf.
- **Hanlin Adaptations:**
  - Removed dependency on hardcoded `group.everettjf.scriptwidget` App Group and standalone `ScriptManager` database.
  - Replaced with Hanlin's `group.com.itorah.chavrusachat` App Group store.
  - Adapted `ScriptWidgetElementView` and its 15 element builders to Hanlin's Swift 6 / iOS 27 deployment target.
  - Embedded `support.bundle` (`core.js`, `moment.min.js`, `util.js`) into Hanlin platform and extension resources.

### B. Expo Widgets
- **Source Repository:** `https://github.com/expo/expo`
- **Sub-package:** `packages/expo-widgets` (version `58.0.3`)
- **Git Head:** `917a61b581baeb852aa4fe331da2c1395d824351`
- **Original Author:** 650 Industries, Inc. (Expo)
- **License:** MIT License
- **Attribution Notice:**
  > Portions of the Expo Widgets layout evaluation and dynamic view renderer are derived from Expo (`expo/expo`), licensed under the MIT License. Copyright (c) 650 Industries, Inc.
- **Hanlin Adaptations:**
  - Bundled `ExpoWidgets.bundle` using an esbuild pipeline resolving React, React Native, and Expo stubs cleanly.
  - Adapted `WidgetsJSRuntime` to look for bundle files in `HanlinScriptingWidgets.appex`, `HanlinScriptExtensions` SPM module, and App Group storage.
  - Rewrote button action routing to dispatch `HanlinGenericWidgetActionIntent` and reload `"HanlinScriptingWidget"`.
  - Added mixed-tree adapter case (`ScriptWidgetSubtree`) in `HanlinExpoWidgetsViewRenderer`.
