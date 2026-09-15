// Requires
import { ViewHelper } from './view-helper-common';
import { SDK_VERSION } from '../../../../utils/constants';
import { layout, Trace } from './view-helper-shared';
import { ios as iosUtils, getWindow } from '../../../../utils';
export * from './view-helper-common';
export const AndroidHelper = 0;
var UILayoutViewController = (function (_super) {
    __extends(UILayoutViewController, _super);
    function UILayoutViewController() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UILayoutViewController.initWithOwner = function (owner) {
        var controller = UILayoutViewController.new();
        controller.owner = owner;
        return controller;
    };
    UILayoutViewController.prototype.viewDidLoad = function () {
        _super.prototype.viewDidLoad.call(this);
        this.extendedLayoutIncludesOpaqueBars = true;
    };
    UILayoutViewController.prototype.viewWillLayoutSubviews = function () {
        var _a;
        _super.prototype.viewWillLayoutSubviews.call(this);
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            IOSHelper.updateConstraints(this, owner);
        }
    };
    UILayoutViewController.prototype.viewDidLayoutSubviews = function () {
        var _a;
        _super.prototype.viewDidLayoutSubviews.call(this);
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            if (SDK_VERSION >= 11) {
                var tabViewItem = owner.parent;
                var tabView = tabViewItem && tabViewItem.parent;
                var parent = tabView && tabView.parent;
                while (parent && !parent.nativeViewProtected) {
                    parent = parent.parent;
                }
                if (parent) {
                    var parentPageInsetsTop = parent.nativeViewProtected.safeAreaInsets.top;
                    var parentPageInsetsBottom = parent.nativeViewProtected.safeAreaInsets.bottom;
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
        // Without this, iOS may use this controller's own preferredStatusBarStyle,
        // which can be unrelated to the currently shown Page.
        // @ts-ignore
    };
    UILayoutViewController.prototype.viewWillAppear = function (animated) {
        var _a;
        _super.prototype.viewWillAppear.call(this, animated);
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return;
        }
        IOSHelper.invalidateStatusBarAppearance(this, "UILayoutViewController.viewWillAppear");
        IOSHelper.updateAutoAdjustScrollInsets(this, owner);
        if (!owner.isLoaded && !owner.parent) {
            owner.callLoaded();
        }
    };
    UILayoutViewController.prototype.viewDidDisappear = function (animated) {
        var _a;
        _super.prototype.viewDidDisappear.call(this, animated);
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && owner.isLoaded && !owner.parent) {
            owner.callUnloaded();
        }
    };
    Object.defineProperty(UILayoutViewController.prototype, "childViewControllerForStatusBarStyle", {
        get: function () {
            var _a;
            return this.presentedViewController || ((_a = this.childViewControllers) === null || _a === void 0 ? void 0 : _a.lastObject);
        },
        enumerable: true,
        configurable: true
    });
    UILayoutViewController.prototype.traitCollectionDidChange = function (previousTraitCollection) {
        var _a;
        _super.prototype.traitCollectionDidChange.call(this, previousTraitCollection);
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
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
    Object.defineProperty(UILayoutViewController.prototype, "preferredStatusBarStyle", {
        get: function () {
            var _a;
            var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
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
    return UILayoutViewController;
}(UIViewController));
var UIAdaptivePresentationControllerDelegateImp = (function (_super) {
    __extends(UIAdaptivePresentationControllerDelegateImp, _super);
    function UIAdaptivePresentationControllerDelegateImp() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UIAdaptivePresentationControllerDelegateImp.initWithOwnerAndCallback = function (owner, whenClosedCallback) {
        var instance = _super.new.call(this);
        instance.owner = owner;
        instance.closedCallback = whenClosedCallback;
        return instance;
    };
    UIAdaptivePresentationControllerDelegateImp.prototype.presentationControllerDidDismiss = function (presentationController) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && typeof this.closedCallback === "function") {
            this.closedCallback();
        }
    };
    UIAdaptivePresentationControllerDelegateImp.ObjCProtocols = [UIAdaptivePresentationControllerDelegate];
    return UIAdaptivePresentationControllerDelegateImp;
}(NSObject));
var UIPopoverPresentationControllerDelegateImp = (function (_super) {
    __extends(UIPopoverPresentationControllerDelegateImp, _super);
    function UIPopoverPresentationControllerDelegateImp() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UIPopoverPresentationControllerDelegateImp.initWithOwnerAndCallback = function (owner, whenClosedCallback) {
        var instance = _super.new.call(this);
        instance.owner = owner;
        instance.closedCallback = whenClosedCallback;
        return instance;
    };
    UIPopoverPresentationControllerDelegateImp.prototype.popoverPresentationControllerDidDismissPopover = function (popoverPresentationController) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && typeof this.closedCallback === "function") {
            this.closedCallback();
        }
    };
    UIPopoverPresentationControllerDelegateImp.ObjCProtocols = [UIPopoverPresentationControllerDelegate];
    return UIPopoverPresentationControllerDelegateImp;
}(NSObject));
export class IOSHelper {
    static getParentWithViewController(view) {
        while (view && !view.viewController) {
            view = view.parent;
        }
        // Note: Might return undefined if no parent with viewController is found
        return view;
    }
    static invalidateStatusBarAppearance(controller, reason = '') {
        try {
            if (!controller) {
                const window = getWindow?.();
                const rootController = window?.rootViewController;
                controller = rootController ? iosUtils.getVisibleViewController(rootController) : null;
            }
            if (!controller) {
                if (Trace.isEnabled()) {
                    Trace.write(`[StatusBar] invalidate skipped (no controller) reason=${reason}`, Trace.categories.NativeLifecycle);
                }
                return;
            }
            const container = controller;
            let child = null;
            try {
                child = container.childViewControllerForStatusBarStyle;
            }
            catch {
                child = null;
            }
            if (!child) {
                if (container instanceof UINavigationController) {
                    child = container.topViewController;
                }
                else if (container instanceof UITabBarController) {
                    child = container.selectedViewController;
                }
            }
            // Always invalidate container and likely child.
            container.setNeedsStatusBarAppearanceUpdate?.();
            child?.setNeedsStatusBarAppearanceUpdate?.();
            // Also invalidate nav container if present.
            const nav = container instanceof UINavigationController ? container : container.navigationController;
            nav?.setNeedsStatusBarAppearanceUpdate?.();
            nav?.topViewController?.setNeedsStatusBarAppearanceUpdate?.();
        }
        catch (e) {
            Trace.write(`[StatusBar] invalidate error: ${e}`, Trace.categories.Error, Trace.messageType.warn);
        }
    }
    static updateAutoAdjustScrollInsets(controller, owner) {
        if (!__VISIONOS__ && SDK_VERSION <= 10) {
            owner._automaticallyAdjustsScrollViewInsets = false;
            // This API is deprecated, but has no alternative for <= iOS 10
            // Defaults to true and results to appliyng the insets twice together with our logic
            // for iOS 11+ we use the contentInsetAdjustmentBehavior property in scrollview
            // https://developer.apple.com/documentation/uikit/uiviewcontroller/1621372-automaticallyadjustsscrollviewin
            controller.automaticallyAdjustsScrollViewInsets = false;
        }
    }
    /**
     * This method simulates the iOS 11+ safeAreaLayoutGuide property and its constraints for older versions.
     *
     * @param controller
     * @param owner
     */
    static updateConstraints(controller, owner) {
        if (!__VISIONOS__ && SDK_VERSION <= 10) {
            if (!controller.view.safeAreaLayoutGuide) {
                IOSHelper.initLayoutGuide(controller);
            }
        }
    }
    /**
     * This method simulates the iOS 11+ safeAreaLayoutGuide property for older versions.
     *
     * @param controller
     */
    static initLayoutGuide(controller) {
        const rootView = controller.view;
        if (!rootView.safeAreaLayoutGuide) {
            const layoutGuide = UILayoutGuide.new();
            rootView.addLayoutGuide(layoutGuide);
            NSLayoutConstraint.activateConstraints([layoutGuide.topAnchor.constraintEqualToAnchor(controller.topLayoutGuide.bottomAnchor), layoutGuide.bottomAnchor.constraintEqualToAnchor(controller.bottomLayoutGuide.topAnchor), layoutGuide.leadingAnchor.constraintEqualToAnchor(rootView.leadingAnchor), layoutGuide.trailingAnchor.constraintEqualToAnchor(rootView.trailingAnchor)]);
            rootView.safeAreaLayoutGuide = layoutGuide;
        }
        return rootView.safeAreaLayoutGuide;
    }
    static layoutView(controller, owner) {
        let layoutGuide = controller.view.safeAreaLayoutGuide;
        if (!layoutGuide) {
            Trace.write(`safeAreaLayoutGuide during layout of ${owner}. Creating fallback constraints, but layout might be wrong.`, Trace.categories.Layout, Trace.messageType.error);
            layoutGuide = IOSHelper.initLayoutGuide(controller);
        }
        const safeArea = layoutGuide.layoutFrame;
        let position = IOSHelper.getPositionFromFrame(safeArea);
        const safeAreaSize = safeArea.size;
        const hasChildViewControllers = controller.childViewControllers.count > 0;
        if (hasChildViewControllers) {
            const fullscreen = controller.view.frame;
            position = IOSHelper.getPositionFromFrame(fullscreen);
        }
        const safeAreaWidth = layout.round(layout.toDevicePixels(safeAreaSize.width));
        const safeAreaHeight = layout.round(layout.toDevicePixels(safeAreaSize.height));
        const widthSpec = layout.makeMeasureSpec(safeAreaWidth, layout.EXACTLY);
        const heightSpec = layout.makeMeasureSpec(safeAreaHeight, layout.EXACTLY);
        ViewHelper.measureChild(null, owner, widthSpec, heightSpec);
        ViewHelper.layoutChild(null, owner, position.left, position.top, position.right, position.bottom);
        if (owner.parent) {
            owner.parent._layoutParent();
        }
    }
    static getPositionFromFrame(frame) {
        const left = layout.round(layout.toDevicePixels(frame.origin.x));
        const top = layout.round(layout.toDevicePixels(frame.origin.y));
        const right = layout.round(layout.toDevicePixels(frame.origin.x + frame.size.width));
        const bottom = layout.round(layout.toDevicePixels(frame.origin.y + frame.size.height));
        return { left, right, top, bottom };
    }
    static getFrameFromPosition(position, insets) {
        insets = insets || { left: 0, top: 0, right: 0, bottom: 0 };
        const left = layout.toDeviceIndependentPixels(position.left + insets.left);
        const top = layout.toDeviceIndependentPixels(position.top + insets.top);
        let width = layout.toDeviceIndependentPixels(position.right - position.left - insets.left - insets.right);
        let height = layout.toDeviceIndependentPixels(position.bottom - position.top - insets.top - insets.bottom);
        if (width < 0) {
            width = 0;
        }
        if (height < 0) {
            height = 0;
        }
        return CGRectMake(left, top, width, height);
    }
    /**
     * Returns `true` when an ancestor ScrollView has `iosContentInsetAdjustmentBehavior`
     * other than `'never'`, meaning iOS applies safe-area insets via `adjustedContentInset`.
     * `View.getSafeAreaInsets` returns empty insets in that case so nested content
     * doesn't double-count them.
     *
     * Duck-types on the property name to avoid a circular import of ScrollView.
     * The property defaults to `'never'`, so this returns `false` unless explicitly opted in.
     */
    static hasIOSManagedInsetAncestor(view) {
        let p = view.parent;
        while (p) {
            if (typeof p.iosContentInsetAdjustmentBehavior === 'string' && p.iosContentInsetAdjustmentBehavior !== 'never') {
                return true;
            }
            p = p.parent;
        }
        return false;
    }
    static shrinkToSafeArea(view, frame) {
        const insets = view.getSafeAreaInsets();
        if (insets.left || insets.top) {
            const position = IOSHelper.getPositionFromFrame(frame);
            const adjustedFrame = IOSHelper.getFrameFromPosition(position, insets);
            if (Trace.isEnabled()) {
                Trace.write(`${view} :shrinkToSafeArea: ${JSON.stringify(IOSHelper.getPositionFromFrame(adjustedFrame))}`, Trace.categories.Layout);
            }
            return adjustedFrame;
        }
        return null;
    }
    static expandBeyondSafeArea(view, frame) {
        const availableSpace = IOSHelper.getAvailableSpaceFromParent(view, frame);
        // Detached NS subtrees (e.g. TabView's `iosBottomAccessory`) have no safe-area
        // reference rects to expand against; leave the frame as-is.
        if (!availableSpace || !availableSpace.safeArea || !availableSpace.fullscreen) {
            return frame;
        }
        const safeArea = availableSpace.safeArea;
        const fullscreen = availableSpace.fullscreen;
        const inWindow = availableSpace.inWindow;
        const position = IOSHelper.getPositionFromFrame(frame);
        const safeAreaPosition = IOSHelper.getPositionFromFrame(safeArea);
        const fullscreenPosition = IOSHelper.getPositionFromFrame(fullscreen);
        const inWindowPosition = IOSHelper.getPositionFromFrame(inWindow);
        const adjustedPosition = position;
        if (position.left && inWindowPosition.left <= safeAreaPosition.left) {
            adjustedPosition.left = fullscreenPosition.left;
        }
        if (position.top && inWindowPosition.top <= safeAreaPosition.top) {
            adjustedPosition.top = fullscreenPosition.top;
        }
        if (inWindowPosition.right < fullscreenPosition.right && inWindowPosition.right >= safeAreaPosition.right + fullscreenPosition.left) {
            adjustedPosition.right += fullscreenPosition.right - inWindowPosition.right;
        }
        if (inWindowPosition.bottom < fullscreenPosition.bottom && inWindowPosition.bottom >= safeAreaPosition.bottom + fullscreenPosition.top) {
            adjustedPosition.bottom += fullscreenPosition.bottom - inWindowPosition.bottom;
        }
        const adjustedFrame = CGRectMake(layout.toDeviceIndependentPixels(adjustedPosition.left), layout.toDeviceIndependentPixels(adjustedPosition.top), layout.toDeviceIndependentPixels(adjustedPosition.right - adjustedPosition.left), layout.toDeviceIndependentPixels(adjustedPosition.bottom - adjustedPosition.top));
        if (Trace.isEnabled()) {
            Trace.write(view + ' :expandBeyondSafeArea: ' + JSON.stringify(IOSHelper.getPositionFromFrame(adjustedFrame)), Trace.categories.Layout);
        }
        return adjustedFrame;
    }
    static getAvailableSpaceFromParent(view, frame) {
        if (!view) {
            return;
        }
        let scrollView = null;
        let viewControllerView = null;
        if (view.viewController) {
            viewControllerView = view.viewController.view;
        }
        else {
            let parent = view.parent;
            while (parent && !parent.viewController && !(parent.nativeViewProtected instanceof UIScrollView)) {
                parent = parent.parent;
            }
            // `parent` is null when `view` is attached to UIKit but has no NS parent
            // (e.g. TabView's `iosBottomAccessory` hosted in UITabAccessory.contentView).
            if (parent) {
                if (parent.nativeViewProtected instanceof UIScrollView) {
                    scrollView = parent.nativeViewProtected;
                }
                else if (parent.viewController) {
                    viewControllerView = parent.viewController.view;
                }
            }
        }
        let fullscreen = null;
        let safeArea = null;
        let controllerInWindow = { x: 0, y: 0 };
        if (viewControllerView) {
            safeArea = viewControllerView.safeAreaLayoutGuide.layoutFrame;
            fullscreen = viewControllerView.frame;
            controllerInWindow = viewControllerView.convertPointToView(viewControllerView.bounds.origin, null);
        }
        else if (scrollView) {
            const insets = scrollView.safeAreaInsets;
            safeArea = CGRectMake(insets.left, insets.top, scrollView.contentSize.width - insets.left - insets.right, scrollView.contentSize.height - insets.top - insets.bottom);
            fullscreen = CGRectMake(0, 0, scrollView.contentSize.width, scrollView.contentSize.height);
        }
        // We take into account the controller position inside the window.
        // for example with a bottomsheet the controller will be "offset"
        const locationInWindow = view.getLocationInWindow();
        let inWindowLeft = locationInWindow.x - controllerInWindow.x;
        let inWindowTop = locationInWindow.y - controllerInWindow.y;
        if (scrollView) {
            inWindowLeft += scrollView.contentOffset.x;
            inWindowTop += scrollView.contentOffset.y;
        }
        const inWindow = CGRectMake(inWindowLeft, inWindowTop, frame.size.width, frame.size.height);
        return {
            safeArea: safeArea,
            fullscreen: fullscreen,
            inWindow: inWindow,
        };
    }
}
IOSHelper.traitCollectionColorAppearanceChangedEvent = 'traitCollectionColorAppearanceChanged';
IOSHelper.traitCollectionLayoutDirectionChangedEvent = 'traitCollectionLayoutDirectionChanged';
IOSHelper.UILayoutViewController = UILayoutViewController;
IOSHelper.UIAdaptivePresentationControllerDelegateImp = UIAdaptivePresentationControllerDelegateImp;
IOSHelper.UIPopoverPresentationControllerDelegateImp = UIPopoverPresentationControllerDelegateImp;
//# sourceMappingURL=index.ios.js.map