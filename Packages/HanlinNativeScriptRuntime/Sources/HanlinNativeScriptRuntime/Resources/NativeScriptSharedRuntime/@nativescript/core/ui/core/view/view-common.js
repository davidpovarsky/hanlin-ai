import { booleanConverter, ViewBase } from '../view-base';
import { getEventOrGestureName } from '../bindable';
import { layout } from '../../../utils';
import { isObject } from '../../../utils/types';
import { sanitizeModuleName } from '../../../utils/common';
import { Property, InheritedProperty, CssProperty } from '../properties';
import { Style } from '../../styling/style';
import { ViewHelper } from './view-helper';
import { setupAccessibleView } from '../../../application/helpers';
import { PercentLength } from '../../styling/length-shared';
import { observe as gestureObserve, GestureTypes, fromString as gestureFromString, toString as gestureToString, TouchManager } from '../../gestures';
import { CSSUtils } from '../../../css/system-classes';
import { Builder } from '../../builder';
import { StyleScope } from '../../styling/style-scope';
import { Animation } from '../../animation';
import { getFontScale } from '../../../accessibility';
import { accessibilityHintProperty, accessibilityIdentifierProperty, accessibilityLabelProperty, accessibilityValueProperty, accessibilityIgnoresInvertColorsProperty } from '../../../accessibility/accessibility-properties';
import { accessibilityBlurEvent, accessibilityFocusChangedEvent, accessibilityFocusEvent, accessibilityPerformEscapeEvent } from '../../../accessibility';
import { SharedTransition } from '../../transition/shared-transition';
import { Trace } from '../../styling/styling-shared';
// helpers (these are okay re-exported here)
export * from './view-helper';
export function CSSType(type) {
    return (cls) => {
        cls.prototype.cssType = type;
    };
}
export function viewMatchesModuleContext(view, context, types) {
    return context && view._moduleName && context.type && types.some((type) => type === context.type) && context.path && context.path.includes(view._moduleName);
}
export function PseudoClassHandler(...pseudoClasses) {
    const stateEventNames = pseudoClasses.map((s) => ':' + s);
    return (target, propertyKey, descriptor) => {
        // This will help keep track of pseudo-class subscription changes
        const subscribeKey = Symbol(propertyKey + '_flag');
        function onSubscribe(subscribe) {
            if (subscribe != !!this[subscribeKey]) {
                this[subscribeKey] = subscribe;
                this[propertyKey](subscribe);
            }
        }
        for (const eventName of stateEventNames) {
            target[eventName] = onSubscribe;
        }
    };
}
export const _rootModalViews = new Array();
// TODO: remove once we fully switch to the new event system
const warnedEvent = new Set();
// Resolves a max-width/max-height style value to an effective device-pixel constraint.
// 'auto' (the default) or an unresolvable percent (parent size unknown) means "no maximum",
// represented as Infinity so that Math.min(measured, effectiveMax) becomes a no-op.
function resolveEffectiveMax(value, availableSize) {
    if (value == null || value === 'auto') {
        return Number.POSITIVE_INFINITY;
    }
    // A percent cannot be resolved when the parent size is unspecified (availableSize < 0);
    // treat it as unconstrained rather than collapsing the view to ~0.
    if (typeof value === 'object' && value.unit === '%' && availableSize < 0) {
        return Number.POSITIVE_INFINITY;
    }
    const resolved = PercentLength.toDevicePixels(value, Number.POSITIVE_INFINITY, availableSize);
    // Safety net for any other unresolved/bogus negative result.
    return resolved < 0 ? Number.POSITIVE_INFINITY : resolved;
}
export class ViewCommon extends ViewBase {
    constructor() {
        super(...arguments);
        this._gestureObservers = {};
    }
    get css() {
        const scope = this._styleScope;
        return scope && scope.css;
    }
    set css(value) {
        this._updateStyleScope(undefined, undefined, value);
    }
    addCss(cssString) {
        this._updateStyleScope(undefined, cssString);
    }
    addCssFile(cssFileName) {
        this._updateStyleScope(cssFileName);
    }
    changeCssFile(cssFileName) {
        const scope = this._styleScope;
        if (scope && cssFileName) {
            scope.changeCssFile(cssFileName);
            this._onCssStateChange();
        }
    }
    _updateStyleScope(cssFileName, cssString, css) {
        let scope = this._styleScope;
        if (!scope) {
            scope = new StyleScope();
            this.setScopeProperty(scope, cssFileName, cssString, css);
            this._inheritStyleScope(scope);
            this._isStyleScopeHost = true;
        }
        else {
            this.setScopeProperty(scope, cssFileName, cssString, css);
            this._onCssStateChange();
        }
    }
    setScopeProperty(scope, cssFileName, cssString, css) {
        if (cssFileName !== undefined) {
            scope.addCssFile(cssFileName);
        }
        else if (cssString !== undefined) {
            scope.addCss(cssString);
        }
        else if (css !== undefined) {
            scope.css = css;
        }
    }
    onLoaded() {
        if (!this.isLoaded) {
            const hasTap = this.hasListeners('tap') || this.hasListeners('tapChange') || !!this.getGestureObservers(GestureTypes.tap);
            const enableTapAnimations = TouchManager.enableGlobalTapAnimations && hasTap;
            if (!this.ignoreTouchAnimation && (this.touchAnimation || enableTapAnimations)) {
                TouchManager.addAnimations(this);
            }
            if (__VISIONOS__) {
                const enableHoverStyle = TouchManager.enableGlobalHoverWhereTap && hasTap;
                if (!this.visionIgnoreHoverStyle && (this.visionHoverStyle || enableHoverStyle)) {
                    TouchManager.addHoverStyle(this);
                }
            }
        }
        super.onLoaded();
        setupAccessibleView(this);
        if (this.statusBarStyle) {
            // reapply status bar style on load
            // helps back navigation cases to restore if overridden
            this.updateStatusBarStyle(this.statusBarStyle);
        }
    }
    _closeAllModalViewsInternal() {
        if (_rootModalViews && _rootModalViews.length > 0) {
            _rootModalViews.forEach((v) => {
                v.closeModal();
            });
            return true;
        }
        return false;
    }
    _getRootModalViews() {
        return _rootModalViews;
    }
    _getRootModalHost() {
        let view = this;
        while (view) {
            // A modal root has no parent, so the chain continues through the view it was
            // presented over; nested modals therefore resolve to the same window root.
            const next = view.parent ?? view._modalParent;
            if (!next) {
                break;
            }
            view = next;
        }
        return view;
    }
    /**
     * The window currently hosting this view, or `undefined` when the view is not part of
     * any window's view tree — including a view whose window has been closed.
     *
     * Resolved on every call by walking up to the root view — through the presenting view
     * of any modal on the way — so a view re-parented into another window's tree reports
     * the window it moved to.
     */
    getNativeWindow() {
        return this._getRootModalHost()?._nativeWindow ?? undefined;
    }
    _onLivesync(context) {
        if (Trace.isEnabled()) {
            Trace.write(`${this}._onLivesync(${JSON.stringify(context)})`, Trace.categories.Livesync);
        }
        let handled = false;
        if (this._closeAllModalViewsInternal()) {
            handled = true;
        }
        if (this._handleLivesync(context)) {
            return true;
        }
        this.eachChildView((child) => {
            if (child._onLivesync(context)) {
                handled = true;
                return false;
            }
        });
        return handled;
    }
    _handleLivesync(context) {
        if (Trace.isEnabled()) {
            Trace.write(`${this}._handleLivesync(${JSON.stringify(context)})`, Trace.categories.Livesync);
        }
        // Handle local CSS
        if (viewMatchesModuleContext(this, context, ['style'])) {
            if (Trace.isEnabled()) {
                Trace.write(`Change Handled: Changing CSS for ${this}`, Trace.categories.Livesync);
            }
            // Always load styles with ".css" extension. Even when changes are in ".scss" ot ".less" files
            const cssModuleName = `${sanitizeModuleName(context.path)}.css`;
            this.changeCssFile(cssModuleName);
            return true;
        }
        // Handle script/markup changes in custom components by falling back to page refresh
        if (viewMatchesModuleContext(this, context, ['markup', 'script']) && this.page && this.page.frame) {
            if (Trace.isEnabled()) {
                Trace.write(`Change Handled: Changing ${context.type} for ${this} inside ${this.page}`, Trace.categories.Livesync);
            }
            return this.page.frame._handleLivesync({
                type: context.type,
                path: this.page._moduleName,
            });
        }
        return false;
    }
    _setupAsRootView(context) {
        super._setupAsRootView(context);
        if (!this._styleScope) {
            this._updateStyleScope();
        }
    }
    _observe(type, callback, thisArg) {
        thisArg = thisArg || undefined;
        if (this._gestureObservers[type]?.find((observer) => observer.callback === callback && observer.context === thisArg)) {
            // Already added.
            return;
        }
        if (!this._gestureObservers[type]) {
            this._gestureObservers[type] = [];
        }
        this._gestureObservers[type].push(gestureObserve(this, type, callback, thisArg));
    }
    getGestureObservers(type) {
        return this._gestureObservers[type];
    }
    addEventListener(eventNames, callback, thisArg, once) {
        thisArg = thisArg || undefined;
        // TODO: Remove this once we fully switch to the new event system
        if (typeof eventNames === 'number') {
            // likely a gesture type from a plugin
            const gestureName = gestureToString(eventNames);
            if (!warnedEvent.has(gestureName)) {
                console.warn(`Using a gesture type (${gestureName}) as an event name is deprecated. Please use the event name instead.`);
                warnedEvent.add(gestureName);
            }
            eventNames = gestureName;
        }
        // Normalize "ontap" -> "tap"
        const normalizedName = getEventOrGestureName(eventNames);
        // Coerce "tap" -> GestureTypes.tap
        // Coerce "loaded" -> undefined
        const gestureType = gestureFromString(normalizedName);
        // If it's a gesture (and this Observable declares e.g. `static tapEvent`)
        if (gestureType && !this._isEvent(normalizedName)) {
            this._observe(gestureType, callback, thisArg);
            return;
        }
        super.addEventListener(normalizedName, callback, thisArg, once);
    }
    removeEventListener(eventNames, callback, thisArg) {
        thisArg = thisArg || undefined;
        // TODO: Remove this once we fully switch to the new event system
        if (typeof eventNames === 'number') {
            // likely a gesture type from a plugin
            const gestureName = gestureToString(eventNames);
            if (!warnedEvent.has(gestureName)) {
                console.warn(`Using a gesture type (${gestureName}) as an event name is deprecated. Please use the event name instead.`);
                warnedEvent.add(gestureName);
            }
            eventNames = gestureName;
        }
        // Normalize "ontap" -> "tap"
        const normalizedName = getEventOrGestureName(eventNames);
        // Coerce "tap" -> GestureTypes.tap
        // Coerce "loaded" -> undefined
        const gestureType = gestureFromString(normalizedName);
        // If it's a gesture (and this Observable declares e.g. `static tapEvent`)
        if (gestureType && !this._isEvent(normalizedName)) {
            this._disconnectGestureObservers(gestureType, callback, thisArg);
            return;
        }
        super.removeEventListener(normalizedName, callback, thisArg);
    }
    onBackPressed() {
        return false;
    }
    _getFragmentManager() {
        return undefined;
    }
    getModalOptions(args) {
        if (args.length === 0) {
            throw new Error('showModal without parameters is deprecated. Please call showModal on a view instance instead.');
        }
        else {
            let options = null;
            if (args.length === 2) {
                options = args[1];
            }
            else {
                if (args[0] instanceof ViewCommon) {
                    console.log('showModal(view: ViewBase, context: any, closeCallback: Function, fullscreen?: boolean, animated?: boolean, stretched?: boolean) ' + 'is deprecated. Use showModal(view: ViewBase, modalOptions: ShowModalOptions) instead.');
                }
                else {
                    console.log('showModal(moduleName: string, context: any, closeCallback: Function, fullscreen?: boolean, animated?: boolean, stretched?: boolean) ' + 'is deprecated. Use showModal(moduleName: string, modalOptions: ShowModalOptions) instead.');
                }
                options = {
                    context: args[1],
                    closeCallback: args[2],
                    fullscreen: args[3],
                    animated: args[4],
                    stretched: args[5],
                };
            }
            const firstArgument = args[0];
            const view = firstArgument instanceof ViewCommon ? firstArgument : Builder.createViewFromEntry({
                moduleName: firstArgument,
            });
            return { view, options };
        }
    }
    showModal(...args) {
        const { view, options } = this.getModalOptions(args);
        if (options.transition?.instance) {
            SharedTransition.updateState(options.transition?.instance.id, {
                page: this,
                toPage: view,
            });
        }
        view._showNativeModalView(this, options);
        return view;
    }
    closeModal(...args) {
        const closeCallback = this._closeModalCallback;
        if (closeCallback) {
            closeCallback(...args);
        }
        else {
            const parent = this.parent;
            if (parent) {
                parent.closeModal(...args);
            }
        }
    }
    get modal() {
        return this._modal;
    }
    _showNativeModalView(parent, options) {
        _rootModalViews.push(this);
        this.cssClasses.add(CSSUtils.MODAL_ROOT_VIEW_CSS_CLASS);
        const modalRootViewCssClasses = CSSUtils.getSystemCssClasses();
        modalRootViewCssClasses.forEach((c) => this.cssClasses.add(c));
        // Orientation/appearance/direction are not in the system class list because they
        // differ per window, so they are inherited from the root this modal opens over.
        const host = parent._getRootModalHost();
        if (host) {
            CSSUtils.WINDOW_SCOPED_CSS_CLASSES.forEach((c) => {
                if (host.cssClasses.has(c)) {
                    this.cssClasses.add(c);
                }
            });
        }
        parent._modal = this;
        this.style.fontScaleInternal = getFontScale();
        this._modalParent = parent;
        this._modalContext = options.context;
        this._modalOptions = options;
        this._closeModalCallback = (...originalArgs) => {
            const cleanupModalViews = () => {
                const modalIndex = _rootModalViews.indexOf(this);
                if (modalIndex > -1) {
                    _rootModalViews.splice(modalIndex, 1);
                }
                this._modalParent = null;
                this._modalContext = null;
                this._modalOptions = null;
                this._closeModalCallback = null;
                this._dialogClosed();
                parent._modal = null;
            };
            const whenClosedCallback = () => {
                const transitionState = SharedTransition.getState(this.transitionId);
                if (transitionState?.interactiveBegan) {
                    SharedTransition.updateState(this.transitionId, {
                        interactiveBegan: false,
                    });
                    if (!transitionState?.interactiveCancelled) {
                        cleanupModalViews();
                    }
                }
                if (!transitionState?.interactiveCancelled) {
                    if (typeof options.closeCallback === 'function') {
                        options.closeCallback.apply(undefined, originalArgs);
                    }
                    this._tearDownUI(true);
                    // Native dismissal fully completed (this callback runs in the
                    // platform dismissal completion) — observable counterpart to the
                    // per-show closeCallback. Used by dev tooling (HMR modal
                    // re-present) to know exactly when a new present is safe.
                    this.notify({
                        eventName: ViewCommon.closedModallyEvent,
                        object: this,
                    });
                }
            };
            const transitionState = SharedTransition.getState(this.transitionId);
            if (!transitionState?.interactiveBegan) {
                cleanupModalViews();
            }
            this._hideNativeModalView(parent, whenClosedCallback);
        };
    }
    _hideNativeModalView(parent, whenClosedCallback) { }
    _raiseLayoutChangedEvent() {
        const args = {
            eventName: ViewCommon.layoutChangedEvent,
            object: this,
        };
        this.notify(args);
    }
    _raiseShownModallyEvent() {
        const args = {
            eventName: ViewCommon.shownModallyEvent,
            object: this,
            context: this._modalContext,
            closeCallback: this._closeModalCallback,
        };
        this.notify(args);
    }
    _raiseShowingModallyEvent() {
        const args = {
            eventName: ViewCommon.showingModallyEvent,
            object: this,
            context: this._modalContext,
            closeCallback: this._closeModalCallback,
        };
        this.notify(args);
    }
    _isEvent(name) {
        return this.constructor && `${name}Event` in this.constructor;
    }
    _disconnectGestureObservers(type, callback, thisArg) {
        // Largely mirrors the implementation of Observable.innerRemoveEventListener().
        const observers = this.getGestureObservers(type);
        if (!observers) {
            return;
        }
        for (let i = 0; i < observers.length; i++) {
            const observer = observers[i];
            // If we have a `thisArg`, refine on both `callback` and `thisArg`.
            if (thisArg && (observer.callback !== callback || observer.context !== thisArg)) {
                continue;
            }
            // If we don't have a `thisArg`, refine only on `callback`.
            if (callback && observer.callback !== callback) {
                continue;
            }
            observer.disconnect();
            observers.splice(i, 1);
            i--;
        }
        if (!observers.length) {
            delete this._gestureObservers[type];
        }
    }
    // START Style property shortcuts
    get flexFlow() {
        return this.style.flexFlow;
    }
    set flexFlow(value) {
        this.style.flexFlow = value;
    }
    get flex() {
        return this.style.flex;
    }
    set flex(value) {
        this.style.flex = value;
    }
    get borderColor() {
        return this.style.borderColor;
    }
    set borderColor(value) {
        this.style.borderColor = value;
    }
    get borderTopColor() {
        return this.style.borderTopColor;
    }
    set borderTopColor(value) {
        this.style.borderTopColor = value;
    }
    get borderRightColor() {
        return this.style.borderRightColor;
    }
    set borderRightColor(value) {
        this.style.borderRightColor = value;
    }
    get borderBottomColor() {
        return this.style.borderBottomColor;
    }
    set borderBottomColor(value) {
        this.style.borderBottomColor = value;
    }
    get borderLeftColor() {
        return this.style.borderLeftColor;
    }
    set borderLeftColor(value) {
        this.style.borderLeftColor = value;
    }
    get borderWidth() {
        return this.style.borderWidth;
    }
    set borderWidth(value) {
        this.style.borderWidth = value;
    }
    get borderTopWidth() {
        return this.style.borderTopWidth;
    }
    set borderTopWidth(value) {
        this.style.borderTopWidth = value;
    }
    get borderRightWidth() {
        return this.style.borderRightWidth;
    }
    set borderRightWidth(value) {
        this.style.borderRightWidth = value;
    }
    get borderBottomWidth() {
        return this.style.borderBottomWidth;
    }
    set borderBottomWidth(value) {
        this.style.borderBottomWidth = value;
    }
    get borderLeftWidth() {
        return this.style.borderLeftWidth;
    }
    set borderLeftWidth(value) {
        this.style.borderLeftWidth = value;
    }
    get borderRadius() {
        return this.style.borderRadius;
    }
    set borderRadius(value) {
        this.style.borderRadius = value;
    }
    get borderTopLeftRadius() {
        return this.style.borderTopLeftRadius;
    }
    set borderTopLeftRadius(value) {
        this.style.borderTopLeftRadius = value;
    }
    get borderTopRightRadius() {
        return this.style.borderTopRightRadius;
    }
    set borderTopRightRadius(value) {
        this.style.borderTopRightRadius = value;
    }
    get borderBottomRightRadius() {
        return this.style.borderBottomRightRadius;
    }
    set borderBottomRightRadius(value) {
        this.style.borderBottomRightRadius = value;
    }
    get borderBottomLeftRadius() {
        return this.style.borderBottomLeftRadius;
    }
    set borderBottomLeftRadius(value) {
        this.style.borderBottomLeftRadius = value;
    }
    get color() {
        return this.style.color;
    }
    set color(value) {
        this.style.color = value;
    }
    get background() {
        return this.style.background;
    }
    set background(value) {
        this.style.background = value;
    }
    get backgroundColor() {
        return this.style.backgroundColor;
    }
    set backgroundColor(value) {
        this.style.backgroundColor = value;
    }
    get backgroundImage() {
        return this.style.backgroundImage;
    }
    set backgroundImage(value) {
        this.style.backgroundImage = value;
    }
    get backgroundSize() {
        return this.style.backgroundSize;
    }
    set backgroundSize(value) {
        this.style.backgroundSize = value;
    }
    get backgroundPosition() {
        return this.style.backgroundPosition;
    }
    set backgroundPosition(value) {
        this.style.backgroundPosition = value;
    }
    get backgroundRepeat() {
        return this.style.backgroundRepeat;
    }
    set backgroundRepeat(value) {
        this.style.backgroundRepeat = value;
    }
    get boxShadow() {
        return this.style.boxShadow;
    }
    set boxShadow(value) {
        this.style.boxShadow = value;
    }
    get direction() {
        return this.style.direction;
    }
    set direction(value) {
        this.style.direction = value;
    }
    get minWidth() {
        return this.style.minWidth;
    }
    set minWidth(value) {
        this.style.minWidth = value;
    }
    get minHeight() {
        return this.style.minHeight;
    }
    set minHeight(value) {
        this.style.minHeight = value;
    }
    get maxWidth() {
        return this.style.maxWidth;
    }
    set maxWidth(value) {
        this.style.maxWidth = value;
    }
    get maxHeight() {
        return this.style.maxHeight;
    }
    set maxHeight(value) {
        this.style.maxHeight = value;
    }
    get width() {
        return this.style.width;
    }
    set width(value) {
        this.style.width = value;
    }
    get height() {
        return this.style.height;
    }
    set height(value) {
        this.style.height = value;
    }
    get margin() {
        return this.style.margin;
    }
    set margin(value) {
        this.style.margin = value;
    }
    get marginLeft() {
        return this.style.marginLeft;
    }
    set marginLeft(value) {
        this.style.marginLeft = value;
    }
    get marginTop() {
        return this.style.marginTop;
    }
    set marginTop(value) {
        this.style.marginTop = value;
    }
    get marginRight() {
        return this.style.marginRight;
    }
    set marginRight(value) {
        this.style.marginRight = value;
    }
    get marginBottom() {
        return this.style.marginBottom;
    }
    set marginBottom(value) {
        this.style.marginBottom = value;
    }
    get horizontalAlignment() {
        return this.style.horizontalAlignment;
    }
    set horizontalAlignment(value) {
        this.style.horizontalAlignment = value;
    }
    get verticalAlignment() {
        return this.style.verticalAlignment;
    }
    set verticalAlignment(value) {
        this.style.verticalAlignment = value;
    }
    get visibility() {
        return this.style.visibility;
    }
    set visibility(value) {
        this.style.visibility = value;
    }
    get opacity() {
        return this.style.opacity;
    }
    set opacity(value) {
        this.style.opacity = value;
    }
    get rotate() {
        return this.style.rotate;
    }
    set rotate(value) {
        this.style.rotate = value;
    }
    get rotateX() {
        return this.style.rotateX;
    }
    set rotateX(value) {
        this.style.rotateX = value;
    }
    get rotateY() {
        return this.style.rotateY;
    }
    set rotateY(value) {
        this.style.rotateY = value;
    }
    get perspective() {
        return this.style.perspective;
    }
    set perspective(value) {
        this.style.perspective = value;
    }
    get textTransform() {
        return this.style.textTransform;
    }
    set textTransform(value) {
        this.style.textTransform = value;
    }
    get translateX() {
        return this.style.translateX;
    }
    set translateX(value) {
        this.style.translateX = value;
    }
    get translateY() {
        return this.style.translateY;
    }
    set translateY(value) {
        this.style.translateY = value;
    }
    get scaleX() {
        return this.style.scaleX;
    }
    set scaleX(value) {
        this.style.scaleX = value;
    }
    get scaleY() {
        return this.style.scaleY;
    }
    set scaleY(value) {
        this.style.scaleY = value;
    }
    get accessible() {
        return this.style.accessible;
    }
    set accessible(value) {
        this.style.accessible = value;
    }
    get accessibilityHidden() {
        return this.style.accessibilityHidden;
    }
    set accessibilityHidden(value) {
        this.style.accessibilityHidden = value;
    }
    get accessibilityRole() {
        return this.style.accessibilityRole;
    }
    set accessibilityRole(value) {
        this.style.accessibilityRole = value;
    }
    get accessibilityState() {
        return this.style.accessibilityState;
    }
    set accessibilityState(value) {
        this.style.accessibilityState = value;
    }
    get accessibilityLiveRegion() {
        return this.style.accessibilityLiveRegion;
    }
    set accessibilityLiveRegion(value) {
        this.style.accessibilityLiveRegion = value;
    }
    get accessibilityLanguage() {
        return this.style.accessibilityLanguage;
    }
    set accessibilityLanguage(value) {
        this.style.accessibilityLanguage = value;
    }
    get accessibilityMediaSession() {
        return this.style.accessibilityMediaSession;
    }
    set accessibilityMediaSession(value) {
        this.style.accessibilityMediaSession = value;
    }
    get iosAccessibilityAdjustsFontSize() {
        return this.style.iosAccessibilityAdjustsFontSize;
    }
    set iosAccessibilityAdjustsFontSize(value) {
        this.style.iosAccessibilityAdjustsFontSize = value;
    }
    get iosAccessibilityMinFontScale() {
        return this.style.iosAccessibilityMinFontScale;
    }
    set iosAccessibilityMinFontScale(value) {
        this.style.iosAccessibilityMinFontScale = value;
    }
    get iosAccessibilityMaxFontScale() {
        return this.style.iosAccessibilityMaxFontScale;
    }
    set iosAccessibilityMaxFontScale(value) {
        this.style.iosAccessibilityMaxFontScale = value;
    }
    get automationText() {
        return this.accessibilityIdentifier;
    }
    set automationText(value) {
        this.accessibilityIdentifier = value;
    }
    get androidElevation() {
        return this.style.androidElevation;
    }
    set androidElevation(value) {
        this.style.androidElevation = value;
    }
    get androidDynamicElevationOffset() {
        return this.style.androidDynamicElevationOffset;
    }
    set androidDynamicElevationOffset(value) {
        this.style.androidDynamicElevationOffset = value;
    }
    /**
     * (Android only) Gets closest window parent considering modals.
     */
    getClosestWindow() {
        // platform impl
        return null;
    }
    //END Style property shortcuts
    get isLayoutValid() {
        return false;
    }
    get cssType() {
        if (!this._cssType) {
            this._cssType = this.typeName.toLowerCase();
        }
        return this._cssType;
    }
    set cssType(type) {
        this._cssType = type.toLowerCase();
    }
    get statusBarStyle() {
        return this.style.statusBarStyle;
    }
    set statusBarStyle(value) {
        this.style.statusBarStyle = value;
    }
    updateStatusBarStyle(value) {
        // platform specific impl
    }
    get isLayoutRequired() {
        return true;
    }
    get needsNativeDrawableFill() {
        return false;
    }
    measure(widthMeasureSpec, heightMeasureSpec) {
        this._setCurrentMeasureSpecs(widthMeasureSpec, heightMeasureSpec);
    }
    layout(left, top, right, bottom) {
        this._setCurrentLayoutBounds(left, top, right, bottom);
    }
    getMeasuredWidth() {
        return this._measuredWidth & layout.MEASURED_SIZE_MASK || 0;
    }
    getMeasuredHeight() {
        return this._measuredHeight & layout.MEASURED_SIZE_MASK || 0;
    }
    getMeasuredState() {
        return (this._measuredWidth & layout.MEASURED_STATE_MASK) | ((this._measuredHeight >> layout.MEASURED_HEIGHT_STATE_SHIFT) & (layout.MEASURED_STATE_MASK >> layout.MEASURED_HEIGHT_STATE_SHIFT));
    }
    setMeasuredDimension(measuredWidth, measuredHeight) {
        this._measuredWidth = measuredWidth;
        this._measuredHeight = measuredHeight;
        if (Trace.isEnabled()) {
            Trace.write(this + ' :setMeasuredDimension: ' + measuredWidth + ', ' + measuredHeight, Trace.categories.Layout);
        }
    }
    static resolveSizeAndState(size, specSize, specMode, childMeasuredState) {
        return ViewHelper.resolveSizeAndState(size, specSize, specMode, childMeasuredState);
    }
    static combineMeasuredStates(curState, newState) {
        return ViewHelper.combineMeasuredStates(curState, newState);
    }
    static layoutChild(parent, child, left, top, right, bottom, setFrame = true) {
        ViewHelper.layoutChild(parent, child, left, top, right, bottom);
    }
    static measureChild(parent, child, widthMeasureSpec, heightMeasureSpec) {
        return ViewHelper.measureChild(parent, child, widthMeasureSpec, heightMeasureSpec);
    }
    _setCurrentMeasureSpecs(widthMeasureSpec, heightMeasureSpec) {
        const changed = this._currentWidthMeasureSpec !== widthMeasureSpec || this._currentHeightMeasureSpec !== heightMeasureSpec;
        this._currentWidthMeasureSpec = widthMeasureSpec;
        this._currentHeightMeasureSpec = heightMeasureSpec;
        return changed;
    }
    _getCurrentLayoutBounds() {
        return { left: 0, top: 0, right: 0, bottom: 0 };
    }
    /**
     * Returns two booleans - the first if "boundsChanged" the second is "sizeChanged".
     */
    _setCurrentLayoutBounds(left, top, right, bottom) {
        const boundsChanged = this._oldLeft !== left || this._oldTop !== top || this._oldRight !== right || this._oldBottom !== bottom;
        const sizeChanged = this._oldRight - this._oldLeft !== right - left || this._oldBottom - this._oldTop !== bottom - top;
        this._oldLeft = left;
        this._oldTop = top;
        this._oldRight = right;
        this._oldBottom = bottom;
        return { boundsChanged, sizeChanged };
    }
    eachChild(callback) {
        this.eachChildView(callback);
    }
    eachChildView(callback) {
        //
    }
    _getNativeViewsCount() {
        return this._isAddedToNativeVisualTree ? 1 : 0;
    }
    _eachLayoutView(callback) {
        return callback(this);
    }
    focus() {
        return undefined;
    }
    getSafeAreaInsets() {
        return { left: 0, top: 0, right: 0, bottom: 0 };
    }
    getLocationInWindow() {
        return undefined;
    }
    getLocationOnScreen() {
        return undefined;
    }
    getLocationRelativeTo(otherView) {
        return undefined;
    }
    getActualSize() {
        const currentBounds = this._getCurrentLayoutBounds();
        if (!currentBounds) {
            return undefined;
        }
        return {
            width: layout.toDeviceIndependentPixels(currentBounds.right - currentBounds.left),
            height: layout.toDeviceIndependentPixels(currentBounds.bottom - currentBounds.top),
        };
    }
    animate(animation) {
        const animationInstance = this.createAnimation(animation);
        const promise = animationInstance.play();
        promise.cancel = () => animationInstance.cancel();
        return promise;
    }
    createAnimation(animation) {
        if (!this._localAnimations) {
            this._localAnimations = new Set();
        }
        animation.target = this;
        const anim = new Animation([animation]);
        this._localAnimations.add(anim);
        return anim;
    }
    _removeAnimation(animation) {
        const localAnimations = this._localAnimations;
        if (localAnimations && localAnimations.has(animation)) {
            localAnimations.delete(animation);
            if (animation.isPlaying) {
                animation.cancel();
            }
            return true;
        }
        return false;
    }
    resetNativeView() {
        if (this._localAnimations) {
            this._localAnimations.forEach((a) => this._removeAnimation(a));
        }
        super.resetNativeView();
    }
    _modifyNativeViewFrame(nativeView, frame) {
        //
    }
    _setNativeViewFrame(nativeView, frame) {
        //
    }
    _getValue() {
        throw new Error('The View._getValue is obsolete. There is a new property system.');
    }
    _setValue() {
        throw new Error('The View._setValue is obsolete. There is a new property system.');
    }
    _updateEffectiveLayoutValues(parentWidthMeasureSize, parentWidthMeasureMode, parentHeightMeasureSize, parentHeightMeasureMode) {
        const style = this.style;
        const availableWidth = parentWidthMeasureMode === layout.UNSPECIFIED ? -1 : parentWidthMeasureSize;
        this.effectiveWidth = PercentLength.toDevicePixels(style.width, -2, availableWidth);
        this.effectiveMaxWidth = resolveEffectiveMax(style.maxWidth, availableWidth);
        this.effectiveMarginLeft = PercentLength.toDevicePixels(style.marginLeft, 0, availableWidth);
        this.effectiveMarginRight = PercentLength.toDevicePixels(style.marginRight, 0, availableWidth);
        const availableHeight = parentHeightMeasureMode === layout.UNSPECIFIED ? -1 : parentHeightMeasureSize;
        this.effectiveHeight = PercentLength.toDevicePixels(style.height, -2, availableHeight);
        this.effectiveMaxHeight = resolveEffectiveMax(style.maxHeight, availableHeight);
        this.effectiveMarginTop = PercentLength.toDevicePixels(style.marginTop, 0, availableHeight);
        this.effectiveMarginBottom = PercentLength.toDevicePixels(style.marginBottom, 0, availableHeight);
    }
    _setNativeClipToBounds() {
        //
    }
    _redrawNativeBackground(value) {
        //
    }
    _applyBackground(background, isBorderDrawable, onlyColor, backgroundDrawable) {
        //
    }
    _onAttachedToWindow() {
        //
    }
    _onDetachedFromWindow() {
        //
    }
    _hasAncestorView(ancestorView) {
        const matcher = (view) => view === ancestorView;
        for (let parent = this.parent; parent != null; parent = parent.parent) {
            if (matcher(parent)) {
                return true;
            }
        }
        return false;
    }
    /**
     * Shared helper method for applying glass effects to views.
     * This method can be used by View and its subclasses (LiquidGlass, LiquidGlassContainer, etc.)
     * iOS only at the moment but could be applied to others once supported in other platforms.
     *
     * @param value - The glass effect configuration
     * @param options - Configuration options for different glass effect behaviors
     * @param options.effectType - Type of effect to create: 'glass' | 'container'
     * @param options.targetView - The UIVisualEffectView to apply the effect to (if updating existing view)
     * @param options.toGlassStyleFn - Custom function to convert variant to UIGlassEffectStyle
     * @param options.onCreate - Callback when a new effect view is created (for initial setup)
     * @param options.onUpdate - Callback when an existing effect view is updated
     */
    _applyGlassEffect(value, options) {
        return undefined;
    }
    sendAccessibilityEvent(options) {
        return;
    }
    accessibilityAnnouncement(msg) {
        return;
    }
    accessibilityScreenChanged() {
        return;
    }
    setAccessibilityIdentifier(view, value) {
        return;
    }
}
ViewCommon.layoutChangedEvent = 'layoutChanged';
ViewCommon.shownModallyEvent = 'shownModally';
ViewCommon.showingModallyEvent = 'showingModally';
/**
 * Fired on the modal view once its native dismissal has fully completed
 * (after the close callback and UI teardown). Unlike `closeCallback` —
 * which is captured per-show — any observer can listen for this, e.g.
 * tooling that needs to re-present a modal (dev-time HMR).
 */
