# HanlinExpoNativeAPI

## Architectural Role and Isolation

`HanlinExpoNativeAPI` bridges the published `@nativescript/react-native@9.1.2` JSI TurboModule and Fabric components into Hanlin's React Native / Hermes Expo MiniApp runtime.

### Strict Isolation from NativeScript Standalone V8 (`HanlinNativeScriptRuntime`)
1. **Engine Separation:**
   - `HanlinNativeScriptRuntime` runs the standalone NativeScript iOS runtime powered by the V8 JavaScript engine (`NativeScript/ios-spm@9.1.0`).
   - `HanlinExpoNativeAPI` compiles against the React Native Hermes JSI runtime (`hermesvm.xcframework`) and React Native New Architecture (`React.xcframework`, `0.88.0`).
   - The two runtimes never share JS objects, memory heaps, or runloops.

2. **Native Authorization Gate:**
   - Direct JSI access is guarded at the native boundary by `HanlinExpoNativeAPIGate`.
   - Packages must declare and be granted the `ios-native-api` capability.
   - Unauthorized packages attempting to call `TurboModuleRegistry.get('NativeScriptNativeApi')` or invoke `.install()` are rejected by the native gate.

3. **Threading and Worklets:**
   - UI views (`NativeScriptUIView`) and Objective-C calls execute on the dedicated Worklets UI runtime / main thread via `react-native-worklets@0.13.1`.
   - The React render JS thread never directly touches UIKit controls without scheduling.
