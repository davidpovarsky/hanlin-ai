const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
import { Trace } from '../../styling/styling-shared';
import { Property, InheritedProperty, clearInheritedProperties, propagateInheritableProperties, propagateInheritableCssProperties, initNativeView } from '../properties';
import { CSSUtils } from '../../../css/system-classes';
import { Source } from '../../../utils/debug-source';
import { Binding } from '../bindable';
import { Observable, WrappedValue } from '../../../data/observable';
import { Style } from '../../styling/style';
// TODO: Remove this import!
import { getClass } from '../../../utils/types';
import { profile } from '../../../profiling';
import { DOMNode } from '../../../debugger/dom-types';
import { applyInlineStyle, CssState } from '../../styling/style-scope';
import { booleanConverter } from './utils';
export { booleanConverter } from './utils';
const defaultBindingSource = {};
/**
 * Gets an ancestor from a given type.
 * @param view - Starting view (child view).
 * @param criterion - The type of ancestor view we are looking for. Could be a string containing a class name or an actual type.
 * Returns an instance of a view (if found), otherwise undefined.
 */
export function getAncestor(view, criterion) {
    let matcher;
    if (typeof criterion === 'string') {
        const normalizedCriterion = criterion.toLowerCase();
        matcher = (view) => view.typeName === criterion || view.cssType === normalizedCriterion;
    }
    else {
        matcher = (view) => view instanceof criterion;
    }
    for (let parent = view.parent; parent != null; parent = parent.parent) {
        if (matcher(parent)) {
            return parent;
        }
    }
    return null;
}
/**
 * Gets a child view by id.
 * @param view - The parent (container) view of the view to look for.
 * @param id - The id of the view to look for.
 * Returns an instance of a view (if found), otherwise undefined.
 */
export function getViewById(view, id) {
    if (!view) {
        return undefined;
    }
    if (view.id === id) {
        return view;
    }
    let retVal;
    const descendantsCallback = function (child) {
        if (child.id === id) {
            retVal = child;
            // break the iteration by returning false
            return false;
        }
        return true;
    };
    eachDescendant(view, descendantsCallback);
    return retVal;
}
/**
 * Gets a child view by domId.
 * @param view - The parent (container) view of the view to look for.
 * @param domId - The id of the view to look for.
 * Returns an instance of a view (if found), otherwise undefined.
 */
export function getViewByDomId(view, domId) {
    if (!view) {
        return undefined;
    }
    if (view._domId === domId) {
        return view;
    }
    let retVal;
    const descendantsCallback = function (child) {
        if (child._domId === domId) {
            retVal = child;
            // break the iteration by returning false
            return false;
        }
        return true;
    };
    eachDescendant(view, descendantsCallback);
    return retVal;
}
// TODO: allow all selector types (just using attributes now)
/**
 * Gets a child view by selector.
 * @param view - The parent (container) view of the view to look for.
 * @param selector - The selector of the view to look for.
 * Returns an instance of a view (if found), otherwise undefined.
 */
export function querySelectorAll(view, selector) {
    if (!view) {
        return [];
    }
    const retVal = [];
    if (view[selector]) {
        retVal.push(view);
    }
    const descendantsCallback = function (child) {
        if (child[selector]) {
            retVal.push(child);
        }
        return true;
    };
    eachDescendant(view, descendantsCallback);
    return retVal;
}
/**
 * Iterates through all child views (via visual tree) and executes a function.
 * @param view - Starting view (parent container).
 * @param callback - A function to execute on every child. If function returns false it breaks the iteration.
 */
