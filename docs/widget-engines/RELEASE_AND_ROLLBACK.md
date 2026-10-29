# Release & Rollback Strategy — Dual Native Widget Engines

## 1. Single-Step Rollback Command

If any regression occurs in production or during deployment, the widget extension and scripting platform can be reverted cleanly to the prior known-good state with a single git command:

```bash
git checkout origin/integration/expo-nativescript-search-20261029 -- \
  HanlinScriptingWidgets/ \
  Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ \
  AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift
```

---

## 2. Technical Feature Decoupling (Non-Permission Flags)

To decouple or disable individual engines without rolling back code:
- **Disabling Expo Engine:**
  In `HanlinExtensionSnapshotView`:
  ```swift
  case .expo:
      HanlinExtensionNodeView(node: snapshot.root, identity: snapshot.actionIdentity ?? snapshot.identity)
  ```
  Immediately causes all Expo widgets to render their fallback `HanlinScriptUINode` without executing JavaScriptCore.
- **Disabling ScriptWidget Engine:**
  In `HanlinExtensionSnapshotView`:
  ```swift
  case .scriptwidget:
      HanlinExtensionNodeView(node: snapshot.root, identity: snapshot.actionIdentity ?? snapshot.identity)
  ```
  Instantly redirects ScriptWidget snapshots to the legacy node view.
- **Data Preservation:**
  The `HanlinScriptExtensionStore` Schema 2 design is strictly non-destructive. Rollback to Schema 1 does not alter or erase package data in `HanlinMiniAppDataStore` or App Group directories.

---

## 3. Pre-Release Constraints Asserts

- **Branch Isolation:** All changes reside strictly on `integration/hanlin-dual-widget-engines-20261029`.
- **No Main Merge:** `main` was NOT modified and NO pull request was merged into `main`.
- **No Distribution:** No build was submitted to TestFlight, App Store Connect, or public distribution.
- **No Unsolicited Asana Edits:** Asana was read for reference only; no tasks or projects were written to without explicit owner instruction.
- **Physical Device Gate:** Physical iPad testing on hardware is marked **`BLOCKED_DEVICE`**, requiring explicit owner device connection.
