/**
 * Do not import other files here to avoid circular dependencies.
 * Used to define helper functions and variables that are shared between Android and iOS.
 * This file can declare cross platform types and use bundler platform checks.
 * For example, use `__ANDROID__` or `__APPLE__` to check the platform.
 */
let nativeApp;
function isEmbedded() {
    if (__APPLE__) {
        return !!NativeScriptEmbedder.sharedInstance().delegate;
    }
    else {
        // @ts-ignore
        // Check if the Bootstrap class exists and has the isEmbeddedNativeScript property
        // This is a way to determine if the app is embedded in a host project.
        return org.nativescript?.Bootstrap?.isEmbeddedNativeScript;
    }
}
/**
 * Get the current application instance.
 * @returns current application instance, UIApplication on iOS or android.app.Application on Android.
 */
export function getNativeApp() {
    if (__ANDROID__) {
        if (!nativeApp) {
            // Try getting it from module - check whether application.android.init has been explicitly called
            // check whether the com.tns.NativeScriptApplication type exists
            if (com.tns.NativeScriptApplication) {
                nativeApp = com.tns.NativeScriptApplication.getInstance();
            }
            if (!nativeApp && isEmbedded()) {
                nativeApp = com.tns.embedding.ApplicationHolder.getInstance();
            }
            // the getInstance might return null if com.tns.NativeScriptApplication exists but is not the starting app type
            if (!nativeApp) {
                // TODO: Should we handle the case when a custom application type is provided and the user has not explicitly initialized the application module?
                const clazz = java.lang.Class.forName('android.app.ActivityThread');
                if (clazz) {
                    const method = clazz.getMethod('currentApplication', null);
                    if (method) {
                        nativeApp = method.invoke(null, null);
                    }
                }
            }
        }
    }
    return nativeApp;
}
/**
 * This is called internally to set the native application instance.
 * You typically do not need to call this directly.
 * However, it's exposed for special case purposes, such as custom application initialization.
 * @param app The native application instance to set.
 * This should be called once during application startup to set the native app instance.
 */
export function setNativeApp(app) {
    nativeApp = app;
}
let rootView;
export function getRootView() {
    return rootView;
}
export function setRootView(view) {
    rootView = view;
}
let _appInBackground = false;
export function isAppInBackground() {
    return _appInBackground;
}
export function setAppInBackground(value) {
    _appInBackground = value;
}
/**
 * Backs `Application.autoSystemAppearanceChanged`. Lives here so windows can read it
 * without importing the application module.
 */
let _autoSystemAppearanceChanged = true;
export function getAutoSystemAppearanceChanged() {
    return _autoSystemAppearanceChanged;
}
export function setAutoSystemAppearanceChanged(value) {
    _autoSystemAppearanceChanged = value;
}
/**
 * Backs `Application.activeWindow`. Lives here so window-scoped lookups - the frame stack
 * above all - can read it without importing the application module.
 */
let _activeWindow;
export function getActiveWindow() {
    return _activeWindow;
}
export function setActiveWindow(window) {
    _activeWindow = window;
}
let _iosWindow;
export function getiOSWindow() {
    return _iosWindow;
}
export function setiOSWindow(value) {
    _iosWindow = value;
}
let _appMainEntry; /* NavigationEntry */
export function getAppMainEntry() {
    return _appMainEntry;
}
export function setAppMainEntry(entry /* NavigationEntry */) {
    _appMainEntry = entry;
}
// Aids avoiding circular dependencies by allowing the application event listeners to be toggled
let _toggleApplicationEventListenersHandler;
export function toggleApplicationEventListeners(toAdd, callback) {
    if (_toggleApplicationEventListenersHandler) {
        _toggleApplicationEventListenersHandler(toAdd, callback);
    }
}
export function setToggleApplicationEventListenersCallback(callback) {
    _toggleApplicationEventListenersHandler = callback;
}
let _applicationPropertiesCallback;
export function getApplicationProperties() {
    if (_applicationPropertiesCallback) {
        return _applicationPropertiesCallback();
    }
    return { orientation: 'unknown', systemAppearance: null };
}
export function setApplicationPropertiesCallback(callback) {
    _applicationPropertiesCallback = callback;
}
let _a11yUpdatePropertiesCallback;
export function setA11yUpdatePropertiesCallback(callback) {
    _a11yUpdatePropertiesCallback = callback;
}
export function updateA11yPropertiesCallback(view /* View */) {
    if (_a11yUpdatePropertiesCallback) {
        _a11yUpdatePropertiesCallback(view);
    }
}
/**
 * Internal Android app helpers
 */
let _imageFetcher;
export function getImageFetcher() {
    return _imageFetcher;
}
export function setImageFetcher(fetcher) {
    _imageFetcher = fetcher;
}
export var CacheMode;
(function (CacheMode) {
    CacheMode[CacheMode["none"] = 0] = "none";
    CacheMode[CacheMode["memory"] = 1] = "memory";
    CacheMode[CacheMode["diskAndMemory"] = 2] = "diskAndMemory";
})(CacheMode || (CacheMode = {}));
let _currentCacheMode;
export function initImageCache(context, mode = CacheMode.diskAndMemory, memoryCacheSize = 0.25, diskCacheSize = 10 * 1024 * 1024) {
    if (_currentCacheMode === mode) {
        return;
    }
    _currentCacheMode = mode;
    if (!getImageFetcher()) {
        setImageFetcher(org.nativescript.widgets.image.Fetcher.getInstance(context));
    }
    else {
        getImageFetcher().clearCache();
    }
    const params = new org.nativescript.widgets.image.Cache.CacheParams();
    params.memoryCacheEnabled = mode !== CacheMode.none;
    params.setMemCacheSizePercent(memoryCacheSize); // Set memory cache to % of app memory
    params.diskCacheEnabled = mode === CacheMode.diskAndMemory;
    params.diskCacheSize = diskCacheSize;
    const imageCache = org.nativescript.widgets.image.Cache.getInstance(params);
    getImageFetcher().addImageCache(imageCache);
    getImageFetcher().initCache();
}
//# sourceMappingURL=helpers-common.js.map