export function eachDescendant(view, callback) {
    if (!callback || !view) {
        return;
    }
    let continueIteration;
    const localCallback = function (child) {
        continueIteration = callback(child);
        if (continueIteration) {
            child.eachChild(localCallback);
        }
        return continueIteration;
    };
    view.eachChild(localCallback);
}
let viewIdCounter = 1;
// const contextMap = new WeakMap<Object, Map<string, WeakRef<Object>[]>>();
// function getNativeView(context: Object, typeName: string): Object {
//     let typeMap = contextMap.get(context);
//     if (!typeMap) {
//         typeMap = new Map<string, WeakRef<Object>[]>();
//         contextMap.set(context, typeMap);
//         return undefined;
//     }
//     const array = typeMap.get(typeName);
//     if (array) {
//         let nativeView;
//         while (array.length > 0) {
//             const weakRef = array.pop();
//             nativeView = weakRef.get();
//             if (nativeView) {
//                 return nativeView;
//             }
//         }
//     }
//     return undefined;
// }
// function putNativeView(context: Object, view: ViewBase): void {
//     const typeMap = contextMap.get(context);
//     const typeName = view.typeName;
//     let list = typeMap.get(typeName);
//     if (!list) {
//         list = [];
//         typeMap.set(typeName, list);
//     }
//     list.push(new WeakRef(view.nativeViewProtected));
// }
var Flags;
(function (Flags) {
    Flags["superOnLoadedCalled"] = "Loaded";
    Flags["superOnUnloadedCalled"] = "Unloaded";
})(Flags || (Flags = {}));
var SuspendType;
(function (SuspendType) {
    SuspendType[SuspendType["Incremental"] = 0] = "Incremental";
    SuspendType[SuspendType["Loaded"] = 1048576] = "Loaded";
    SuspendType[SuspendType["NativeView"] = 2097152] = "NativeView";
    SuspendType[SuspendType["UISetup"] = 4194304] = "UISetup";
    SuspendType[SuspendType["IncrementalCountMask"] = -7340033] = "IncrementalCountMask";
})(SuspendType || (SuspendType = {}));
(function (SuspendType) {
    function toString(type) {
        return (type ? 'suspended' : 'resumed') + '(' + 'Incremental: ' + (type & SuspendType.IncrementalCountMask) + ', ' + 'Loaded: ' + !(type & SuspendType.Loaded) + ', ' + 'NativeView: ' + !(type & SuspendType.NativeView) + ', ' + 'UISetup: ' + !(type & SuspendType.UISetup) + ')';
    }
    SuspendType.toString = toString;
})(SuspendType || (SuspendType = {}));
const DEFAULT_VIEW_PADDINGS = new Map();
/**
 *
 * @nsView ViewBase
 */
