import { SplitViewBase, displayModeProperty, splitBehaviorProperty, preferredPrimaryColumnWidthFractionProperty, preferredSupplementaryColumnWidthFractionProperty, preferredInspectorColumnWidthFractionProperty, navigationBarTintColorProperty } from './split-view-common';
import { View } from '../core/view';
import { layout } from '../../utils';
import { SDK_VERSION } from '../../utils/constants';
import { FrameBase } from '../frame/frame-common';
var UISplitViewControllerDelegateImpl = (function (_super) {
    __extends(UISplitViewControllerDelegateImpl, _super);
    function UISplitViewControllerDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UISplitViewControllerDelegateImpl.initWithOwner = function (owner) {
        var d = UISplitViewControllerDelegateImpl.new();
        d._owner = owner;
        return d;
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerCollapseSecondaryViewControllerOntoPrimaryViewController = function (splitViewController, secondaryViewController, primaryViewController) {
        var owner = this._owner.deref();
        if (owner) {
            owner.onSecondaryViewCollapsed(secondaryViewController, primaryViewController);
        }
        return true;
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerDidCollapse = function (svc) {
        var owner = this._owner.deref();
        if (owner) {
            owner._invalidateAllChildLayouts();
        }
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerDidExpand = function (svc) {
        var owner = this._owner.deref();
        if (owner) {
            owner._invalidateAllChildLayouts();
        }
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerDidHideColumn = function (svc, column) {
        var owner = this._owner.deref();
        if (owner) {
            if (column === UISplitViewControllerColumn.Primary) {
                owner.primaryButtonAttached = false;
            }
            else if (column === UISplitViewControllerColumn.Inspector) {
                owner.inspectorButtonAttached = false;
            }
            owner._invalidateAllChildLayouts();
        }
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerDidShowColumn = function (svc, column) {
        var owner = this._owner.deref();
        if (owner) {
            owner._invalidateAllChildLayouts();
            if (column === UISplitViewControllerColumn.Primary) {
                owner.primaryShowing = true;
                setTimeout(function () { return owner.attachPrimaryButton(); }, 100);
            }
            else if (column === UISplitViewControllerColumn.Inspector) {
                owner.inspectorShowing = true;
                setTimeout(function () { return owner.attachInspectorButton(); }, 100);
            }
        }
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerDisplayModeForExpandingToProposedDisplayMode = function (svc, proposedDisplayMode) {
        return UISplitViewControllerDisplayMode.TwoBesideSecondary;
    };
    UISplitViewControllerDelegateImpl.prototype.splitViewControllerTopColumnForCollapsingToProposedTopColumn = function (svc, proposedTopColumn) {
        return UISplitViewControllerColumn.Secondary;
    };
    UISplitViewControllerDelegateImpl.prototype.toggleInspector = function () {
        var owner = this._owner.deref();
        if (owner) {
            if (owner.inspectorShowing) {
                owner.hideInspector();
            }
            else {
                owner.showInspector();
            }
        }
    };
    UISplitViewControllerDelegateImpl.prototype.togglePrimary = function () {
        var owner = this._owner.deref();
        if (owner) {
            if (owner.primaryShowing) {
                owner.hidePrimary();
                owner.primaryShowing = false;
            }
            else {
                owner.showPrimary();
                owner.primaryShowing = true;
            }
        }
    };
    UISplitViewControllerDelegateImpl.ObjCProtocols = [UISplitViewControllerDelegate];
    UISplitViewControllerDelegateImpl.ObjCExposedMethods = {
        toggleInspector: { returns: interop.types.void, params: [] },
        togglePrimary: { returns: interop.types.void, params: [] },
    };
    return UISplitViewControllerDelegateImpl;
}(NSObject));
export class SplitView extends SplitViewBase {
    static getInstance() {
        return SplitView.instance;
    }
    constructor() {
        super();
        // Keep role -> controller
        this._controllers = new Map();
        this._children = new Map();
        this.primaryButtonAttached = false;
        this.inspectorButtonAttached = false;
        this.inspectorShowing = false;
        this.primaryShowing = true;
        this.viewController = UISplitViewController.alloc().initWithStyle(this._getSplitStyle());
    }
    createNativeView() {
        SplitView.instance = this;
        this._delegate = UISplitViewControllerDelegateImpl.initWithOwner(new WeakRef(this));
        this.viewController.delegate = this._delegate;
        this.viewController.presentsWithGesture = true;
        // Disable automatic display mode button - we manage our own buttons
        if (this.viewController.displayModeButtonVisibility !== undefined) {
            this.viewController.displayModeButtonVisibility = 1 /* UISplitViewControllerDisplayModeButtonVisibility.Never */;
        }
        // Apply initial preferences
        this._applyPreferences();
        return this.viewController.view;
    }
    onLoaded() {
        super.onLoaded();
        // Ensure proper view controller containment
        this._ensureViewControllerContainment();
    }
    _ensureViewControllerContainment() {
        if (!this.viewController) {
            return;
        }
        const window = this.nativeViewProtected?.window;
        if (!window) {
            return;
        }
        const currentRootVC = window.rootViewController;
        // If the window's rootViewController is not our SplitViewController,
        // we need to set it up properly
        if (currentRootVC !== this.viewController) {
            // Check if we can become the root view controller
            // or if we need to be added as a child
            if (currentRootVC) {
                currentRootVC.addChildViewController(this.viewController);
                this.viewController.didMoveToParentViewController(currentRootVC);
            }
        }
    }
    disposeNativeView() {
        super.disposeNativeView();
        this._controllers.clear();
        this._children.clear();
        this.viewController = null;
        this._delegate = null;
    }
    _getSplitStyle() {
        switch (SplitView.SplitStyle) {
            case 'triple':
                return 2 /* UISplitViewControllerStyle.TripleColumn */;
            default:
                // default to double always
                return 1 /* UISplitViewControllerStyle.DoubleColumn */;
        }
    }
    // Controller-backed container: intercept native tree operations
    _addViewToNativeVisualTree(child, atIndex) {
        const role = this._resolveRoleForChild(child, atIndex);
        const controller = this._ensureControllerForChild(child);
        this._children.set(role, child);
        this._controllers.set(role, controller);
        this._syncControllers();
        return true;
    }
    _removeViewFromNativeVisualTree(child) {
        const role = this._findRoleByChild(child);
        if (role) {
            this._children.delete(role);
            this._controllers.delete(role);
            this._syncControllers();
        }
        super._removeViewFromNativeVisualTree(child);
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        const width = layout.getMeasureSpecSize(widthMeasureSpec);
        const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
        const height = layout.getMeasureSpecSize(heightMeasureSpec);
        const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
        const horizontal = this.effectivePaddingLeft + this.effectivePaddingRight + this.effectiveBorderLeftWidth + this.effectiveBorderRightWidth;
        const vertical = this.effectivePaddingTop + this.effectivePaddingBottom + this.effectiveBorderTopWidth + this.effectiveBorderBottomWidth;
        const measuredWidth = Math.max(widthMode === layout.UNSPECIFIED ? 0 : width, this.effectiveMinWidth) + (widthMode === layout.UNSPECIFIED ? horizontal : 0);
        const measuredHeight = Math.max(heightMode === layout.UNSPECIFIED ? 0 : height, this.effectiveMinHeight) + (heightMode === layout.UNSPECIFIED ? vertical : 0);
        const widthAndState = View.resolveSizeAndState(measuredWidth, width, widthMode, 0);
        const heightAndState = View.resolveSizeAndState(measuredHeight, height, heightMode, 0);
        this.setMeasuredDimension(widthAndState, heightAndState);
    }
    onRoleChanged(view, oldValue, newValue) {
        // Move child mapping to new role and resync
        const oldRole = this._findRoleByChild(view);
        if (oldRole) {
            const controller = this._controllers.get(oldRole);
            this._controllers.delete(oldRole);
            this._children.delete(oldRole);
            if (controller) {
                this._controllers.set(newValue, controller);
            }
            this._children.set(newValue, view);
            this._syncControllers();
        }
    }
    onSecondaryViewCollapsed(secondaryViewController, primaryViewController) {
        // Default implementation: do nothing.
        // Subclasses may override to customize behavior when secondary is collapsed onto primary.
    }
    showPrimary() {
        if (!this.viewController)
            return;
        this.viewController.showColumn(0 /* UISplitViewControllerColumn.Primary */);
        this._invalidateAllChildLayouts();
        // Attach button after a short delay to ensure the column is visible
        setTimeout(() => this.attachPrimaryButton(), 100);
    }
    hidePrimary() {
        if (!this.viewController)
            return;
        this.viewController.hideColumn(0 /* UISplitViewControllerColumn.Primary */);
        this.primaryButtonAttached = false;
        this._invalidateAllChildLayouts();
    }
    showSecondary() {
        if (!this.viewController)
            return;
        this.viewController.showColumn(2 /* UISplitViewControllerColumn.Secondary */);
        this._invalidateAllChildLayouts();
    }
    hideSecondary() {
        if (!this.viewController)
            return;
        this.viewController.hideColumn(2 /* UISplitViewControllerColumn.Secondary */);
        this._invalidateAllChildLayouts();
    }
    showSupplementary() {
        if (!this.viewController)
            return;
        this.viewController.showColumn(1 /* UISplitViewControllerColumn.Supplementary */);
        this._invalidateAllChildLayouts();
    }
    showInspector() {
        if (!this.viewController)
            return;
        // Guard for older OS versions by feature-detecting inspector-related API
        if (this.viewController.preferredInspectorColumnWidthFraction !== undefined) {
            this.viewController.showColumn(4 /* UISplitViewControllerColumn.Inspector */);
            this.notifyInspectorChange(true);
            this._invalidateAllChildLayouts();
            // Attach button after a short delay to ensure the column is visible
            setTimeout(() => this.attachInspectorButton(), 100);
        }
    }
    hideInspector() {
        if (!this.viewController)
            return;
        if (this.viewController.preferredInspectorColumnWidthFraction !== undefined) {
            this.viewController.hideColumn(4 /* UISplitViewControllerColumn.Inspector */);
            this.inspectorButtonAttached = false;
            this.notifyInspectorChange(false);
            this._invalidateAllChildLayouts();
        }
    }
    notifyInspectorChange(showing) {
        this.inspectorShowing = showing;
        this.notify({
            eventName: 'inspectorChange',
            object: this,
            data: { showing },
        });
    }
    invalidateChildLayouts(delay = 0) {
        const refreshLayouts = () => {
            for (const [role, child] of this._children.entries()) {
                if (child && child.requestLayout) {
                    child.requestLayout();
                }
                // Also trigger layout on the native view
                if (child && child.nativeViewProtected) {
                    child.nativeViewProtected.setNeedsLayout();
                    child.nativeViewProtected.layoutIfNeeded();
                }
                // If it's a Frame, also request layout on its current page
                if (child?.currentPage?.requestLayout) {
                    child.currentPage.requestLayout();
                    if (child.currentPage.nativeViewProtected) {
                        child.currentPage.nativeViewProtected.setNeedsLayout();
                        child.currentPage.nativeViewProtected.layoutIfNeeded();
                    }
                }
            }
            // Also request layout on the SplitView itself
            this.requestLayout();
            if (this.nativeViewProtected) {
                this.nativeViewProtected.setNeedsLayout();
                this.nativeViewProtected.layoutIfNeeded();
            }
        };
        if (delay > 0) {
            setTimeout(refreshLayouts, delay);
        }
        else {
            refreshLayouts();
        }
    }
    _invalidateAllChildLayouts() {
        // Call after animation typically completes to ensure native layout pass has finished
        this.invalidateChildLayouts(350);
    }
    _resolveRoleForChild(child, atIndex) {
        const explicit = SplitViewBase.getRole(child);
        if (explicit) {
            return explicit;
        }
        // Fallback by index if no explicit role set
        return this._roleByIndex(atIndex);
    }
    _findRoleByChild(child) {
        for (const [role, c] of this._children.entries()) {
            if (c === child) {
                return role;
            }
        }
        return null;
    }
    _ensureControllerForChild(child) {
        // If child is controller-backed (Page/Frame/etc.), reuse its controller
        const vc = (child.ios instanceof UIViewController ? child.ios : child.viewController);
        if (vc) {
            return vc;
        }
        // Fallback: basic wrapper (not expected in current usage where children are Frames/Pages)
        const wrapper = UIViewController.new();
        if (!wrapper.view) {
            wrapper.view = UIView.new();
        }
        if (child.nativeViewProtected) {
            wrapper.view.addSubview(child.nativeViewProtected);
        }
        return wrapper;
    }
    _attachSecondaryDisplayModeButton() {
        const secondary = this._controllers.get('secondary');
        if (!(secondary instanceof UINavigationController)) {
            return;
        }
        const targetVC = secondary.topViewController;
        if (!targetVC) {
            // Subscribe to Frame's navigatedTo event to know when the first page is shown
            const frameChild = this._children.get('secondary');
            if (frameChild && frameChild.on && !frameChild._splitViewSecondaryNavigatedHandler) {
                frameChild._splitViewSecondaryNavigatedHandler = () => {
                    // Use setTimeout to ensure the navigation controller's topViewController is updated
                    setTimeout(() => this._attachSecondaryDisplayModeButton(), 0);
                };
                frameChild.on(FrameBase.navigatedToEvent, frameChild._splitViewSecondaryNavigatedHandler);
            }
            return;
        }
        // Avoid duplicates
        if (targetVC.navigationItem.leftBarButtonItem) {
            return;
        }
        // Set the displayModeButtonItem on the page's navigationItem
        targetVC.navigationItem.leftBarButtonItem = this.viewController.displayModeButtonItem;
        targetVC.navigationItem.leftItemsSupplementBackButton = true;
    }
    attachPrimaryButton() {
        if (this.primaryButtonAttached) {
            return;
        }
        const primary = this._controllers.get('primary');
        if (!(primary instanceof UINavigationController)) {
            return;
        }
        const targetVC = primary.topViewController;
        if (!targetVC) {
            // Subscribe to Frame's navigatedTo event to know when the first page is shown
            const frameChild = this._children.get('primary');
            if (frameChild && frameChild.on && !frameChild._splitViewPrimaryNavigatedHandler) {
                frameChild._splitViewPrimaryNavigatedHandler = () => {
                    // Use setTimeout to ensure the navigation controller's topViewController is updated
                    setTimeout(() => this.attachPrimaryButton(), 0);
                };
                frameChild.on(FrameBase.navigatedToEvent, frameChild._splitViewPrimaryNavigatedHandler);
            }
            return;
        }
        // Set the navigation bar tint color for the primary column
        if (primary.navigationBar && this.navigationBarTintColor) {
            primary.navigationBar.tintColor = this.navigationBarTintColor.ios;
        }
        // Add a sidebar button to primary column matching the inspector style
        const cfg = UIImageSymbolConfiguration.configurationWithPointSizeWeightScale(18, 4 /* UIImageSymbolWeight.Regular */, 2 /* UIImageSymbolScale.Medium */);
        const image = UIImage.systemImageNamedWithConfiguration('sidebar.leading', cfg);
        const item = UIBarButtonItem.alloc().initWithImageStyleTargetAction(image, 0 /* UIBarButtonItemStyle.Plain */, this._delegate, 'togglePrimary');
        if (this.navigationBarTintColor) {
            item.tintColor = this.navigationBarTintColor.ios;
        }
        // Use rightBarButtonItems array to ensure we control exactly what's shown
        targetVC.navigationItem.rightBarButtonItems = NSArray.arrayWithObject(item);
        this.primaryButtonAttached = true;
    }
    attachInspectorButton() {
        if (this.inspectorButtonAttached) {
            return;
        }
        const inspector = this._controllers.get('inspector');
        if (!(inspector instanceof UINavigationController)) {
            return;
        }
        const targetVC = inspector.topViewController;
        if (!targetVC) {
            // Subscribe to Frame's navigatedTo event to know when the first page is shown
            const frameChild = this._children.get('inspector');
            if (frameChild && frameChild.on && !frameChild._splitViewNavigatedHandler) {
                frameChild._splitViewNavigatedHandler = () => {
                    // Use setTimeout to ensure the navigation controller's topViewController is updated
                    setTimeout(() => this.attachInspectorButton(), 100);
                };
                frameChild.on(FrameBase.navigatedToEvent, frameChild._splitViewNavigatedHandler);
            }
            return;
        }
        // Set the navigation bar tint color for the inspector column
        if (inspector.navigationBar && this.navigationBarTintColor) {
            inspector.navigationBar.tintColor = this.navigationBarTintColor.ios;
        }
        // Note: could provide properties to customize this
        const cfg = UIImageSymbolConfiguration.configurationWithPointSizeWeightScale(18, 4 /* UIImageSymbolWeight.Regular */, 2 /* UIImageSymbolScale.Medium */);
        const image = UIImage.systemImageNamedWithConfiguration('sidebar.trailing', cfg);
        const item = UIBarButtonItem.alloc().initWithImageStyleTargetAction(image, 0 /* UIBarButtonItemStyle.Plain */, this._delegate, 'toggleInspector');
        if (this.navigationBarTintColor) {
            item.tintColor = this.navigationBarTintColor.ios;
        }
        targetVC.navigationItem.rightBarButtonItem = item;
        this.inspectorButtonAttached = true;
    }
    _syncControllers() {
        if (!this.viewController) {
            return;
        }
        // Prefer modern API if present; otherwise fall back to setting viewControllers array
        const primary = this._controllers.get('primary');
        const secondary = this._controllers.get('secondary');
        const supplementary = this._controllers.get('supplementary');
        const inspector = this._controllers.get('inspector');
        if (primary) {
            this.viewController.setViewControllerForColumn(primary, 0 /* UISplitViewControllerColumn.Primary */);
        }
        if (secondary) {
            this.viewController.setViewControllerForColumn(secondary, 2 /* UISplitViewControllerColumn.Secondary */);
        }
        if (supplementary) {
            this.viewController.setViewControllerForColumn(supplementary, 1 /* UISplitViewControllerColumn.Supplementary */);
        }
        if (inspector) {
            if (this.viewController.preferredInspectorColumnWidthFraction !== undefined) {
                this.viewController.setViewControllerForColumn(inspector, 4 /* UISplitViewControllerColumn.Inspector */);
            }
        }
        this._applyPreferences();
    }
    _applyPreferences() {
        if (!this.viewController) {
            return;
        }
        // displayMode
        let preferredDisplayMode = 0 /* UISplitViewControllerDisplayMode.Automatic */;
        switch (this.displayMode) {
            case 'secondaryOnly':
                preferredDisplayMode = 1 /* UISplitViewControllerDisplayMode.SecondaryOnly */;
                break;
            case 'oneBesideSecondary':
                preferredDisplayMode = 2 /* UISplitViewControllerDisplayMode.OneBesideSecondary */;
                break;
            case 'oneOverSecondary':
                preferredDisplayMode = 3 /* UISplitViewControllerDisplayMode.OneOverSecondary */;
                break;
            case 'twoBesideSecondary':
                preferredDisplayMode = 4 /* UISplitViewControllerDisplayMode.TwoBesideSecondary */;
                break;
            case 'twoOverSecondary':
                preferredDisplayMode = 5 /* UISplitViewControllerDisplayMode.TwoOverSecondary */;
                break;
            case 'twoDisplaceSecondary':
                preferredDisplayMode = 6 /* UISplitViewControllerDisplayMode.TwoDisplaceSecondary */;
                break;
        }
        this.viewController.preferredDisplayMode = preferredDisplayMode;
        // splitBehavior (iOS 14+)
        const sb = this.splitBehavior;
        let preferredSplitBehavior = 0 /* UISplitViewControllerSplitBehavior.Automatic */;
        switch (sb) {
            case 'tile':
                preferredSplitBehavior = 1 /* UISplitViewControllerSplitBehavior.Tile */;
                break;
            case 'overlay':
                preferredSplitBehavior = 2 /* UISplitViewControllerSplitBehavior.Overlay */ ?? 0 /* UISplitViewControllerSplitBehavior.Automatic */;
                break;
            case 'displace':
                preferredSplitBehavior = 3 /* UISplitViewControllerSplitBehavior.Displace */ ?? 0 /* UISplitViewControllerSplitBehavior.Automatic */;
                break;
        }
        this.viewController.preferredSplitBehavior = preferredSplitBehavior;
        const primary = this._controllers.get('primary');
        const secondary = this._controllers.get('secondary');
        const supplementary = this._controllers.get('supplementary');
        const inspector = this._controllers.get('inspector');
        if (secondary instanceof UINavigationController) {
            this._attachSecondaryDisplayModeButton();
        }
        if (primary instanceof UINavigationController) {
            this.attachPrimaryButton();
        }
        if (supplementary) {
            this.showSupplementary();
        }
        if (inspector) {
            this.showInspector();
        }
        // Width fractions
        if (typeof this.preferredPrimaryColumnWidthFraction === 'number' && !isNaN(this.preferredPrimaryColumnWidthFraction)) {
            this.viewController.preferredPrimaryColumnWidthFraction = this.preferredPrimaryColumnWidthFraction;
        }
        if (SplitView.SplitStyle === 'triple') {
            // supplementary applies in triple style
            if (typeof this.preferredSupplementaryColumnWidthFraction === 'number' && !isNaN(this.preferredSupplementaryColumnWidthFraction)) {
                this.viewController.preferredSupplementaryColumnWidthFraction = this.preferredSupplementaryColumnWidthFraction;
            }
        }
        if (SDK_VERSION >= 26) {
            // Inspector width fraction
            const inspectorWidth = this.preferredInspectorColumnWidthFraction;
            if (typeof inspectorWidth === 'number' && !isNaN(inspectorWidth)) {
                this.viewController.preferredInspectorColumnWidthFraction = inspectorWidth;
            }
        }
    }
    [displayModeProperty.setNative](value) {
        this._applyPreferences();
    }
    [splitBehaviorProperty.setNative](value) {
        this._applyPreferences();
    }
    [preferredPrimaryColumnWidthFractionProperty.setNative](value) {
        this._applyPreferences();
    }
    [preferredSupplementaryColumnWidthFractionProperty.setNative](value) {
        this._applyPreferences();
    }
    [preferredInspectorColumnWidthFractionProperty.setNative](value) {
        this._applyPreferences();
    }
    [navigationBarTintColorProperty.setNative](value) {
        this._applyPreferences();
    }
}
//# sourceMappingURL=index.ios.js.map