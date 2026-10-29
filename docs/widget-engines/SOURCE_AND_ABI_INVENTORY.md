# Source and ABI Inventory — Dual Native Widget Engines

## 1. Upstream Revisions Pinned

| Component | Pinned Version / Commit SHA | Origin Repository | Role in Hanlin |
| :--- | :--- | :--- | :--- |
| **Expo Widgets** | `58.0.3` (gitHead `917a61b581baeb852aa4fe331da2c1395d824351`) | `expo/expo` (`packages/expo-widgets`) | Layout evaluation via JavaScriptCore & native SwiftUI views |
| **@expo/ui** | `58.0.3` | `expo/expo` (`packages/expo-ui`) | Pinned UI component framework |
| **ScriptWidget** | `68f04194f00222558c44d5a832e7617a96f62574` | `everettjf/scriptwidget` (`main`) | Complete JSX runtime + 29-tag native SwiftUI renderer |
| **React** | `19.3.0` | npm | Host runtime & JSX stub |
| **React Native** | `0.88.0` | npm | Pinned host environment |
| **Babel Core** | Standalone inside `support.bundle/core.js` | `everettjf/scriptwidget` | On-device JSX-to-JS transpilation |

---

## 2. Vendored Source Structure & Modifications

### A. Expo Widgets Engine (`Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ExpoWidgets/`)
- `HanlinExpoWidgetsRuntime.swift`:
  - Evaluates `ExpoWidgets.bundle` in JavaScriptCore.
  - Adapted bundle lookup checking App Extension bundle, SPM module bundle, and App Group container (`group.com.itorah.chavrusachat`).
  - Thread-safe recursive locking for concurrent widget timeline evaluations.
- `HanlinExpoWidgetsViewRenderer.swift`:
  - Native SwiftUI renderer for `TextView`, `HStackView`, `VStackView`, `ZStackView`, `RectangleView`, `RoundedRectangleView`, `CapsuleView`, `CircleView`, `EllipseView`, `SpacerView`, `DividerView`, `ImageView`, `ProgressView`, `GaugeView`, `ChartView`, `Button`, `LinkView`, `AccessoryWidgetBackgroundView`.
  - Added `ScriptWidgetSubtree` node handling to enable embedding ScriptWidget JSX trees as child views inside Expo layouts.
- `HanlinExpoWidgetsDynamicView.swift`:
  - SwiftUI root container evaluating layout scripts and rendering fallback diagnostics if errors occur.

### B. ScriptWidget Engine (`Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/`)
- `HanlinScriptWidgetRuntime.swift`:
  - Evaluates JSX / JS using `support.bundle` (`core.js`, `moment.min.js`).
  - Converts evaluated tree directly into `HanlinScriptWidgetElement`.
  - Replaced hardcoded `group.everettjf.scriptwidget` and standalone `ScriptManager` database with Hanlin's `group.com.itorah.chavrusachat` App Group store.
- `HanlinScriptWidgetElement.swift`:
  - Lightweight, Sendable element model with typed attribute accessors.
- `HanlinScriptWidgetAttributes.swift`:
  - Parsing for hex/named colors, fonts, alignments, frames, padding, opacity, and corner radii.
- `HanlinScriptWidgetElements.swift`:
  - Specialized native renderers for `chart`, `gauge`, `ring`, `badge`, `chip`, `stat`, `date`, `button`, `toggle`, `icon`, `shapes`, and `grids`.
- `HanlinScriptWidgetElementView.swift`:
  - Master native component renderer covering all 29 upstream ScriptWidget tags.

### C. Host & Storage Integration
- `HanlinScriptExtensionContracts.swift`:
  - Added `HanlinWidgetEngine` (`legacy`, `expo`, `scriptwidget`).
  - Added `ExpoWidgetDescriptor`, `ScriptWidgetDescriptor`, and `HanlinWidgetPayload`.
  - Upgraded `HanlinScriptExtensionSnapshot` to support Schema V2 with full V1 decoding compatibility.
- `HanlinScriptExtensionStore.swift`:
  - Transparent support for loading and saving Schema 1 and Schema 2 envelopes.
- `HanlinGenericWidgetActionIntent.swift`:
  - Interactive WidgetKit AppIntent (`HanlinGenericWidgetActionIntent`) and Expo compatibility intent (`WidgetUserInteraction`).
- `HanlinScriptingWidgets/HanlinScriptingWidgets.swift`:
  - Dynamic routing in `HanlinExtensionSnapshotView` across `.legacy`, `.expo`, and `.scriptwidget`.
