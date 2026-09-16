import { FrameBase, NavigationType } from './frame-common';
import { CoreTypes } from '../enums';
import { View } from '../core/view';
import { IOSHelper } from '../core/view/view-helper';
import { profile } from '../../profiling';
import { layout } from '../../utils/layout-helper';
import { CORE_ANIMATION_DEFAULTS } from '../../utils/animation-helpers';
import { SDK_VERSION } from '../../utils/constants';
import { Trace } from '../../trace';
import { SlideTransition } from '../transition/slide-transition';
import { FadeTransition } from '../transition/fade-transition';
import { SharedTransition } from '../transition/shared-transition';
export * from './frame-common';
const ENTRY = '_entry';
const DELEGATE = '_delegate';
const NAV_DEPTH = '_navDepth';
const TRANSITION = '_transition';
const NON_ANIMATED_TRANSITION = 'non-animated';
let navDepth = -1;
let navControllerDelegate = null;
export class Frame extends FrameBase {
    constructor() {
        super();
        this._ios = new iOSFrame(this);
        this.viewController = this._ios.controller;
    }
    createNativeView() {
        // Push frame back in frame stack since it was removed in disposeNativeView() method.
        if (this._currentEntry) {
            this._pushInFrameStack();
        }
        // View controller can be disposed during view disposal, so make sure to create a new one if not defined
        if (!this._ios) {
            this._ios = new iOSFrame(this);
            this.viewController = this._ios.controller;
        }
        return this._ios.controller.view;
    }
    disposeNativeView() {
        const current = this._currentEntry;
        const executingEntry = this._executingContext ? this._executingContext.entry : null;
        if (executingEntry) {
            this._disposeBackstackEntry(executingEntry);
        }
        this.backStack.forEach((entry) => {
            if (entry !== executingEntry) {
                this._disposeBackstackEntry(entry);
            }
        });
        if (current) {
            this._disposeBackstackEntry(current);
        }
        this._removeFromFrameStack();
        if (this.viewController) {
            this.viewController.lastExecutingTransition = null;
            this.viewController = null;
        }
        // This was the last frame so we can get rid of the controller delegate reference
        if (this._isFrameStackEmpty()) {
            navControllerDelegate = null;
        }
        if (this._ios) {
            this._ios.controller = null;
            this._ios = null;
        }
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this._ios;
    }
    setCurrent(entry, navigationType) {
        const current = this._currentEntry;
        const currentEntryChanged = current !== entry;
        if (entry?.resolvedPage && currentEntryChanged) {
            this._updateBackstack(entry, navigationType);
            super.setCurrent(entry, navigationType);
        }
    }
    // !!! THIS PROFILE DECORATOR CREATES A CIRCULAR DEPENDENCY
    // !!! BECAUSE THE PARAMETER TYPE IS EVALUATED WITH TYPEOF
    _navigateCore(backstackEntry) {
        super._navigateCore(backstackEntry);
        const viewController = backstackEntry.resolvedPage.ios;
        if (!viewController) {
            throw new Error('Required page does not have a viewController created.');
        }
        const clearHistory = backstackEntry.entry.clearHistory;
        if (clearHistory) {
            navDepth = -1;
        }
        const isReplace = this._executingContext && this._executingContext.navigationType === NavigationType.replace;
        if (!isReplace) {
            navDepth++;
        }
        let navigationTransition;
        const animated = this.currentPage ? this._getIsAnimatedNavigation(backstackEntry.entry) : false;
        if (animated) {
            navigationTransition = this._getNavigationTransition(backstackEntry.entry);
            if (navigationTransition) {
                viewController[TRANSITION] = navigationTransition;
            }
        }
        else {
            //https://github.com/NativeScript/NativeScript/issues/1787
            viewController[TRANSITION] = { name: NON_ANIMATED_TRANSITION };
        }
        if (!navControllerDelegate) {
            navControllerDelegate = UINavigationControllerDelegateImpl.new();
        }
        this._ios.controller.delegate = navControllerDelegate;
        viewController[DELEGATE] = navControllerDelegate;
        const nativeTransition = _getNativeTransition(navigationTransition, true, this.direction);
        if (!nativeTransition && navigationTransition) {
            if (navigationTransition.instance) {
                this.transitionId = navigationTransition.instance.id;
                const transitionState = SharedTransition.getState(this.transitionId);
                if (transitionState?.interactive?.dismiss) {
                    // interactive transitions via gestures
                    // TODO - allow users to define their own custom gesture dismissals
                    navigationTransition.instance.setupInteractiveGesture(() => {
                        this._ios.controller.popViewControllerAnimated(true);
                    }, this);
                }
            }
        }
        backstackEntry[NAV_DEPTH] = navDepth;
        viewController[ENTRY] = backstackEntry;
        if (!animated && SDK_VERSION > 10) {
            // Reset back button title before pushing view controller to prevent
            // displaying default 'back' title (when NavigaitonButton custom title is set).
            const barButtonItem = UIBarButtonItem.alloc().initWithTitleStyleTargetAction('', 0 /* UIBarButtonItemStyle.Plain */, null, null);
            viewController.navigationItem.backBarButtonItem = barButtonItem;
        }
        // First navigation.
        if (!this._currentEntry) {
            // Update action-bar with disabled animations before the initial navigation.
            this._updateActionBar(backstackEntry.resolvedPage, true);
            // Core defaults modalPresentationStyle to 1 for standard frame navigation
            // for all others, it's modal presentation
            this.pushViewControllerAnimated(viewController, animated, this._ios?.controller?.modalPresentationStyle !== 1);
            if (Trace.isEnabled()) {
                Trace.write(`${this}.pushViewControllerAnimated(${viewController}, ${animated}); depth = ${navDepth}`, Trace.categories.Navigation);
            }
            return;
        }
        // We should clear the entire history.
        if (clearHistory) {
            viewController.navigationItem.hidesBackButton = true;
            const newControllers = NSMutableArray.alloc().initWithCapacity(1);
            newControllers.addObject(viewController);
            // Mark all previous ViewControllers as cleared
            const oldControllers = this._ios.controller.viewControllers;
            for (let i = 0; i < oldControllers.count; i++) {
                oldControllers.objectAtIndex(i).isBackstackCleared = true;
            }
            this._ios.controller.setViewControllersAnimated(newControllers, animated);
            if (Trace.isEnabled()) {
                Trace.write(`${this}.setViewControllersAnimated([${viewController}], ${animated}); depth = ${navDepth}`, Trace.categories.Navigation);
            }
            return;
        }
        // We should hide the current entry from the back stack.
        // This is the case for HMR when NavigationType.replace.
        if (!Frame._isEntryBackstackVisible(this._currentEntry) || isReplace) {
            const newControllers = NSMutableArray.alloc().initWithArray(this._ios.controller.viewControllers);
            if (newControllers.count === 0) {
                throw new Error('Wrong controllers count.');
            }
            // the code below fixes a phantom animation that appears on the Back button in this case
            // TODO: investigate why the animation happens at first place before working around it
            viewController.navigationItem.hidesBackButton = this.backStack.length === 0;
            // swap the top entry with the new one
            const skippedNavController = newControllers.lastObject;
            skippedNavController.isBackstackSkipped = true;
            newControllers.removeLastObject();
            newControllers.addObject(viewController);
            // replace the controllers instead of pushing directly
            this._ios.controller.setViewControllersAnimated(newControllers, animated);
            if (Trace.isEnabled()) {
                Trace.write(`${this}.setViewControllersAnimated([originalControllers - lastController + ${viewController}], ${animated}); depth = ${navDepth}`, Trace.categories.Navigation);
            }
            return;
        }
        // General case.
        this._ios.controller.pushViewControllerAnimated(viewController, animated);
        if (Trace.isEnabled()) {
            Trace.write(`${this}.pushViewControllerAnimated(${viewController}, ${animated}); depth = ${navDepth}`, Trace.categories.Navigation);
        }
    }
    pushViewControllerAnimated(viewController, animated, isModal) {
        const transitionCoordinator = this._ios.controller.transitionCoordinator;
        if (!isModal && transitionCoordinator) {
            transitionCoordinator.animateAlongsideTransitionCompletion(null, () => {
                this._ios.controller.pushViewControllerAnimated(viewController, animated);
            });
        }
        else {
            // modal should always push immediately without transition coordinator
            this._ios.controller.pushViewControllerAnimated(viewController, animated);
        }
    }
    _goBackCore(backstackEntry) {
        super._goBackCore(backstackEntry);
        navDepth = backstackEntry[NAV_DEPTH];
        const controller = backstackEntry.resolvedPage.ios;
        const animated = this._currentEntry ? this._getIsAnimatedNavigation(this._currentEntry.entry) : false;
        this._updateActionBar(backstackEntry.resolvedPage);
        if (Trace.isEnabled()) {
            Trace.write(`${this}.popToViewControllerAnimated(${controller}, ${animated}); depth = ${navDepth}`, Trace.categories.Navigation);
        }
        this._ios.controller.popToViewControllerAnimated(controller, animated);
    }
    _updateActionBar(page, disableNavBarAnimation = false) {
        super._updateActionBar(page);
        if (!this._ios || (page && this.currentPage && this.currentPage.modal === page)) {
            return;
        }
        page = page || this.currentPage;
        const newValue = this._getNavBarVisible(page);
        const disableNavBarAnimationCache = this._ios._disableNavBarAnimation;
        if (disableNavBarAnimation) {
            this._ios._disableNavBarAnimation = true;
        }
        // when showing/hiding navigationbar, the page needs a relayout to avoid overlapping or hidden layouts
        const needsPageLayout = this._ios.showNavigationBar !== newValue;
        this._ios.showNavigationBar = newValue;
        if (disableNavBarAnimation) {
            this._ios._disableNavBarAnimation = disableNavBarAnimationCache;
        }
        if (this._ios.controller?.navigationBar) {
            this._ios.controller.navigationBar.userInteractionEnabled = this.navigationQueueIsEmpty();
        }
        if (needsPageLayout && page) {
            page.requestLayout();
        }
    }
    _getNavBarVisible(page) {
        switch (this.actionBarVisibility) {
            case 'always':
                return true;
            case 'never':
                return false;
            case 'auto':
                switch (this._ios.navBarVisibility) {
                    case 'always':
                        return true;
                    case 'never':
                        return false;
                    case 'auto': {
                        let newValue;
                        if (page && page.actionBarHidden !== undefined) {
                            newValue = !page.actionBarHidden;
                        }
                        else {
                            newValue = this.ios.controller.viewControllers.count > 1 || (page && page.actionBar && !page.actionBar._isEmpty());
                        }
                        newValue = !!newValue;
                        return newValue;
                    }
                }
        }
    }
    static get defaultAnimatedNavigation() {
        return FrameBase.defaultAnimatedNavigation;
    }
    static set defaultAnimatedNavigation(value) {
        FrameBase.defaultAnimatedNavigation = value;
    }
    static get defaultTransition() {
        return FrameBase.defaultTransition;
    }
    static set defaultTransition(value) {
        FrameBase.defaultTransition = value;
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        const width = layout.getMeasureSpecSize(widthMeasureSpec);
        const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
        const height = layout.getMeasureSpecSize(heightMeasureSpec);
        const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
        const widthAndState = View.resolveSizeAndState(width, width, widthMode, 0);
        const heightAndState = View.resolveSizeAndState(height, height, heightMode, 0);
        this.setMeasuredDimension(widthAndState, heightAndState);
    }
    layoutNativeView(left, top, right, bottom) {
        //
    }
    _setNativeViewFrame(nativeView, frame) {
        //
    }
    // Emits an event whenever the UINavigationController shows a view controller.
    // Consumers can subscribe to 'viewControllerShown'
    // to safely interact with the visible controller/navigationItem once it exists.
    _onViewControllerShown(viewController) {
        this.notify({
            eventName: 'viewControllerShown',
            object: this,
            viewController,
        });
    }
}
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], Frame.prototype, "_navigateCore", null);
const transitionDelegates = new Array();
var TransitionDelegate = (function (_super) {
    __extends(TransitionDelegate, _super);
    function TransitionDelegate() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    TransitionDelegate.initWithOwnerId = function (id) {
        var delegate = TransitionDelegate.new();
        delegate._id = id;
        transitionDelegates.push(delegate);
        return delegate;
    };
    TransitionDelegate.prototype.animationWillStart = function (animationID, context) {
        if (Trace.isEnabled()) {
            Trace.write("START ".concat(this._id), Trace.categories.Transition);
        }
    };
    TransitionDelegate.prototype.animationDidStop = function (animationID, finished, context) {
        if (finished) {
            if (Trace.isEnabled()) {
                Trace.write("END ".concat(this._id), Trace.categories.Transition);
            }
        }
        else {
            if (Trace.isEnabled()) {
                Trace.write("CANCEL ".concat(this._id), Trace.categories.Transition);
            }
        }
        var index = transitionDelegates.indexOf(this);
        if (index > -1) {
            transitionDelegates.splice(index, 1);
        }
    };
    TransitionDelegate.ObjCExposedMethods = {
        animationWillStart: {
            returns: interop.types.void,
            params: [NSString, NSObject],
        },
        animationDidStop: {
            returns: interop.types.void,
            params: [NSString, NSNumber, NSObject],
        },
    };
    return TransitionDelegate;
}(NSObject));
var UINavigationControllerDelegateImpl = (function (_super) {
    __extends(UINavigationControllerDelegateImpl, _super);
    function UINavigationControllerDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UINavigationControllerDelegateImpl.prototype.navigationControllerAnimationControllerForOperationFromViewControllerToViewController = function (navigationController, operation, fromVC, toVC) {
        var _a;
        var viewController;
        switch (operation) {
            case UINavigationControllerOperation.Push:
                viewController = toVC;
                break;
            case UINavigationControllerOperation.Pop:
                viewController = fromVC;
                break;
        }
        if (!viewController) {
            return null;
        }
        var navigationTransition = viewController[TRANSITION];
        if (!navigationTransition) {
            return null;
        }
        var layoutDirection = (_a = navigationController.owner) === null || _a === void 0 ? void 0 : _a.direction;
        if (Trace.isEnabled()) {
            Trace.write("UINavigationControllerImpl.navigationControllerAnimationControllerForOperationFromViewControllerToViewController(".concat(operation, ", ").concat(fromVC, ", ").concat(toVC, "), transition: ").concat(JSON.stringify(navigationTransition)), Trace.categories.NativeLifecycle);
        }
        var transition = navigationTransition.instance;
        if (!transition) {
            if (navigationTransition.name) {
                var curve = _getNativeCurve(navigationTransition);
                var name = navigationTransition.name.toLowerCase();
                var type = "slide";
                var defaultDirection = layoutDirection === CoreTypes.LayoutDirection.rtl ? "right" : "left";
                if (name.indexOf(type) === 0) {
                    var direction = name === type ? defaultDirection : name.substring(type.length);
                    transition = new SlideTransition(direction, navigationTransition.duration, curve);
                }
                else if (name === "fade") {
                    transition = new FadeTransition(navigationTransition.duration, curve);
                }
            }
        }
        navigationController.lastExecutingTransition = transition;
        if (transition === null || transition === void 0 ? void 0 : transition.iosNavigatedController) {
            return transition.iosNavigatedController(navigationController, operation, fromVC, toVC);
        }
        return null;
    };
    UINavigationControllerDelegateImpl.prototype.navigationControllerInteractionControllerForAnimationController = function (navigationController, animationController) {
        var _a, _b;
        var owner = navigationController.owner;
        if (owner) {
            var state = SharedTransition.getState(owner.transitionId);
            if ((_a = state === null || state === void 0 ? void 0 : state.instance) === null || _a === void 0 ? void 0 : _a.iosInteractionDismiss) {
                if (state === null || state === void 0 ? void 0 : state.interactiveBegan) {
                    return (_b = state === null || state === void 0 ? void 0 : state.instance) === null || _b === void 0 ? void 0 : _b.iosInteractionDismiss(null);
                }
            }
        }
        return null;
    };
    UINavigationControllerDelegateImpl.prototype.navigationControllerDidShowViewControllerAnimated = function (navigationController, viewController, animated) {
        if (Trace.isEnabled()) {
            Trace.write("Frame.navigationController.DID_show(" + navigationController + ", " + viewController + ", " + animated + ");", Trace.categories.Debug);
        }
        var owner = navigationController.owner;
        if (owner) {
            owner._onViewControllerShown(viewController);
        }
        IOSHelper.invalidateStatusBarAppearance(navigationController, "navigationControllerDidShowViewControllerAnimated");
    };
    UINavigationControllerDelegateImpl.ObjCProtocols = [UINavigationControllerDelegate];
    return UINavigationControllerDelegateImpl;
}(NSObject));
var UINavigationControllerImpl = (function (_super) {
    __extends(UINavigationControllerImpl, _super);
    function UINavigationControllerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UINavigationControllerImpl.initWithOwner = function (owner) {
        var _a, _b, _c, _d;
        var navigationBarClass = (_b = (_a = owner.deref()) === null || _a === void 0 ? void 0 : _a.iosNavigationBarClass) !== null && _b !== void 0 ? _b : null;
        var toolbarClass = (_d = (_c = owner.deref()) === null || _c === void 0 ? void 0 : _c.iosToolbarClass) !== null && _d !== void 0 ? _d : null;
        var controller = navigationBarClass || toolbarClass ? UINavigationControllerImpl.alloc().initWithNavigationBarClassToolbarClass(navigationBarClass, toolbarClass) : UINavigationControllerImpl.new();
        controller._owner = owner;
        return controller;
    };
    Object.defineProperty(UINavigationControllerImpl.prototype, "owner", {
        get: function () {
            var _a, _b;
            return (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        },
        enumerable: true,
        configurable: true
    });
    UINavigationControllerImpl.prototype.viewWillAppear = function (animated) {
        var _a, _b;
        _super.prototype.viewWillAppear.call(this, animated);
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        if (owner && !owner.isLoaded && !owner.parent) {
            owner.callLoaded();
        }
    };
    UINavigationControllerImpl.prototype.viewDidDisappear = function (animated) {
        var _a, _b;
        _super.prototype.viewDidDisappear.call(this, animated);
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        if (owner && owner.isLoaded && !owner.parent && !this.presentedViewController) {
            owner.callUnloaded();
            owner._tearDownUI(true);
        }
    };
    UINavigationControllerImpl.prototype.animateWithDuration = function (navigationTransition, nativeTransition, transitionType, baseCallback) {
        var _this = this;
        var duration = navigationTransition.duration ? navigationTransition.duration / 1000 : CORE_ANIMATION_DEFAULTS.duration;
        var curve = _getNativeCurve(navigationTransition);
        var transitionTraced = Trace.isCategorySet(Trace.categories.Transition);
        var transitionDelegate;
        if (transitionTraced) {
            var id = _getTransitionId(nativeTransition, transitionType);
            transitionDelegate = TransitionDelegate.initWithOwnerId(id);
        }
        UIView.animateWithDurationAnimations(duration, function () {
            if (transitionTraced) {
                UIView.setAnimationDelegate(transitionDelegate);
            }
            UIView.setAnimationWillStartSelector("animationWillStart");
            UIView.setAnimationDidStopSelector("animationDidStop");
            UIView.setAnimationCurve(curve);
            baseCallback();
            UIView.setAnimationTransitionForViewCache(nativeTransition, _this.view, true);
        });
    };
    UINavigationControllerImpl.prototype.pushViewControllerAnimated = function (viewController, animated) {
        var _this = this;
        var _a, _b;
        var navigationTransition = viewController[TRANSITION];
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        var logTag = "UINavigationControllerImpl.pushViewControllerAnimated";
        if (Trace.isEnabled()) {
            Trace.write("".concat(logTag, "(").concat(viewController, ", ").concat(animated, "); transition: ").concat(JSON.stringify(navigationTransition)), Trace.categories.NativeLifecycle);
        }
        var nativeTransition = _getNativeTransition(navigationTransition, true, owner === null || owner === void 0 ? void 0 : owner.direction);
        if (!animated || !navigationTransition || !nativeTransition) {
            _super.prototype.pushViewControllerAnimated.call(this, viewController, animated);
            IOSHelper.invalidateStatusBarAppearance(this, logTag);
            return;
        }
        this.animateWithDuration(navigationTransition, nativeTransition, "push", function () {
            _super.prototype.pushViewControllerAnimated.call(_this, viewController, false);
        });
        IOSHelper.invalidateStatusBarAppearance(this, logTag);
    };
    UINavigationControllerImpl.prototype.setViewControllersAnimated = function (viewControllers, animated) {
        var _this = this;
        var _a, _b;
        var viewController = viewControllers === null || viewControllers === void 0 ? void 0 : viewControllers.lastObject;
        var navigationTransition = viewController ? viewController[TRANSITION] : null;
        if (Trace.isEnabled()) {
            Trace.write("UINavigationControllerImpl.setViewControllersAnimated(".concat(viewControllers, ", ").concat(animated, "); transition: ").concat(JSON.stringify(navigationTransition)), Trace.categories.NativeLifecycle);
        }
        var logTag = "UINavigationControllerImpl.setViewControllersAnimated";
        if (!animated || !navigationTransition) {
            _super.prototype.setViewControllersAnimated.call(this, viewControllers, animated);
            IOSHelper.invalidateStatusBarAppearance(this, logTag);
            return;
        }
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        var nativeTransition = _getNativeTransition(navigationTransition, true, owner === null || owner === void 0 ? void 0 : owner.direction);
        if (!nativeTransition) {
            _super.prototype.setViewControllersAnimated.call(this, viewControllers, animated);
            IOSHelper.invalidateStatusBarAppearance(this, logTag);
            return;
        }
        this.animateWithDuration(navigationTransition, nativeTransition, "set", function () {
            _super.prototype.setViewControllersAnimated.call(_this, viewControllers, false);
        });
        IOSHelper.invalidateStatusBarAppearance(this, logTag);
    };
    UINavigationControllerImpl.prototype.popViewControllerAnimated = function (animated) {
        var _this = this;
        var _a, _b;
        var lastViewController = this.viewControllers.lastObject;
        var navigationTransition = lastViewController[TRANSITION];
        if (Trace.isEnabled()) {
            Trace.write("UINavigationControllerImpl.popViewControllerAnimated(".concat(animated, "); transition: ").concat(JSON.stringify(navigationTransition)), Trace.categories.NativeLifecycle);
        }
        if (navigationTransition && navigationTransition.name === NON_ANIMATED_TRANSITION) {
            return _super.prototype.popViewControllerAnimated.call(this, false);
        }
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        var nativeTransition = _getNativeTransition(navigationTransition, false, owner === null || owner === void 0 ? void 0 : owner.direction);
        if (!animated || !navigationTransition || !nativeTransition) {
            return _super.prototype.popViewControllerAnimated.call(this, animated);
        }
        this.animateWithDuration(navigationTransition, nativeTransition, "pop", function () {
            _super.prototype.popViewControllerAnimated.call(_this, false);
        });
        return null;
    };
    UINavigationControllerImpl.prototype.popToViewControllerAnimated = function (viewController, animated) {
        var _this = this;
        var _a, _b;
        var lastViewController = this.viewControllers.lastObject;
        var navigationTransition = lastViewController[TRANSITION];
        if (Trace.isEnabled()) {
            Trace.write("UINavigationControllerImpl.popToViewControllerAnimated(".concat(viewController, ", ").concat(animated, "); transition: ").concat(JSON.stringify(navigationTransition)), Trace.categories.NativeLifecycle);
        }
        if (navigationTransition && navigationTransition.name === NON_ANIMATED_TRANSITION) {
            return _super.prototype.popToViewControllerAnimated.call(this, viewController, false);
        }
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
        var nativeTransition = _getNativeTransition(navigationTransition, false, owner === null || owner === void 0 ? void 0 : owner.direction);
        if (!animated || !navigationTransition || !nativeTransition) {
            return _super.prototype.popToViewControllerAnimated.call(this, viewController, animated);
        }
        this.animateWithDuration(navigationTransition, nativeTransition, "popTo", function () {
            _super.prototype.popToViewControllerAnimated.call(_this, viewController, false);
        });
        return null;
    };
    UINavigationControllerImpl.prototype.traitCollectionDidChange = function (previousTraitCollection) {
        var _a, _b;
        _super.prototype.traitCollectionDidChange.call(this, previousTraitCollection);
        var owner = (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a);
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
    Object.defineProperty(UINavigationControllerImpl.prototype, "childViewControllerForStatusBarStyle", {
        get: function () {
            return this.topViewController;
        },
        enumerable: true,
        configurable: true
    });
    Object.defineProperty(UINavigationControllerImpl.prototype, "preferredStatusBarStyle", {
        get: function () {
            var _a;
            var top = this.topViewController;
            return (_a = top === null || top === void 0 ? void 0 : top.preferredStatusBarStyle) !== null && _a !== void 0 ? _a : UIStatusBarStyle.Default;
        },
        enumerable: true,
        configurable: true
    });
    __decorate([
        profile
    ], UINavigationControllerImpl.prototype, "viewWillAppear", null);
    __decorate([
        profile
    ], UINavigationControllerImpl.prototype, "viewDidDisappear", null);
    __decorate([
        profile
    ], UINavigationControllerImpl.prototype, "pushViewControllerAnimated", null);
    __decorate([
        profile
    ], UINavigationControllerImpl.prototype, "setViewControllersAnimated", null);
    return UINavigationControllerImpl;
}(UINavigationController));
function _getTransitionId(nativeTransition, transitionType) {
    let name;
    switch (nativeTransition) {
        case 4 /* UIViewAnimationTransition.CurlDown */:
            name = 'CurlDown';
            break;
        case 3 /* UIViewAnimationTransition.CurlUp */:
            name = 'CurlUp';
            break;
        case 1 /* UIViewAnimationTransition.FlipFromLeft */:
            name = 'FlipFromLeft';
            break;
        case 2 /* UIViewAnimationTransition.FlipFromRight */:
            name = 'FlipFromRight';
            break;
        case 0 /* UIViewAnimationTransition.None */:
            name = 'None';
            break;
    }
    return `${name} ${transitionType}`;
}
function _getNativeTransition(navigationTransition, push, direction) {
    if (navigationTransition && navigationTransition.name) {
        switch (navigationTransition.name.toLowerCase()) {
            case 'flip':
                if (direction === CoreTypes.LayoutDirection.rtl) {
                    return push ? 1 /* UIViewAnimationTransition.FlipFromLeft */ : 2 /* UIViewAnimationTransition.FlipFromRight */;
                }
                return push ? 2 /* UIViewAnimationTransition.FlipFromRight */ : 1 /* UIViewAnimationTransition.FlipFromLeft */;
            case 'flipright':
                return push ? 2 /* UIViewAnimationTransition.FlipFromRight */ : 1 /* UIViewAnimationTransition.FlipFromLeft */;
            case 'flipleft':
                return push ? 1 /* UIViewAnimationTransition.FlipFromLeft */ : 2 /* UIViewAnimationTransition.FlipFromRight */;
            case 'curl':
            case 'curlup':
                return push ? 3 /* UIViewAnimationTransition.CurlUp */ : 4 /* UIViewAnimationTransition.CurlDown */;
            case 'curldown':
                return push ? 4 /* UIViewAnimationTransition.CurlDown */ : 3 /* UIViewAnimationTransition.CurlUp */;
        }
    }
    return null;
}
export function _getNativeCurve(transition) {
    if (transition.curve) {
        switch (transition.curve) {
            case 'easeIn':
                if (Trace.isEnabled()) {
                    Trace.write('Transition curve resolved to UIViewAnimationCurve.EaseIn.', Trace.categories.Transition);
                }
                return 1 /* UIViewAnimationCurve.EaseIn */;
            case 'easeOut':
                if (Trace.isEnabled()) {
                    Trace.write('Transition curve resolved to UIViewAnimationCurve.EaseOut.', Trace.categories.Transition);
                }
                return 2 /* UIViewAnimationCurve.EaseOut */;
            case 'easeInOut':
                if (Trace.isEnabled()) {
                    Trace.write('Transition curve resolved to UIViewAnimationCurve.EaseInOut.', Trace.categories.Transition);
                }
                return 0 /* UIViewAnimationCurve.EaseInOut */;
            case 'linear':
                if (Trace.isEnabled()) {
                    Trace.write('Transition curve resolved to UIViewAnimationCurve.Linear.', Trace.categories.Transition);
                }
                return 3 /* UIViewAnimationCurve.Linear */;
            default:
                if (Trace.isEnabled()) {
                    Trace.write('Transition curve resolved to original: ' + transition.curve, Trace.categories.Transition);
                }
                return transition.curve;
        }
    }
    return 0 /* UIViewAnimationCurve.EaseInOut */;
}
class iOSFrame {
    constructor(frame) {
        this._navBarVisibility = 'auto';
        this._controller = UINavigationControllerImpl.initWithOwner(new WeakRef(frame));
    }
    get controller() {
        return this._controller;
    }
    set controller(value) {
        this._controller = value;
    }
    get showNavigationBar() {
        return this._showNavigationBar;
    }
    set showNavigationBar(value) {
        this._showNavigationBar = value;
        if (this._controller) {
            this._controller.setNavigationBarHiddenAnimated(!value, !this._disableNavBarAnimation);
        }
    }
    get navBarVisibility() {
        return this._navBarVisibility;
    }
    set navBarVisibility(value) {
        this._navBarVisibility = value;
    }
}
export function setActivityCallbacks(activity) { }
//# sourceMappingURL=index.ios.js.map