ViewCommon.closedModallyEvent = 'closedModally';
ViewCommon.accessibilityBlurEvent = accessibilityBlurEvent;
ViewCommon.accessibilityFocusEvent = accessibilityFocusEvent;
ViewCommon.accessibilityFocusChangedEvent = accessibilityFocusChangedEvent;
ViewCommon.accessibilityPerformEscapeEvent = accessibilityPerformEscapeEvent;
ViewCommon.androidOverflowInsetEvent = 'androidOverflowInset';
export const originXProperty = new Property({
    name: 'originX',
    defaultValue: 0.5,
    valueConverter: (v) => parseFloat(v),
});
originXProperty.register(ViewCommon);
export const originYProperty = new Property({
    name: 'originY',
    defaultValue: 0.5,
    valueConverter: (v) => parseFloat(v),
});
originYProperty.register(ViewCommon);
export const isEnabledProperty = new Property({
    name: 'isEnabled',
    defaultValue: true,
    valueConverter: booleanConverter,
    valueChanged(target, oldValue, newValue) {
        const state = 'disabled';
        if (newValue) {
            target._removeVisualState(state);
        }
        else {
            target._addVisualState(state);
        }
    },
});
isEnabledProperty.register(ViewCommon);
export const isUserInteractionEnabledProperty = new Property({
    name: 'isUserInteractionEnabled',
    defaultValue: true,
    valueConverter: booleanConverter,
});
isUserInteractionEnabledProperty.register(ViewCommon);
/**
 * Property backing statusBarStyle.
 */
