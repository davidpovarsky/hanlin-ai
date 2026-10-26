/**
 * @hanlin/expo-native-api (Contract Version 1.0.0)
 *
 * Hanlin Expo Native API TypeScript Facade.
 * Re-exports the authoritative upstream `@nativescript/react-native` API,
 * factories, and lifecycle helpers without replacing them with mock implementations.
 */

export const FACADE_VERSION = "1.0.0";
export const CONTRACT_VERSION = "1.0.0";
export const UPSTREAM_VERSION = "9.1.2";
export const WORKLETS_VERSION = "0.13.1";

export {
  // Core JSI lifecycle
  init,
  install,
  isAvailable,
  isInstalled,
  defaultMetadataPath,
  getRuntimeBackend,
  installGlobals,

  // Worklets integration
  runOnUI,
  installWorklets,
  uiInvoker,
  jsInvoker,
  runtimeInvoker,

  // Native UIKit factories
  defineUIKitView,
  defineUIKitContainer,
  defineUIViewController,
  createDelegate,

  // Retain / Release utilities
  createRetainer,
  retain,
  release,

  // Runtime introspection
  getClass,
  getProtocol,
  isClassAvailable,
  isFrameworkLoaded,
  loadFramework,
  isMainThread,
  assertUIKitThread,
  warnIfNotUIKitThread,
  refreshUIKitHostView,
  refreshUIKitHostViewHandle,
  loadImage,
  nativeViewHandle,
  eventBridge,
  createEventBridge
} from "@nativescript/react-native";

export type {
  InstallOptions,
  NativeScriptWorklets,
  UIKitSizingMode,
  UIKitLayoutOptions,
  UIKitHostReadyEvent,
  UIKitViewContext,
  NativeScriptImageLoadOptions,
  NativeScriptImageLoadCallback,
  UIKitDisposeResult,
  UIKitViewDefinition,
  UIKitViewRef,
  UIKitHostViewProps,
  UIKitViewComponent,
  UIKitContainerResult,
  UIKitContainerDefinition,
  UIViewControllerDefinition,
  NativeScriptCallbackThread,
  NativeScriptInvokedCallback,
  NativeRetainer,
  NativeDelegateOwner,
  CreateDelegateOptions,
  NativeProtocolReference
} from "@nativescript/react-native";
