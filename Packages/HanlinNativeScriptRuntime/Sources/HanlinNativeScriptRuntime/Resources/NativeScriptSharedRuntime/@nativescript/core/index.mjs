// eslint-disable-next-line @typescript-eslint/triple-slash-reference
/// <reference path="./global-types.d.ts" />
// Init globals first (use import to ensure it's always at the top)
import './globals';
export * from './application';
export { getNativeApp, setNativeApp } from './application/helpers-common';
export * from './native-window';
export * as ApplicationSettings from './application-settings';
import * as Accessibility from './accessibility';
export var AccessibilityEvents;
(function (AccessibilityEvents) {
    AccessibilityEvents.accessibilityBlurEvent = Accessibility.accessibilityBlurEvent;
    AccessibilityEvents.accessibilityFocusEvent = Accessibility.accessibilityFocusEvent;
    AccessibilityEvents.accessibilityFocusChangedEvent = Accessibility.accessibilityFocusChangedEvent;
    AccessibilityEvents.accessibilityPerformEscapeEvent = Accessibility.accessibilityPerformEscapeEvent;
})(AccessibilityEvents || (AccessibilityEvents = {}));
export { AccessibilityLiveRegion, AccessibilityRole, AccessibilityState, AccessibilityTrait, FontScaleCategory } from './accessibility';
export { Color } from './color';
export * as Connectivity from './connectivity';
export * from './core-types';
export { CSSUtils } from './css/system-classes';
export { ObservableArray, ChangeType } from './data/observable-array';
export { Observable, WrappedValue, fromObject, fromObjectRecursive } from './data/observable';
export { VirtualArray } from './data/virtual-array';
export { File, FileSystemEntity, Folder, knownFolders, path, getFileAccess, AndroidDirectory } from './file-system';
export { HttpResponseEncoding } from './http/http-interfaces';
export * as Http from './http';
export { ImageAsset } from './image-asset';
export { ImageSource } from './image-source';
export { ModuleNameResolver } from './module-name-resolver';
export { _setResolver } from './module-name-resolver/helpers';
export { isAndroid, isIOS, isVisionOS, isApple, Screen, Device, platformNames } from './platform';
export { profile, enable as profilingEnable, disable as profilingDisable, time as profilingTime, uptime as profilingUptime, start as profilingStart, stop as profilingStop, isRunning as profilingIsRunning, dumpProfiles as profilingDumpProfiles, resetProfiles as profilingResetProfiles, startCPUProfile as profilingStartCPU, stopCPUProfile as profilingStopCPU } from './profiling';
export { encoding } from './text';
export * from './trace';
export * as Utils from './utils';
export { XmlParser, ParserEventType, ParserEvent } from './xml';
export * from './ui';
//# sourceMappingURL=index.js.map