export const statusBarStyleProperty = new CssProperty({
    name: 'statusBarStyle',
    cssName: 'status-bar-style',
});
statusBarStyleProperty.register(Style);
// Apple only
export const iosOverflowSafeAreaProperty = new Property({
    name: 'iosOverflowSafeArea',
    defaultValue: false,
    valueConverter: booleanConverter,
});
iosOverflowSafeAreaProperty.register(ViewCommon);
export const iosOverflowSafeAreaEnabledProperty = new InheritedProperty({
    name: 'iosOverflowSafeAreaEnabled',
    defaultValue: true,
    valueConverter: booleanConverter,
});
iosOverflowSafeAreaEnabledProperty.register(ViewCommon);
export const iosIgnoreSafeAreaProperty = new InheritedProperty({
    name: 'iosIgnoreSafeArea',
    defaultValue: false,
    valueConverter: booleanConverter,
});
iosIgnoreSafeAreaProperty.register(ViewCommon);
export const androidOverflowEdgeProperty = new Property({
    name: 'androidOverflowEdge',
    defaultValue: 'ignore',
});
androidOverflowEdgeProperty.register(ViewCommon);
export const iosGlassEffectProperty = new Property({
    name: 'iosGlassEffect',
});
iosGlassEffectProperty.register(ViewCommon);
export const visionHoverStyleProperty = new Property({
    name: 'visionHoverStyle',
    valueChanged(view, oldValue, newValue) {
        view.visionHoverStyle = newValue;
    },
});
visionHoverStyleProperty.register(ViewCommon);
const visionIgnoreHoverStyleProperty = new Property({
    name: 'visionIgnoreHoverStyle',
    valueChanged(view, oldValue, newValue) {
        view.visionIgnoreHoverStyle = newValue;
    },
    valueConverter: booleanConverter,
});
visionIgnoreHoverStyleProperty.register(ViewCommon);
// Apple only end
const touchAnimationProperty = new Property({
    name: 'touchAnimation',
    valueChanged(view, oldValue, newValue) {
        view.touchAnimation = newValue;
    },
    valueConverter(value) {
        if (isObject(value)) {
            return value;
        }
        else {
            return booleanConverter(value);
        }
    },
});
touchAnimationProperty.register(ViewCommon);
const ignoreTouchAnimationProperty = new Property({
    name: 'ignoreTouchAnimation',
    valueChanged(view, oldValue, newValue) {
        view.ignoreTouchAnimation = newValue;
    },
    valueConverter: booleanConverter,
});
ignoreTouchAnimationProperty.register(ViewCommon);
const touchDelayProperty = new Property({
    name: 'touchDelay',
    valueChanged(view, oldValue, newValue) {
        view.touchDelay = newValue;
    },
    valueConverter: (v) => parseFloat(v),
});
touchDelayProperty.register(ViewCommon);
export const testIDProperty = new Property({
    name: 'testID',
});
testIDProperty.register(ViewCommon);
accessibilityIdentifierProperty.register(ViewCommon);
accessibilityLabelProperty.register(ViewCommon);
accessibilityValueProperty.register(ViewCommon);
accessibilityHintProperty.register(ViewCommon);
accessibilityIgnoresInvertColorsProperty.register(ViewCommon);
//# sourceMappingURL=view-common.js.map