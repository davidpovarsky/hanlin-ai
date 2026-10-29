# Architecture & Payload Contract — Dual Native Widget Engines

## 1. Schema V2 Architecture & Data Flow

```mermaid
flowchart TD
    subgraph Host Application / MiniApp Runtime
        JS[External MiniApp / Script] -->|widgets.publish or Package Install| HSP[HanlinScriptingPlatform]
        HSP -->|Generate Snapshot V2| Store[HanlinScriptExtensionStore]
        Store -->|Persist JSON Envelope| AppGroup[App Group: group.com.itorah.chavrusachat]
    end

    subgraph WidgetKit Extension (HanlinScriptingWidgets.appex)
        AppGroup -->|load()| Provider[HanlinWidgetTimelineProvider]
        Provider -->|snapshot.engine| Router{HanlinExtensionSnapshotView}

        Router -->|.legacy| VLegacy[HanlinExtensionNodeView]
        Router -->|.expo| VExpo[HanlinExpoWidgetsDynamicView]
        Router -->|.scriptwidget| VScript[HanlinScriptWidgetDynamicView]

        VExpo -->|JSC + ExpoWidgets.bundle| RendererExpo[HanlinExpoWidgetsViewRenderer]
        VScript -->|JSC + support.bundle| RendererScript[HanlinScriptWidgetElementView]

        RendererExpo -.->|Mixed Tree: ScriptWidgetSubtree| RendererScript
    end

    subgraph User Interactions
        RendererExpo -->|AppIntent Button| ActionIntent[HanlinGenericWidgetActionIntent]
        RendererScript -->|AppIntent Button / Toggle| ActionIntent
        ActionIntent -->|Enqueue Command & Reload| Store
    end
```

---

## 2. Wire Contract Specification

### `HanlinWidgetEngine`
```swift
public enum HanlinWidgetEngine: String, Codable, CaseIterable, Hashable, Sendable {
    case legacy
    case expo
    case scriptwidget
}
```

### `HanlinWidgetPayload`
A tagged union discriminating the engine-specific runtime representation:
```swift
public enum HanlinWidgetPayload: Codable, Hashable, Sendable {
    case legacy(HanlinScriptUINode)
    case expo(ExpoWidgetDescriptor)
    case scriptwidget(ScriptWidgetDescriptor)
}
```

- **`ExpoWidgetDescriptor`**:
  - `layout: String` — JavaScript function source `function(props, env) { return { type, props }; }` or serialized layout.
  - `props: [String: HanlinValue]?` — Initial input props passed into the layout function.
  - `sourceName: String?` — Widget source identifier.
- **`ScriptWidgetDescriptor`**:
  - `script: String` — Complete JSX/JS source `function main() { return <vstack>...</vstack>; }`.
  - `environment: [String: HanlinValue]?` — Runtime environment passed into JavaScriptCore.

---

## 3. Backwards & Forwards Compatibility

1. **Decoding Schema 1 Snapshots:**
   - If `schemaVersion` is missing or `1`, `engine` defaults to `.legacy`.
   - If `payload` is missing, `payload` defaults to `.legacy(root)`.
   - Any client reading `root` continues to receive the legacy fallback `HanlinScriptUINode`.
2. **Encoding Schema 2 Snapshots:**
   - Both `engine` and `payload` are encoded into the snapshot JSON.
   - For `.expo` and `.scriptwidget`, `root` contains an informational text node (`displayName`), preserving safety if an older reader inspects `root`.
3. **Storage Security & Integrity:**
   - Stored in `group.com.itorah.chavrusachat/ScriptingExtensions/`.
   - Protected with `.completeFileProtectionUntilFirstUserAuthentication`.
   - SHA-256 integrity digest verified on every read.