export class ViewBase extends Observable {
    /**
     * Gets the CSS fully qualified type name used for selector matching.
     */
    get cssType() {
        return undefined;
    }
    set cssType(value) { }
    constructor() {
        super();
        this._onLoadedCalled = false;
        this._onUnloadedCalled = false;
        /**
         * if _setupAsRootView is called it means it is not supposed to be
         * added to a parent. However parent can be set before for the purpose
         * of CSS variables/classes. That variable ensures that _addViewToNativeVisualTree
         * is not called in _setupAsRootView
         */
        this._isRootView = false;
        this._effectivePaddingTop = null;
        this._effectivePaddingRight = null;
        this._effectivePaddingBottom = null;
        this._effectivePaddingLeft = null;
        this._defaultPaddingTop = 0;
        this._defaultPaddingRight = 0;
        this._defaultPaddingBottom = 0;
        this._defaultPaddingLeft = 0;
        /**
         * Default visual state, defaults to 'normal'
         *
         * @nsProperty
         */
        this.defaultVisualState = 'normal';
        /* "ui/styling/style-scope" */ this._cssState = new CssState(new WeakRef(this));
        this.pseudoClassAliases = {
            highlighted: ['active', 'pressed'],
        };
        this._domId = viewIdCounter++;
        this._style = new Style(new WeakRef(this));
        this.cssClasses = new Set();
        this.cssPseudoClasses = new Set();
        this.cssPseudoClasses.add(this.defaultVisualState);
        this.notify({ eventName: ViewBase.createdEvent, type: this.constructor.name, object: this });
    }
    // Used in Angular. TODO: remove from here
    /**
     * Gets the template parent or the native parent. Sets the template parent.
     */
    get parentNode() {
        return this._templateParent || this.parent;
    }
    set parentNode(node) {
        this._templateParent = node;
    }
    get nativeView() {
        // this._disableNativeViewRecycling = true;
        return this.nativeViewProtected;
    }
    set nativeView(value) {
        this.setNativeView(value);
    }
    // TODO: Use Type.prototype.typeName instead.
    /**
     * Gets the name of the constructor function for this instance. E.g. for a Button class this will return "Button".
     */
    get typeName() {
        return getClass(this);
    }
    /**
     * Gets the style object associated to this view.
     */
    get style() {
        return this._style;
    }
    /**
     *
     * @nsProperty
     */
    set style(inlineStyle /* | string */) {
        if (typeof inlineStyle === 'string') {
            this.setInlineStyle(inlineStyle);
        }
        else {
            throw new Error('View.style property is read-only.');
        }
    }
    get android() {
        // this._disableNativeViewRecycling = true;
        return this._androidView;
    }
    get ios() {
        // this._disableNativeViewRecycling = true;
        return this._iosView;
    }
    get isLoaded() {
        return this._isLoaded;
    }
    get ['class']() {
        return this.className;
    }
    set ['class'](v) {
        this.className = v;
    }
    get effectivePaddingTop() {
        return this._effectivePaddingTop != null ? this._effectivePaddingTop : this._defaultPaddingTop;
    }
    set effectivePaddingTop(v) {
        this._effectivePaddingTop = v;
    }
    get effectivePaddingRight() {
        return this._effectivePaddingRight != null ? this._effectivePaddingRight : this._defaultPaddingRight;
    }
    set effectivePaddingRight(v) {
        this._effectivePaddingRight = v;
    }
    get effectivePaddingBottom() {
        return this._effectivePaddingBottom != null ? this._effectivePaddingBottom : this._defaultPaddingBottom;
    }
    set effectivePaddingBottom(v) {
        this._effectivePaddingBottom = v;
    }
    get effectivePaddingLeft() {
        return this._effectivePaddingLeft != null ? this._effectivePaddingLeft : this._defaultPaddingLeft;
    }
    set effectivePaddingLeft(v) {
        this._effectivePaddingLeft = v;
    }
    getEffectivePaddingShorthand() {
        return `${this.effectivePaddingTop} ${this.effectivePaddingRight} ${this.effectivePaddingBottom} ${this.effectivePaddingLeft}`;
    }
    /**
     * Returns the child view with the specified id.
     */
    getViewById(id) {
        return getViewById(this, id);
    }
    /**
     * Returns the child view with the specified domId.
     */
    getViewByDomId(domId) {
        return getViewByDomId(this, domId);
    }
    /**
     * Gets owner page. This is a read-only property.
     */
    get page() {
        if (this.parent) {
            return this.parent.page;
        }
        return null;
    }
    /**
     * @unstable
     * Ensures a dom-node for this view.
     */
    ensureDomNode() {
        if (!this.domNode) {
            this.domNode = new DOMNode(this);
        }
    }
    // Overridden so we don't raise `propertyChange`
    // The property will raise its own event.
    set(name, value) {
        this[name] = WrappedValue.unwrap(value);
    }
    onLoaded() {
        this.setFlag(Flags.superOnLoadedCalled, true);
        if (this._isLoaded) {
            return;
        }
        this._isLoaded = true;
        this._cssState.onLoaded();
        this._resumeNativeUpdates(SuspendType.Loaded);
        this.eachChild((child) => {
            this.loadView(child);
            return true;
        });
        this._emit('loaded');
    }
    onUnloaded() {
        this.setFlag(Flags.superOnUnloadedCalled, true);
        if (!this._isLoaded) {
            return;
        }
        this._suspendNativeUpdates(SuspendType.Loaded);
        this.eachChild((child) => {
            this.unloadView(child);
            return true;
        });
        this._isLoaded = false;
        this._cssState.onUnloaded();
        this._emit('unloaded');
    }
    _layoutParent() {
        if (this.parent) {
            this.parent._layoutParent();
        }
    }
    _setDefaultPaddings(insets) {
        // Overridden
    }
    _suspendNativeUpdates(type) {
        if (type) {
            this._suspendNativeUpdatesCount = this._suspendNativeUpdatesCount | type;
        }
        else {
            this._suspendNativeUpdatesCount++;
        }
    }
    _resumeNativeUpdates(type) {
        if (type) {
            this._suspendNativeUpdatesCount = this._suspendNativeUpdatesCount & ~type;
        }
        else {
            if ((this._suspendNativeUpdatesCount & SuspendType.IncrementalCountMask) === 0) {
                throw new Error(`Invalid call to ${this}._resumeNativeUpdates`);
            }
            this._suspendNativeUpdatesCount--;
        }
        if (!this._suspendNativeUpdatesCount) {
            this.onResumeNativeUpdates();
        }
    }
    /**
     * Allow multiple updates to be performed on the instance at once.
     */
    _batchUpdate(callback) {
        try {
            this._suspendNativeUpdates(SuspendType.Incremental);
            return callback();
        }
        finally {
            this._resumeNativeUpdates(SuspendType.Incremental);
        }
    }
    setFlag(flag, value) {
        switch (flag) {
            case Flags.superOnLoadedCalled:
                this._onLoadedCalled = value;
                break;
            case Flags.superOnUnloadedCalled:
                this._onUnloadedCalled = value;
                break;
        }
    }
    isFlagSet(flag) {
        switch (flag) {
            case Flags.superOnLoadedCalled:
                return this._onLoadedCalled;
            case Flags.superOnUnloadedCalled:
                return this._onUnloadedCalled;
        }
    }
    callFunctionWithSuper(flag, func) {
        this.setFlag(flag, false);
        func();
        if (!this.isFlagSet(flag)) {
            throw new Error(`super.${flag} not called in ${this}`);
        }
    }
    callLoaded() {
        this.callFunctionWithSuper(Flags.superOnLoadedCalled, () => this.onLoaded());
    }
    callUnloaded() {
        this.callFunctionWithSuper(Flags.superOnUnloadedCalled, () => this.onUnloaded());
    }
    notifyPseudoClassChanged(pseudoClass) {
        this.notify({ eventName: ':' + pseudoClass, object: this });
    }
    addSinglePseudoClass(name) {
        if (!this.cssPseudoClasses.has(name)) {
            this.cssPseudoClasses.add(name);
            this.notifyPseudoClassChanged(name);
        }
    }
    deleteSinglePseudoClass(name) {
        if (this.cssPseudoClasses.has(name)) {
            this.cssPseudoClasses.delete(name);
            this.notifyPseudoClassChanged(name);
        }
    }
    /**
     * @protected
     * @unstable
     * A widget can call this method to add a matching css pseudo class.
     */
    addPseudoClass(name) {
        this.addSinglePseudoClass(name);
        const aliases = this.pseudoClassAliases[name];
        if (aliases) {
            for (let i = 0, length = aliases.length; i < length; i++) {
                this.addSinglePseudoClass(aliases[i]);
            }
        }
    }
    /**
     * @protected
     * @unstable
     * A widget can call this method to discard matching css pseudo class.
     */
    deletePseudoClass(name) {
        this.deleteSinglePseudoClass(name);
        const aliases = this.pseudoClassAliases[name];
        if (aliases) {
            for (let i = 0, length = aliases.length; i < length; i++) {
                this.deleteSinglePseudoClass(aliases[i]);
            }
        }
    }
    bindingContextChanged(data) {
        this.bindings.get('bindingContext').bind(data.value);
    }
    bind(options, source = defaultBindingSource) {
        const targetProperty = options.targetProperty;
        this.unbind(targetProperty);
        if (!this.bindings) {
            this.bindings = new Map();
        }
        const binding = new Binding(this, options);
        this.bindings.set(targetProperty, binding);
        let bindingSource = source;
        if (bindingSource === defaultBindingSource) {
            bindingSource = this.bindingContext;
            binding.sourceIsBindingContext = true;
            if (targetProperty === 'bindingContext') {
                this.bindingContextBoundToParentBindingContextChanged = true;
                const parent = this.parent;
                if (parent) {
                    parent.on('bindingContextChange', this.bindingContextChanged, this);
                }
                else {
                    this.shouldAddHandlerToParentBindingContextChanged = true;
                }
            }
        }
        binding.bind(bindingSource);
    }
    unbind(property) {
        const bindings = this.bindings;
        if (!bindings) {
            return;
        }
        const binding = bindings.get(property);
        if (binding) {
            binding.unbind();
            bindings.delete(property);
            if (binding.sourceIsBindingContext) {
                if (property === 'bindingContext') {
                    this.shouldAddHandlerToParentBindingContextChanged = false;
                    this.bindingContextBoundToParentBindingContextChanged = false;
                    const parent = this.parent;
                    if (parent) {
                        parent.off('bindingContextChange', this.bindingContextChanged, this);
                    }
                }
            }
        }
    }
    performLayout(currentRun = 0) {
        // if there's an animation in progress we need to delay the layout
        // we've added a guard of 5000 milliseconds execution
        // to make sure that the layout will happen even if the animation haven't finished in 5 seconds
        if (this._shouldDelayLayout() && currentRun < 100) {
            setTimeout(() => this.performLayout(currentRun), currentRun);
            currentRun++;
        }
        else {
            this.parent.requestLayout();
        }
    }
    /**
     * Invalidates the layout of the view and triggers a new layout pass.
     */
    requestLayout() {
        // Default implementation for non View instances (like TabViewItem).
        const parent = this.parent;
        if (parent) {
            this.performLayout();
        }
    }
    /**
     * Iterates over children of type ViewBase.
     * @param callback Called for each child of type ViewBase. Iteration stops if this method returns falsy value.
     */
    eachChild(callback) {
        //
    }
    _inheritStyles(view) {
        propagateInheritableProperties(this, view);
        view._inheritStyleScope(this._styleScope);
        propagateInheritableCssProperties(this.style, view.style);
    }
    _addView(view, atIndex) {
        if (Trace.isEnabled()) {
            Trace.write(`${this}._addView(${view}, ${atIndex})`, Trace.categories.ViewHierarchy);
        }
        if (!view) {
            throw new Error('Expecting a valid View instance.');
        }
        if (!(view instanceof ViewBase)) {
            throw new Error(view + ' is not a valid View instance.');
        }
        if (view.parent) {
            throw new Error('View already has a parent. View: ' + view + ' Parent: ' + view.parent);
        }
        view.parent = this;
        this._addViewCore(view, atIndex);
        view._parentChanged(null);
        if (this.domNode) {
            this.domNode.onChildAdded(view);
        }
    }
    /**
     * Method is intended to be overridden by inheritors and used as "protected"
     */
    _addViewCore(view, atIndex) {
        this._inheritStyles(view);
        if (this._context) {
            view._setupUI(this._context, atIndex);
        }
        if (this._isLoaded) {
            this.loadView(view);
        }
    }
    /**
     * Load view.
     * @param view to load.
     */
    loadView(view) {
        if (view && !view.isLoaded) {
            view.callLoaded();
        }
    }
    /**
     * When returning true the callLoaded method will be run in setTimeout
     * Method is intended to be overridden by inheritors and used as "protected"
     */
    _shouldDelayLayout() {
        return false;
    }
    /**
     * Unload view.
     * @param view to unload.
     */
    unloadView(view) {
        if (view && view.isLoaded) {
            view.callUnloaded();
        }
    }
    /**
     * Core logic for removing a child view from this instance. Used by the framework to handle lifecycle events more centralized. Do not use outside the UI Stack implementation.
     */
    _removeView(view) {
        if (Trace.isEnabled()) {
            Trace.write(`${this}._removeView(${view})`, Trace.categories.ViewHierarchy);
        }
        if (view.parent !== this) {
            throw new Error('View not added to this instance. View: ' + view + ' CurrentParent: ' + view.parent + ' ExpectedParent: ' + this);
        }
        if (this.domNode) {
            this.domNode.onChildRemoved(view);
        }
        this._removeViewCore(view);
        view.parent = undefined;
        view._parentChanged(this);
    }
    /**
     * Method is intended to be overridden by inheritors and used as "protected"
     */
    _removeViewCore(view) {
        this.unloadView(view);
        if (view._context) {
            view._tearDownUI();
        }
    }
    /**
     * Creates a native view.
     * Returns either android.view.View or UIView.
     */
    createNativeView() {
        return undefined;
    }
    /**
     * Clean up references to the native view.
     */
    disposeNativeView() {
        // Unset these values so that view checks for resize the next time it's added back to view tree
        this._oldLeft = 0;
        this._oldTop = 0;
        this._oldRight = 0;
        this._oldBottom = 0;
        this.notify({
            eventName: ViewBase.disposeNativeViewEvent,
            object: this,
        });
    }
    /**
     * Initializes properties/listeners of the native view.
     */
    initNativeView() {
        //
    }
    /**
     * Resets properties/listeners set to the native view.
     */
    resetNativeView() {
        //
    }
    resetNativeViewInternal() {
        // const nativeView = this.nativeViewProtected;
        // if (nativeView && __ANDROID__) {
        //     const recycle = this.recycleNativeView;
        //     if (recycle === "always" || (recycle === "auto" && !this._disableNativeViewRecycling)) {
        //         resetNativeView(this);
        //         if (this._isPaddingRelative) {
        //             nativeView.setPaddingRelative(this._defaultPaddingLeft, this._defaultPaddingTop, this._defaultPaddingRight, this._defaultPaddingBottom);
        //         } else {
        //             nativeView.setPadding(this._defaultPaddingLeft, this._defaultPaddingTop, this._defaultPaddingRight, this._defaultPaddingBottom);
        //         }
        //         this.resetNativeView();
        //     }
        // }
        // if (this._cssState) {
        //     this._cancelAllAnimations();
        // }
    }
    _setupAsRootView(context) {
        this._isRootView = true;
        this._setupUI(context);
        this._isRootView = false;
    }
    /**
     * Setups the UI for ViewBase and all its children recursively.
     * This method should *not* be overridden by derived views.
     */
    _setupUI(context /* android.content.Context */, atIndex, parentIsLoaded) {
        if (this._context === context) {
            // this check is unnecessary as this function should never be called when this._context === context as it means the view was somehow detached,
            // which is only possible by setting reusable = true. Adding it either way for feature flag safety
            if (this.reusable) {
                if (!this._isRootView && this.parent && !this._isAddedToNativeVisualTree) {
                    const nativeIndex = this.parent._childIndexToNativeChildIndex(atIndex);
                    this._isAddedToNativeVisualTree = this.parent._addViewToNativeVisualTree(this, nativeIndex);
                }
            }
            return;
        }
        else if (this._context) {
            this._tearDownUI(true);
        }
        this._context = context;
        // This will account for nativeView that is created in createNativeView, recycled
        // or for backward compatibility - set before _setupUI in iOS constructor.
        let nativeView = this.nativeViewProtected;
        // if (__ANDROID__) {
        //     const recycle = this.recycleNativeView;
        //     if (recycle === "always" || (recycle === "auto" && !this._disableNativeViewRecycling)) {
        //         nativeView = <android.view.View>getNativeView(context, this.typeName);
        //     }
        // }
        if (!nativeView) {
            nativeView = this.createNativeView();
        }
        if (__ANDROID__) {
            // this check is also unecessary as this code should never be reached with _androidView != null unless reusable = true
            // also adding this check for feature flag safety
            if (this._androidView !== nativeView || !this.reusable) {
                this._androidView = nativeView;
                if (nativeView) {
                    const className = this.constructor.name;
                    if (this._isPaddingRelative === undefined) {
                        this._isPaddingRelative = nativeView.isPaddingRelative();
                    }
                    let result /* android.graphics.Rect */ = DEFAULT_VIEW_PADDINGS.get(className) || nativeView.defaultPaddings;
                    if (result === undefined) {
                        DEFAULT_VIEW_PADDINGS.set(className, org.nativescript.widgets.ViewHelper.getPadding(nativeView));
                        nativeView.defaultPaddings = DEFAULT_VIEW_PADDINGS.get(className);
                        result = DEFAULT_VIEW_PADDINGS.get(className);
                    }
                    if (!nativeView.defaultPaddings) {
                        nativeView.defaultPaddings = DEFAULT_VIEW_PADDINGS.get(className);
                    }
                    this._setDefaultPaddings(result);
                }
            }
        }
        else {
            this._iosView = nativeView;
        }
        this.setNativeView(nativeView);
        if (!this._isRootView && this.parent) {
            const nativeIndex = this.parent._childIndexToNativeChildIndex(atIndex);
            this._isAddedToNativeVisualTree = this.parent._addViewToNativeVisualTree(this, nativeIndex);
        }
        this._resumeNativeUpdates(SuspendType.UISetup);
        this.eachChild((child) => {
            child._setupUI(context);
            return true;
        });
    }
    /**
     * Set the nativeView field performing extra checks and updates to the native properties on the new view.
     * Use in cases where the createNativeView is not suitable.
     * As an example use in item controls where the native parent view will create the native views for child items.
     */
    setNativeView(value) {
        if (this.__nativeView === value) {
            return;
        }
        if (this.__nativeView) {
            this._suspendNativeUpdates(SuspendType.NativeView);
            // We may do a `this.resetNativeView()` here?
        }
        this.__nativeView = this.nativeViewProtected = value;
        if (this.__nativeView) {
            this._suspendedUpdates = undefined;
            this.initNativeView();
            this._resumeNativeUpdates(SuspendType.NativeView);
        }
    }
    /**
     * Tears down the UI of a reusable node by making it no longer reusable.
     * @see _tearDownUI
     * @param forceDestroyChildren Force destroy the children (even if they are reusable)
     */
    destroyNode(forceDestroyChildren) {
        this.reusable = false;
        this.unloadView(this);
        this._tearDownUI(forceDestroyChildren);
    }
    /**
     * Tears down the UI for ViewBase and all its children recursively.
     * This method should *not* be overridden by derived views.
     */
    _tearDownUI(force) {
        // No context means we are already teared down.
        if (!this._context) {
            return;
        }
        const preserveNativeView = this.reusable && !force;
        this.resetNativeViewInternal();
        if (!preserveNativeView) {
            this.eachChild((child) => {
                // if we decided to tear down the current view, we should also tear down the children, even if they are reusable
                // the developer is responsible to detach them if they need to reuse them somewhere else
                child._tearDownUI(true);
                return true;
            });
        }
        if (this.parent) {
            this.parent._removeViewFromNativeVisualTree(this);
        }
        // const nativeView = this.nativeViewProtected;
        // if (nativeView && __ANDROID__) {
        //     const recycle = this.recycleNativeView;
        //     let shouldRecycle = false;
        //     if (recycle === "always") {
        //         shouldRecycle = true;
        //     } else if (recycle === "auto" && !this._disableNativeViewRecycling) {
        //         const propertiesSet = Object.getOwnPropertySymbols(this).length + Object.getOwnPropertySymbols(this.style).length / 2;
        //         shouldRecycle = propertiesSet <= this.recyclePropertyCounter;
        //     }
        //     // const nativeParent = __ANDROID__ ? (<android.view.View>nativeView).getParent() : (<UIView>nativeView).superview;
        //     const nativeParent = (<android.view.View>nativeView).getParent();
        //     const animation = (<android.view.View>nativeView).getAnimation();
        //     if (shouldRecycle && !nativeParent && !animation) {
        //         putNativeView(this._context, this);
        //     }
        // }
        if (!preserveNativeView) {
            this.disposeNativeView();
            this._suspendNativeUpdates(SuspendType.UISetup);
            this.setNativeView(null);
            this._androidView = null;
            this._iosView = null;
            this._context = null;
        }
        if (this.domNode) {
            this.domNode.dispose();
            this.domNode = undefined;
        }
    }
    _childIndexToNativeChildIndex(index) {
        return index;
    }
    /**
     * Performs the core logic of adding a child view to the native visual tree. Returns true if the view's native representation has been successfully added, false otherwise.
     * Method is intended to be overridden by inheritors and used as "protected".
     */
    _addViewToNativeVisualTree(view, atIndex) {
        if (view._isAddedToNativeVisualTree) {
            throw new Error('Child already added to the native visual tree.');
        }
        return true;
    }
    /**
     * Method is intended to be overridden by inheritors and used as "protected"
     */
    _removeViewFromNativeVisualTree(view) {
        view._isAddedToNativeVisualTree = false;
    }
    /**
     * @deprecated
     */
    get visualState() {
        return this._visualState;
    }
    _addVisualState(state) {
        this.deletePseudoClass(this.defaultVisualState);
        this.addPseudoClass(state);
    }
    _removeVisualState(state) {
        this.deletePseudoClass(state);
        if (!this.cssPseudoClasses.size) {
            this.addPseudoClass(this.defaultVisualState);
        }
    }
    /**
     * @deprecated Use View._addVisualState() and View._removeVisualState() instead.
     */
    _goToVisualState(state) {
        console.log('_goToVisualState() is deprecated. Use View._addVisualState() and View._removeVisualState() instead.');
        if (Trace.isEnabled()) {
            Trace.write(this + ' going to state: ' + state, Trace.categories.Style);
        }
        if (state === this._visualState) {
            return;
        }
        this.deletePseudoClass(this._visualState);
        this._visualState = state;
        this.addPseudoClass(state);
    }
    /**
     * @deprecated
     *
     * This used to be the way to set attribute values in early {N} versions.
     * Now attributes are expected to be set as plain properties on the view instances.
     */
    _applyXmlAttribute(attribute, value) {
        console.log('ViewBase._applyXmlAttribute(...) is deprecated; set attributes as plain properties instead');
        if (attribute === 'style' || attribute === 'rows' || attribute === 'columns' || attribute === 'fontAttributes') {
            this[attribute] = value;
            return true;
        }
        return false;
    }
    setInlineStyle(style) {
        if (typeof style !== 'string') {
            throw new Error('Parameter should be valid CSS string!');
        }
        applyInlineStyle(this, style, undefined);
    }
    _parentChanged(oldParent) {
        const newParent = this.parent;
        //Overridden
        if (oldParent) {
            clearInheritedProperties(this);
            if (this.bindingContextBoundToParentBindingContextChanged) {
                oldParent.off('bindingContextChange', this.bindingContextChanged, this);
            }
        }
        else if (this.shouldAddHandlerToParentBindingContextChanged) {
            newParent.on('bindingContextChange', this.bindingContextChanged, this);
            this.bindings.get('bindingContext').bind(newParent.bindingContext);
        }
    }
    onResumeNativeUpdates() {
        // Apply native setters...
        initNativeView(this, undefined, undefined);
    }
    toString() {
        let str = this.typeName;
        if (this.id) {
            str += `<${this.id}>`;
        }
        else {
            str += `(${this._domId})`;
        }
        const source = Source.get(this);
        if (source) {
            str += `@${source};`;
        }
        return str;
    }
    /**
     * @private
     * Notifies each child's css state for change, recursively.
     * Either the style scope, className or id properties were changed.
     */
    _onCssStateChange() {
        this._cssState.onChange();
        eachDescendant(this, (child) => {
            child._cssState.onChange();
            return true;
        });
    }
    _inheritStyleScope(styleScope) {
        // If we are styleScope don't inherit parent stylescope.
        // TODO: Consider adding parent scope and merge selectors.
        if (this._isStyleScopeHost) {
            return;
        }
        if (this._styleScope !== styleScope) {
            this._styleScope = styleScope;
            this._onCssStateChange();
            this.eachChild((child) => {
                child._inheritStyleScope(styleScope);
                return true;
            });
        }
    }
    showModal(moduleOrView, modalOptions) {
        const parent = this.parent;
        return parent && parent.showModal(moduleOrView, modalOptions);
    }
    /**
     * Closes the current modal view that this page is showing.
     * @param context - Any context you want to pass back to the host when closing the modal view.
     */
    closeModal(...args) {
        const parent = this.parent;
        if (parent) {
            parent.closeModal(...args);
        }
    }
    /**
     * Method is intended to be overridden by inheritors and used as "protected"
     */
    _dialogClosed() {
        this.eachChild((child) => {
            child._dialogClosed();
            return true;
        });
    }
    /**
     * Method is intended to be overridden by inheritors and used as "protected"
     */
    _onRootViewReset() {
        this.eachChild((child) => {
            child._onRootViewReset();
            return true;
        });
    }
}
/**
 * String value used when hooking to loaded event.
 *
 * @nsEvent loaded
 */
