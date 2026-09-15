import { CSSUtils } from '../css/system-classes';
import { Device } from '../platform';
import { Trace } from '../trace';
import { Builder } from '../ui/builder';
import { applyAccessibilityCssToRoot, readyInitAccessibilityCssHelper, readyInitFontScale } from '../accessibility/accessibility-common';
import { SDK_VERSION } from '../utils/constants';
import { NativeWindowEvents } from './native-window-interfaces';
import { getAutoSystemAppearanceChanged } from '../application/helpers-common';
import { WindowBase } from './window-base';
const ORIENTATION_CSS_CLASSES = CSSUtils.ORIENTATION_CSS_CLASSES;
const SYSTEM_APPEARANCE_CSS_CLASSES = CSSUtils.SYSTEM_APPEARANCE_CSS_CLASSES;
const LAYOUT_DIRECTION_CSS_CLASSES = CSSUtils.LAYOUT_DIRECTION_CSS_CLASSES;
/**
 * Cross-platform NativeWindow base class.
 *
 * Wraps a platform window surface (iOS UIWindowScene+UIWindow, Android Activity)
 * and manages per-window root view lifecycle, CSS classes, and events.
 *
 * Platform-specific subclasses implement the abstract methods.
 */
export class NativeWindow extends WindowBase {
    constructor(id, isPrimary = false, role = 'application') {
        super(id, isPrimary, role);
    }
    get rootView() {
        return this._rootView;
    }
    /**
     * Set the content of this window.
     * Accepts a View, a NavigationEntry, or a module name string.
     */
    setContent(content) {
        let view;
        if (typeof content === 'string') {
            view = Builder.createViewFromEntry({ moduleName: content });
        }
        else if (content && typeof content === 'object') {
            if (content.moduleName || content.create) {
                view = Builder.createViewFromEntry(content);
            }
            else {
                view = content;
            }
        }
        if (!view) {
            throw new Error('NativeWindow.setContent: Invalid content provided.');
        }
        const previousRootView = this._rootView;
        if (previousRootView) {
            previousRootView._onRootViewReset();
        }
        this._takeRootView(view);
        this._applyRootViewSettings(view);
        this._setNativeContent(view);
        this._notifyEvent(NativeWindowEvents.contentLoaded);
    }
    /**
     * @internal – take ownership of a root view the platform pipeline built and attached itself.
     *
     * The pipeline already ran `_setupAsRootView` and `Application.initRootView` on this view and
     * installed it on the native surface, so neither `_applyRootViewSettings` nor `_setNativeContent`
     * may run here — both would redo that work.
     */
    _adoptRootView(view) {
        if (!view || this._rootView === view) {
            return;
        }
        this._takeRootView(view);
        this._notifyEvent(NativeWindowEvents.contentLoaded);
    }
    /**
     * @internal – give up the root view without tearing it down.
     *
     * Called when another window takes the view over: the view is being moved, not
     * destroyed, so — unlike {@link _onDestroy} — nothing here unloads, resets or tears
     * down the view. It stays loaded and usable in its new window.
     */
    _releaseRootView() {
        const rootView = this._rootView;
        if (!rootView) {
            return;
        }
        this._onReleaseRootView(rootView);
        rootView._nativeWindow = null;
        this._rootView = null;
    }
    /**
     * Platform hook: unhook the released view from the native surface. The view itself
     * must survive — it is on its way into another window.
     */
    _onReleaseRootView(rootView) {
        // noop
    }
    /**
     * Becomes the owner of `view`, releasing it from whichever window held it before.
     */
    _takeRootView(view) {
        const currentOwner = view._nativeWindow;
        if (currentOwner && currentOwner !== this) {
            currentOwner._releaseRootView();
        }
        if (this._rootView && this._rootView !== view) {
            this._rootView._nativeWindow = null;
        }
        this._rootView = view;
        view._nativeWindow = this;
    }
    /**
     * Get the current orientation of this window.
     *
     * Read from the native surface while the window is attached; a detached window
     * reports the last value it saw.
     *
     * A read that catches a change the platform has not reported yet goes through
     * {@link _setOrientation}, so the change is never swallowed by the reading.
     */
    orientation() {
        if (this.state === 'attached') {
            const value = this._getOrientation();
            if (this._orientation === undefined) {
                this._orientation = value;
            }
            else if (this._orientation !== value) {
                this._setOrientation(value);
            }
        }
        return this._orientation;
    }
    /**
     * Get the current system appearance of this window.
     *
     * Read from the native surface while the window is attached; a detached window
     * reports the last value it saw.
     *
     * A read that catches a change the platform has not reported yet goes through
     * {@link _setSystemAppearance}, so the change is never swallowed by the reading.
     */
    systemAppearance() {
        if (this.state === 'attached') {
            const value = this._getSystemAppearance();
            if (this._systemAppearance === undefined) {
                this._systemAppearance = value;
            }
            else if (this._systemAppearance !== value && value !== null) {
                this._setSystemAppearance(value);
            }
        }
        return this._systemAppearance;
    }
    /**
     * Get the current layout direction of this window.
     *
     * Read from the native surface while the window is attached; a detached window
     * reports the last value it saw.
     *
     * A read that catches a change the platform has not reported yet goes through
     * {@link _setLayoutDirection}, so the change is never swallowed by the reading.
     */
    layoutDirection() {
        if (this.state === 'attached') {
            const value = this._getLayoutDirection();
            if (this._layoutDirection === undefined) {
                this._layoutDirection = value;
            }
            else if (this._layoutDirection !== value && value !== null) {
                this._setLayoutDirection(value);
            }
        }
        return this._layoutDirection;
    }
    on(eventName, callback, thisArg) {
        super.on(eventName, callback, thisArg);
    }
    // --- Root view CSS class management ---
    /**
     * Applies platform, orientation, appearance, and layout direction CSS classes
     * to the root view.
     */
    _applyRootViewSettings(rootView) {
        rootView._setupAsRootView({});
        this._setRootViewCSSClasses(rootView);
        readyInitAccessibilityCssHelper();
        readyInitFontScale();
        applyAccessibilityCssToRoot(rootView);
    }
    _setRootViewCSSClasses(rootView) {
        const platform = Device.os.toLowerCase();
        const deviceType = Device.deviceType.toLowerCase();
        if (platform) {
            CSSUtils.pushToSystemCssClasses(`${CSSUtils.CLASS_PREFIX}${platform}`);
            // SDK Version CSS classes
            // Add exact version class (e.g., .ns-ios-26 or .ns-android-36)
            // this acts like 'gte' for that major version range
            // e.g., if user wants iOS 27, they can add .ns-ios-27 specifiers
            CSSUtils.pushToSystemCssClasses(`${CSSUtils.CLASS_PREFIX}${platform}-${Math.floor(SDK_VERSION)}`);
        }
        if (deviceType) {
            CSSUtils.pushToSystemCssClasses(`${CSSUtils.CLASS_PREFIX}${deviceType}`);
        }
        rootView.cssClasses.add(CSSUtils.ROOT_VIEW_CSS_CLASS);
        const rootViewCssClasses = CSSUtils.getSystemCssClasses();
        rootViewCssClasses.forEach((c) => rootView.cssClasses.add(c));
        // Two windows can disagree on these, so they never reach the process-wide
        // system class list — see CSSUtils.WINDOW_SCOPED_CSS_CLASSES.
        const orientationValue = this.orientation();
        const appearanceValue = this.systemAppearance();
        const directionValue = this.layoutDirection();
        if (orientationValue) {
            rootView.cssClasses.add(`${CSSUtils.CLASS_PREFIX}${orientationValue}`);
        }
        if (appearanceValue) {
            rootView.cssClasses.add(`${CSSUtils.CLASS_PREFIX}${appearanceValue}`);
        }
        if (directionValue) {
            rootView.cssClasses.add(`${CSSUtils.CLASS_PREFIX}${directionValue}`);
        }
        this._increaseStyleScopeVersion(rootView);
        rootView._onCssStateChange();
        if (Trace.isEnabled()) {
            const rootCssClasses = Array.from(rootView.cssClasses);
            Trace.write(`NativeWindow [${this.id}] Setting root css classes: ${rootCssClasses.join(' ')}`, Trace.categories.Style);
        }
    }
    // --- Orientation / Appearance / Direction change handling ---
    /**
     * @internal – called by platform when orientation changes for this window.
     */
    _setOrientation(value) {
        if (this._orientation === value) {
            return;
        }
        this._orientation = value;
        if (this._rootView) {
            const cssClass = `${CSSUtils.CLASS_PREFIX}${value}`;
            this._applyCssClass(this._rootView, ORIENTATION_CSS_CLASSES, cssClass);
        }
        this._notifyValueChanged(NativeWindowEvents.orientationChanged, value);
    }
    /**
     * @internal – called by platform when system appearance changes for this window.
     */
    _setSystemAppearance(value) {
        if (this._systemAppearance === value) {
            return;
        }
        this._systemAppearance = value;
        // `Application.autoSystemAppearanceChanged` opts out of the CSS classes only —
        // the event still fires so apps driving their own theming can react to it.
        if (this._rootView && getAutoSystemAppearanceChanged()) {
            const cssClass = `${CSSUtils.CLASS_PREFIX}${value}`;
            this._applyCssClass(this._rootView, SYSTEM_APPEARANCE_CSS_CLASSES, cssClass);
        }
        this._notifyValueChanged(NativeWindowEvents.systemAppearanceChanged, value);
    }
    /**
     * @internal – called by platform when layout direction changes for this window.
     */
    _setLayoutDirection(value) {
        if (this._layoutDirection === value) {
            return;
        }
        this._layoutDirection = value;
        if (this._rootView) {
            const cssClass = `${CSSUtils.CLASS_PREFIX}${value}`;
            this._applyCssClass(this._rootView, LAYOUT_DIRECTION_CSS_CLASSES, cssClass);
        }
        this._notifyValueChanged(NativeWindowEvents.layoutDirectionChanged, value);
    }
    // --- Internal helpers ---
    _notifyValueChanged(eventName, newValue) {
        this.notify({
            eventName,
            object: this,
            window: this,
            newValue,
        });
    }
    _applyCssClass(rootView, cssClasses, newCssClass) {
        if (!rootView.cssClasses.has(newCssClass)) {
            cssClasses.forEach((cssClass) => rootView.cssClasses.delete(cssClass));
            rootView.cssClasses.add(newCssClass);
            this._increaseStyleScopeVersion(rootView);
            rootView._onCssStateChange();
        }
        // The modal registry is process-wide, so only the modals presented over this
        // window's root view may follow it.
        const rootModalViews = rootView._getRootModalViews();
        rootModalViews.forEach((modalView) => {
            if (modalView._getRootModalHost() !== rootView) {
                return;
            }
            if (!modalView.cssClasses.has(newCssClass)) {
                cssClasses.forEach((cssClass) => modalView.cssClasses.delete(cssClass));
                modalView.cssClasses.add(newCssClass);
                modalView._onCssStateChange();
            }
        });
    }
    _increaseStyleScopeVersion(rootView) {
        const styleScope = rootView._styleScope ?? rootView?.currentPage?._styleScope;
        if (styleScope) {
            styleScope._increaseApplicationCssSelectorVersion();
        }
    }
    /**
     * @internal – the native surface went away but the window session lives on.
     *
     * The window stays registered and keeps its listeners, so app code that subscribed
     * to it keeps working once a surface re-attaches. The root view keeps pointing back at
     * this window for the same reason — it is still this window's content.
     */
    _detach() {
        // Take a final reading while the surface can still answer and the root view is
        // still up: from here on these are what the window reports.
        this.orientation();
        this.systemAppearance();
        this.layoutDirection();
        if (this._rootView) {
            if (this._rootView.isLoaded) {
                this._rootView.callUnloaded();
            }
            this._rootView._tearDownUI(true);
            this._rootView._onRootViewReset();
        }
        this._setState('detached');
        this._notifyEvent(NativeWindowEvents.detached);
    }
    _onDestroy() {
        super._onDestroy();
        if (this._rootView) {
            if (this._rootView.isLoaded) {
                this._rootView.callUnloaded();
            }
            this._rootView._onRootViewReset();
            this._rootView._nativeWindow = null;
            this._rootView = null;
        }
    }
}
//# sourceMappingURL=native-window-common.js.map