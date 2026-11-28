// eslint-disable-next-line @typescript-eslint/triple-slash-reference
/// <reference path="./global-types.d.ts" />
// Init globals first (use import to ensure it's always at the top)
import '../core/globals';
export * from '../core/application';
export { getNativeApp, setNativeApp } from '../core/application/helpers-common';
export * from '../core/native-window';
export * as ApplicationSettings from '../core/application-settings';
import * as Accessibility from '../core/accessibility';
export var AccessibilityEvents;
(function (AccessibilityEvents) {
    AccessibilityEvents.accessibilityBlurEvent = Accessibility.accessibilityBlurEvent;
    AccessibilityEvents.accessibilityFocusEvent = Accessibility.accessibilityFocusEvent;
    AccessibilityEvents.accessibilityFocusChangedEvent = Accessibility.accessibilityFocusChangedEvent;
    AccessibilityEvents.accessibilityPerformEscapeEvent = Accessibility.accessibilityPerformEscapeEvent;
})(AccessibilityEvents || (AccessibilityEvents = {}));
export { AccessibilityLiveRegion, AccessibilityRole, AccessibilityState, AccessibilityTrait, FontScaleCategory } from '../core/accessibility';
export { Color } from '../core/color';
export * as Connectivity from '../core/connectivity';
export * from '../core/core-types';
export { CSSUtils } from '../core/css/system-classes';
export { ObservableArray, ChangeType } from '../core/data/observable-array';
export { Observable, WrappedValue, fromObject, fromObjectRecursive } from '../core/data/observable';
export { VirtualArray } from '../core/data/virtual-array';
export { File, FileSystemEntity, Folder, knownFolders, path, getFileAccess, AndroidDirectory } from '../core/file-system';
export { HttpResponseEncoding } from '../core/http/http-interfaces';
export * as Http from '../core/http';
export { ImageAsset } from '../core/image-asset';
export { ImageSource } from '../core/image-source';
export { ModuleNameResolver } from '../core/module-name-resolver';
export { _setResolver } from '../core/module-name-resolver/helpers';
export { isAndroid, isIOS, isVisionOS, isApple, Screen, Device, platformNames } from '../core/platform';
export { profile, enable as profilingEnable, disable as profilingDisable, time as profilingTime, uptime as profilingUptime, start as profilingStart, stop as profilingStop, isRunning as profilingIsRunning, dumpProfiles as profilingDumpProfiles, resetProfiles as profilingResetProfiles, startCPUProfile as profilingStartCPU, stopCPUProfile as profilingStopCPU } from '../core/profiling';
export { encoding } from '../core/text';
export * from '../core/trace';
export * as Utils from '../core/utils';
export { XmlParser, ParserEventType, ParserEvent } from '../core/xml';
export * from '../core/ui';
//# sourceMappingURL=index.js.map