ViewBase.loadedEvent = 'loaded';
/**
 * String value used when hooking to unloaded event.
 *
 * @nsEvent unloaded
 */
ViewBase.unloadedEvent = 'unloaded';
/**
 * String value used when hooking to creation event
 *
 * @nsEvent created
 */
ViewBase.createdEvent = 'created';
/**
 * String value used when hooking to disposeNativeView event
 *
 * @nsEvent disposeNativeView
 */
ViewBase.disposeNativeViewEvent = 'disposeNativeView';
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "onLoaded", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "onUnloaded", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "addPseudoClass", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "deletePseudoClass", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "requestLayout", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [ViewBase, Number]),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "_addView", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Number, Boolean]),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "_setupUI", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Boolean]),
    __metadata("design:returntype", void 0)
], ViewBase.prototype, "_tearDownUI", null);
ViewBase.prototype.isCollapsed = false;
ViewBase.prototype._oldLeft = 0;
ViewBase.prototype._oldTop = 0;
ViewBase.prototype._oldRight = 0;
ViewBase.prototype._oldBottom = 0;
ViewBase.prototype.effectiveMinWidth = 0;
ViewBase.prototype.effectiveMinHeight = 0;
// Infinity means unconstrained, so Math.min(measured, effectiveMaxWidth) is a no-op when unset.
ViewBase.prototype.effectiveMaxWidth = Number.POSITIVE_INFINITY;
ViewBase.prototype.effectiveMaxHeight = Number.POSITIVE_INFINITY;
ViewBase.prototype.effectiveWidth = 0;
ViewBase.prototype.effectiveHeight = 0;
ViewBase.prototype.effectiveMarginTop = 0;
ViewBase.prototype.effectiveMarginRight = 0;
ViewBase.prototype.effectiveMarginBottom = 0;
ViewBase.prototype.effectiveMarginLeft = 0;
ViewBase.prototype.effectiveBorderTopWidth = 0;
ViewBase.prototype.effectiveBorderRightWidth = 0;
ViewBase.prototype.effectiveBorderBottomWidth = 0;
ViewBase.prototype.effectiveBorderLeftWidth = 0;
ViewBase.prototype.effectiveRowGap = 0;
ViewBase.prototype.effectiveColumnGap = 0;
ViewBase.prototype._isViewBase = true;
ViewBase.prototype.recycleNativeView = 'never';
ViewBase.prototype.reusable = false;
ViewBase.prototype._suspendNativeUpdatesCount = SuspendType.Loaded | SuspendType.NativeView | SuspendType.UISetup;
export const bindingContextProperty = new InheritedProperty({
    name: 'bindingContext',
});
bindingContextProperty.register(ViewBase);
export const hiddenProperty = new Property({
    name: 'hidden',
    defaultValue: false,
    affectsLayout: __APPLE__,
    valueConverter: booleanConverter,
    valueChanged: (target, oldValue, newValue) => {
        if (target) {
            target.isCollapsed = !!newValue;
        }
    },
});
hiddenProperty.register(ViewBase);
export const classNameProperty = new Property({
    name: 'className',
    valueChanged(view, oldValue, newValue) {
        const cssClasses = view.cssClasses;
        const rootViewsCssClasses = CSSUtils.getSystemCssClasses();
        const shouldAddModalRootViewCssClasses = cssClasses.has(CSSUtils.MODAL_ROOT_VIEW_CSS_CLASS);
        const shouldAddRootViewCssClasses = cssClasses.has(CSSUtils.ROOT_VIEW_CSS_CLASS);
        // Window-scoped classes are absent from the system class list, so they have to be
        // carried over by hand or a root view would lose them on every className change.
        const windowScopedCssClasses = shouldAddModalRootViewCssClasses || shouldAddRootViewCssClasses ? CSSUtils.WINDOW_SCOPED_CSS_CLASSES.filter((c) => cssClasses.has(c)) : [];
        cssClasses.clear();
        if (shouldAddModalRootViewCssClasses) {
            cssClasses.add(CSSUtils.MODAL_ROOT_VIEW_CSS_CLASS);
        }
        else if (shouldAddRootViewCssClasses) {
            cssClasses.add(CSSUtils.ROOT_VIEW_CSS_CLASS);
        }
        for (let i = 0, length = rootViewsCssClasses.length; i < length; i++) {
            cssClasses.add(rootViewsCssClasses[i]);
        }
        for (let i = 0, length = windowScopedCssClasses.length; i < length; i++) {
            cssClasses.add(windowScopedCssClasses[i]);
        }
        if (typeof newValue === 'string' && newValue !== '') {
            const classes = newValue.split(' ');
            for (let i = 0, length = classes.length; i < length; i++) {
                cssClasses.add(classes[i]);
            }
        }
        view._onCssStateChange();
    },
});
classNameProperty.register(ViewBase);
export const idProperty = new Property({
    name: 'id',
    valueChanged: (view, oldValue, newValue) => view._onCssStateChange(),
});
idProperty.register(ViewBase);
export const defaultVisualStateProperty = new Property({
    name: 'defaultVisualState',
    defaultValue: 'normal',
    valueChanged(target, oldValue, newValue) {
        const value = newValue || 'normal';
        // Append new default if old one is currently applied
        if (target.cssPseudoClasses && target.cssPseudoClasses.has(oldValue)) {
            target.deletePseudoClass(oldValue);
            target.addPseudoClass(newValue);
        }
    },
});
defaultVisualStateProperty.register(ViewBase);
//# sourceMappingURL=index.js.map