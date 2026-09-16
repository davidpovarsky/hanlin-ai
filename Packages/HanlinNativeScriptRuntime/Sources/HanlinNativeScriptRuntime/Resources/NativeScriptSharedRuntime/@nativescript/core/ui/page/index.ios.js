const __VISIONOS__ = globalThis.__VISIONOS__ !== undefined ? globalThis.__VISIONOS__ : false;
import { isAccessibilityServiceEnabled } from '../../application';
import { NavigationType } from '../frame/frame-interfaces';
import { View, IOSHelper } from '../core/view';
import { PageBase, actionBarHiddenProperty, enableSwipeBackNavigationProperty } from './page-common';
import { profile } from '../../profiling';
import { layout } from '../../utils/layout-helper';
import { SDK_VERSION } from '../../utils/constants';
import { getLastFocusedViewOnPage } from '../../accessibility/accessibility-common';
import { SharedTransition } from '../transition/shared-transition';
export * from './page-common';
const ENTRY = '_entry';
const DELEGATE = '_delegate';
const TRANSITION = '_transition';
const NON_ANIMATED_TRANSITION = 'non-animated';
var UIViewControllerImpl = (function (_super) {
    __extends(UIViewControllerImpl, _super);
    function UIViewControllerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    Object.defineProperty(UIViewControllerImpl.prototype, "isRunningLayout", {
        get: function () {
            return this._isRunningLayout !== 0;
        },
        enumerable: true,
        configurable: true
    });
    UIViewControllerImpl.prototype.startRunningLayout = function () {
        this._isRunningLayout++;
    };
    UIViewControllerImpl.prototype.finishRunningLayout = function () {
        this._isRunningLayout--;
        this.didFirstLayout = true;
    };
    UIViewControllerImpl.prototype.runLayout = function (cb) {
        try {
            this.startRunningLayout();
            cb();
        }
        finally {
            this.finishRunningLayout();
        }
    };
    UIViewControllerImpl.initWithOwner = function (owner) {
        var controller = UIViewControllerImpl.new();
        controller._owner = owner;
        controller._isRunningLayout = 0;
        controller.didFirstLayout = false;
        return controller;
    };
    UIViewControllerImpl.prototype.viewDidLoad = function () {
        _super.prototype.viewDidLoad.call(this);
        this.extendedLayoutIncludesOpaqueBars = true;
    };
    UIViewControllerImpl.prototype.viewWillAppear = function (animated) {
        var _a;
        _super.prototype.viewWillAppear.call(this, animated);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return;
        }
        var frame = this.navigationController ? this.navigationController.owner : null;
        if (frame) {
            var entry = this[ENTRY];
            var currentPage = frame.currentPage;
            if (!owner._presentedViewController && entry && currentPage !== owner && !frame._executingContext) {
                var isBack = frame.backStack.includes(entry);
                frame._executingContext = {
                    entry: entry,
                    isBackNavigation: isBack,
                    navigationType: isBack ? NavigationType.back : NavigationType.forward,
                };
                frame._onNavigatingTo(entry, isBack);
            }
            frame._resolvedPage = owner;
            if (owner.parent === frame) {
                frame._inheritStyles(owner);
            }
            else {
                if (!owner.parent) {
                    if (!frame._styleScope) {
                        owner._updateStyleScope();
                    }
                    frame._addView(owner);
                }
                else {
                    throw new Error("Page is already shown on another frame.");
                }
            }
            frame._updateActionBar(owner);
        }
        IOSHelper.updateAutoAdjustScrollInsets(this, owner);
        if (!owner.isLoaded) {
            owner.callLoaded();
            owner.updateStatusBar();
        }
        else {
            owner.updateWithWillAppear(animated);
        }
    };
    UIViewControllerImpl.prototype.viewDidAppear = function (animated) {
        var _a, _b, _c, _d;
        _super.prototype.viewDidAppear.call(this, animated);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return;
        }
        var navigationController = this.navigationController;
        var frame = navigationController ? navigationController.owner : null;
        if (frame) {
            var newEntry = this[ENTRY];
            if (frame._executingContext && frame._executingContext.entry !== newEntry) {
                frame._executingContext = null;
                return;
            }
            if (!owner._presentedViewController) {
                var navigationType = (_c = (_b = frame._executingContext) === null || _b === void 0 ? void 0 : _b.navigationType) !== null && _c !== void 0 ? _c : NavigationType.back;
                var isReplace = navigationType === NavigationType.replace;
                frame.setCurrent(newEntry, navigationType);
                if (isReplace) {
                    var controller = newEntry.resolvedPage.ios;
                    if (controller) {
                        var animated_1 = frame._getIsAnimatedNavigation(newEntry.entry);
                        if (animated_1) {
                            controller[TRANSITION] = frame._getNavigationTransition(newEntry.entry);
                        }
                        else {
                            controller[TRANSITION] = {
                                name: NON_ANIMATED_TRANSITION,
                            };
                        }
                    }
                }
                if ((_d = frame.ios) === null || _d === void 0 ? void 0 : _d.controller) {
                    frame.ios.controller.delegate = this[DELEGATE];
                }
                frame._processNavigationQueue(owner);
                if (!__VISIONOS__) {
                    if (frame.canGoBack()) {
                        var transitionState = SharedTransition.getState(owner.transitionId);
                        if (transitionState === null || transitionState === void 0 ? void 0 : transitionState.interactive) {
                            navigationController.interactivePopGestureRecognizer.enabled = false;
                        }
                        else {
                            navigationController.interactivePopGestureRecognizer.delegate = navigationController;
                            navigationController.interactivePopGestureRecognizer.enabled = owner.enableSwipeBackNavigation;
                            if (SDK_VERSION >= 26 && navigationController.interactiveContentPopGestureRecognizer) {
                                navigationController.interactiveContentPopGestureRecognizer.enabled = owner.enableSwipeBackNavigation;
                            }
                        }
                    }
                    else {
                        navigationController.interactivePopGestureRecognizer.enabled = false;
                        if (SDK_VERSION >= 26 && navigationController.interactiveContentPopGestureRecognizer) {
                            navigationController.interactiveContentPopGestureRecognizer.enabled = false;
                        }
                    }
                }
            }
        }
        if (!this.presentedViewController) {
            owner._presentedViewController = null;
        }
    };
    UIViewControllerImpl.prototype.viewWillDisappear = function (animated) {
        var _a;
        _super.prototype.viewWillDisappear.call(this, animated);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return;
        }
        if (!owner._presentedViewController) {
            owner._presentedViewController = this.presentedViewController;
        }
        owner.updateWithWillDisappear(animated);
    };
    UIViewControllerImpl.prototype.viewDidDisappear = function (animated) {
        var _a;
        _super.prototype.viewDidDisappear.call(this, animated);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner || owner.modal || owner._presentedViewController) {
            return;
        }
        if (owner.isLoaded) {
            owner.callUnloaded();
        }
    };
    UIViewControllerImpl.prototype.viewWillLayoutSubviews = function () {
        var _a;
        _super.prototype.viewWillLayoutSubviews.call(this);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref( // Safe area insets include additional safe area insets too, so subtract old values
        );
        if (owner) {
            IOSHelper.updateConstraints(this, owner);
        }
    };
    UIViewControllerImpl.prototype.viewSafeAreaInsetsDidChange = function () {
        var _this = this;
        var _a;
        _super.prototype.viewSafeAreaInsetsDidChange.call(this);
        if (this.isRunningLayout || !this.didFirstLayout) {
            return;
        }
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            this.runLayout(function () { return IOSHelper.layoutView(_this, owner); });
        }
    };
    UIViewControllerImpl.prototype.viewDidLayoutSubviews = function () {
        var _a;
        this.startRunningLayout();
        _super.prototype.viewDidLayoutSubviews.call(this);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            if (SDK_VERSION >= 11) {
                var frame = owner.parent;
                var frameParent = frame && frame.parent;
                while (frameParent && !frameParent.nativeViewProtected) {
                    frameParent = frameParent.parent;
                }
                if (frameParent) {
                    var parentPageInsetsTop = frameParent.nativeViewProtected.safeAreaInsets.top;
                    var parentPageInsetsBottom = frameParent.nativeViewProtected.safeAreaInsets.bottom;
                    var currentInsetsTop = this.view.safeAreaInsets.top;
                    var currentInsetsBottom = this.view.safeAreaInsets.bottom;
                    if (this.additionalSafeAreaInsets) {
                        currentInsetsTop -= this.additionalSafeAreaInsets.top;
                        currentInsetsBottom -= this.additionalSafeAreaInsets.bottom;
                    }
                    var additionalInsetsTop = Math.max(parentPageInsetsTop - currentInsetsTop, 0);
                    var additionalInsetsBottom = Math.max(parentPageInsetsBottom - currentInsetsBottom, 0);
                    if (additionalInsetsTop > 0 || additionalInsetsBottom > 0) {
                        var additionalInsets = new UIEdgeInsets({
                            top: additionalInsetsTop,
                            left: 0,
                            bottom: additionalInsetsBottom,
                            right: 0,
                        });
                        this.additionalSafeAreaInsets = additionalInsets;
                    }
                    else {
                        this.additionalSafeAreaInsets = null;
                    }
                }
            }
            IOSHelper.layoutView(this, owner);
        }
        this.finishRunningLayout();
    };
    UIViewControllerImpl.prototype.traitCollectionDidChange = function (previousTraitCollection) {
        var _a;
        _super.prototype.traitCollectionDidChange.call(this, previousTraitCollection);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            if (SDK_VERSION >= 13) {
                if (this.traitCollection.hasDifferentColorAppearanceComparedToTraitCollection && this.traitCollection.hasDifferentColorAppearanceComparedToTraitCollection(previousTraitCollection)) {
                    owner.notify({
                        eventName: IOSHelper.traitCollectionColorAppearanceChangedEvent,
                        object: owner,
                    });
                }
            }
            if (this.traitCollection.layoutDirection !== previousTraitCollection.layoutDirection) {
                owner.notify({
                    eventName: IOSHelper.traitCollectionLayoutDirectionChangedEvent,
                    object: owner,
                });
            }
        }
    };
    UIViewControllerImpl.prototype.accessibilityPerformEscape = function () {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner === null || owner === void 0 ? void 0 : owner.onAccessibilityPerformEscape) {
            var result = owner.onAccessibilityPerformEscape();
            return result;
        }
        else {
            return false;
        }
    };
    Object.defineProperty(UIViewControllerImpl.prototype, "preferredStatusBarStyle", {
        get: function () {
            var _a;
            var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
            if (owner === null || owner === void 0 ? void 0 : owner.statusBarStyle) {
                if (SDK_VERSION >= 13) {
                    return owner.statusBarStyle === "light" ? UIStatusBarStyle.LightContent : UIStatusBarStyle.DarkContent;
                }
                else {
                    return owner.statusBarStyle === "light" ? UIStatusBarStyle.LightContent : UIStatusBarStyle.Default;
                }
            }
            return UIStatusBarStyle.Default;
        },
        enumerable: true,
        configurable: true
    });
    __decorate([
        profile
    ], UIViewControllerImpl.prototype, "viewDidAppear", null);
    __decorate([
        profile
    ], UIViewControllerImpl.prototype, "viewWillDisappear", null);
    __decorate([
        profile
    ], UIViewControllerImpl.prototype, "viewDidDisappear", null);
    return UIViewControllerImpl;
}(UIViewController));
export class Page extends PageBase {
    constructor() {
        super();
        this._backgroundColor = SDK_VERSION <= 12 && !UIColor.systemBackgroundColor ? UIColor.whiteColor : UIColor.systemBackgroundColor;
        const controller = UIViewControllerImpl.initWithOwner(new WeakRef(this));
        controller.view.backgroundColor = this._backgroundColor;
        this.viewController = this._ios = controller;
    }
    createNativeView() {
        // View controller can be disposed during view disposal, so make sure to create a new one if not defined
        if (!this._ios) {
            const controller = UIViewControllerImpl.initWithOwner(new WeakRef(this));
            controller.view.backgroundColor = this._backgroundColor;
            this.viewController = this._ios = controller;
        }
        return this._ios.view;
    }
    disposeNativeView() {
        this.viewController = null;
        this._ios = null;
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this._ios;
    }
    layoutNativeView(left, top, right, bottom) {
        const nativeView = this.nativeViewProtected;
        if (!nativeView) {
            return;
        }
        const currentFrame = nativeView.frame;
        // Create a copy of current view frame
        const newFrame = CGRectMake(currentFrame.origin.x, currentFrame.origin.y, currentFrame.size.width, currentFrame.size.height);
        this._setNativeViewFrame(nativeView, newFrame);
    }
    _modifyNativeViewFrame(nativeView, frame) {
        //
    }
    _shouldDelayLayout() {
        return this.frame && this.frame._animationInProgress;
    }
    onLoaded() {
        super.onLoaded();
        if (this.hasActionBar) {
            this.actionBar.update();
        }
    }
    updateWithWillAppear(animated) {
        // this method is important because it allows plugins to react to modal page close
        // for example allowing updating status bar background color
        if (this.hasActionBar) {
            this.actionBar.update();
        }
        this.updateStatusBar();
    }
    updateWithWillDisappear(animated) {
        // this method is important because it allows plugins to react to modal page close
        // for example allowing updating status bar background color
    }
    updateStatusBar() {
        this._updateStatusBarStyle(this.statusBarStyle);
    }
    _updateStatusBarStyle(value) {
        const frame = this.frame;
        if (frame?.ios && value) {
            const navigationController = frame.ios.controller;
            IOSHelper.invalidateStatusBarAppearance(navigationController, `Page._updateStatusBarStyle:${value}`);
        }
    }
    _updateEnableSwipeBackNavigation(enabled) {
        const navController = this._ios.navigationController;
        if (this.frame && navController) {
            // Make sure we don't set true if cannot go back
            enabled = enabled && this.frame.canGoBack();
            if (navController.interactivePopGestureRecognizer) {
                navController.interactivePopGestureRecognizer.enabled = enabled;
            }
            if (SDK_VERSION >= 26 && navController.interactiveContentPopGestureRecognizer) {
                navController.interactiveContentPopGestureRecognizer.enabled = enabled;
            }
        }
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        const width = layout.getMeasureSpecSize(widthMeasureSpec);
        const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
        const height = layout.getMeasureSpecSize(heightMeasureSpec);
        const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
        if (this.hasActionBar && this.frame && this.frame._getNavBarVisible(this)) {
            const { width, height } = this.actionBar._getActualSize;
            const widthSpec = layout.makeMeasureSpec(width, layout.EXACTLY);
            const heightSpec = layout.makeMeasureSpec(height, layout.EXACTLY);
            View.measureChild(this, this.actionBar, widthSpec, heightSpec);
        }
        const result = View.measureChild(this, this.layoutView, widthMeasureSpec, heightMeasureSpec);
        const measureWidth = Math.max(result.measuredWidth, this.effectiveMinWidth);
        const measureHeight = Math.max(result.measuredHeight, this.effectiveMinHeight);
        const widthAndState = View.resolveSizeAndState(measureWidth, width, widthMode, 0);
        const heightAndState = View.resolveSizeAndState(measureHeight, height, heightMode, 0);
        this.setMeasuredDimension(widthAndState, heightAndState);
    }
    onLayout(left, top, right, bottom) {
        if (this.hasActionBar) {
            const { width: actionBarWidth, height: actionBarHeight } = this.actionBar._getActualSize;
            View.layoutChild(this, this.actionBar, 0, 0, actionBarWidth, actionBarHeight);
        }
        const insets = this.getSafeAreaInsets();
        if (!__VISIONOS__ && SDK_VERSION <= 10 && this.viewController) {
            // iOS 10 and below don't have safe area insets API,
            // there we need only the top inset on the Page
            insets.top = layout.round(layout.toDevicePixels(this.viewController.view.safeAreaLayoutGuide.layoutFrame.origin.y));
        }
        const childLeft = 0 + insets.left;
        const childTop = 0 + insets.top;
        const childRight = right - insets.right;
        const childBottom = bottom - insets.bottom;
        View.layoutChild(this, this.layoutView, childLeft, childTop, childRight, childBottom);
    }
    _addViewToNativeVisualTree(child, atIndex) {
        // ActionBar is handled by the UINavigationController
        if (this.hasActionBar && child === this.actionBar) {
            return true;
        }
        const nativeParent = this.nativeViewProtected;
        const nativeChild = child.nativeViewProtected;
        const viewController = child.ios instanceof UIViewController ? child.ios : child.viewController;
        if (viewController) {
            // Adding modal controllers to as child will make app freeze.
            if (this.viewController.presentedViewController === viewController) {
                return true;
            }
            this.viewController.addChildViewController(viewController);
            if (typeof viewController.didMoveToParentViewController === 'function') {
                viewController.didMoveToParentViewController(this.viewController);
            }
        }
        if (nativeParent && nativeChild) {
            if (typeof atIndex !== 'number' || atIndex >= nativeParent.subviews.count) {
                nativeParent.addSubview(nativeChild);
            }
            else {
                nativeParent.insertSubviewAtIndex(nativeChild, atIndex);
            }
            return true;
        }
        return false;
    }
    _removeViewFromNativeVisualTree(child) {
        // ActionBar is handled by the UINavigationController
        if (this.hasActionBar && child === this.actionBar) {
            return;
        }
        const viewController = child.ios instanceof UIViewController ? child.ios : child.viewController;
        if (viewController) {
            if (typeof viewController.willMoveToParentViewController === 'function') {
                viewController.willMoveToParentViewController(null);
            }
            viewController.removeFromParentViewController();
        }
        super._removeViewFromNativeVisualTree(child);
    }
    [actionBarHiddenProperty.setNative](value) {
        // Invalidate all inner controller.
        invalidateTopmostController(this.viewController);
        const frame = this.frame;
        if (frame) {
            // Update nav-bar visibility with disabled animations
            frame._updateActionBar(this, true);
        }
    }
    [enableSwipeBackNavigationProperty.setNative](value) {
        this._updateEnableSwipeBackNavigation(value);
    }
    accessibilityScreenChanged(refocus = false) {
        if (!isAccessibilityServiceEnabled()) {
            return;
        }
        if (refocus) {
            const lastFocusedView = getLastFocusedViewOnPage(this);
            if (lastFocusedView) {
                const uiView = lastFocusedView.nativeViewProtected;
                if (uiView) {
                    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, uiView);
                    return;
                }
            }
        }
        if (this.actionBarHidden) {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, this.nativeViewProtected);
            return;
        }
        if (this.accessibilityLabel) {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, this.nativeViewProtected);
            return;
        }
        if (this.actionBar.accessibilityLabel || this.actionBar.title) {
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, this.actionBar.nativeView);
            return;
        }
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, this.nativeViewProtected);
    }
}
function invalidateTopmostController(controller) {
    if (!controller) {
        return;
    }
    controller.view.setNeedsLayout();
    const presentedViewController = controller.presentedViewController;
    if (presentedViewController) {
        return invalidateTopmostController(presentedViewController);
    }
    const childControllers = controller.childViewControllers;
    let size = controller.childViewControllers.count;
    while (size > 0) {
        const childController = childControllers[--size];
        if (childController instanceof UITabBarController) {
            invalidateTopmostController(childController.selectedViewController);
        }
        else if (childController instanceof UINavigationController) {
            invalidateTopmostController(childController.topViewController);
        }
        else if (childController instanceof UISplitViewController) {
            invalidateTopmostController(childController.viewControllers.lastObject);
        }
        else {
            invalidateTopmostController(childController);
        }
    }
}
//# sourceMappingURL=index.ios.js.map