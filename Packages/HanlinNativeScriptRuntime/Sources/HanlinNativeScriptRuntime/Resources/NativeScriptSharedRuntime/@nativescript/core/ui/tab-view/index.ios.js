const __VISIONOS__ = globalThis.__VISIONOS__ !== undefined ? globalThis.__VISIONOS__ : false;
import { Font } from '../styling/font';
import { IOSHelper, View } from '../core/view';
import { TabViewBase, TabViewItemBase, itemsProperty, selectedIndexProperty, tabTextColorProperty, tabTextFontSizeProperty, tabBackgroundColorProperty, selectedTabTextColorProperty, iosIconRenderingModeProperty, traceMissingIcon, iosBottomAccessoryProperty, iosTabBarMinimizeBehaviorProperty } from './tab-view-common';
import { Color } from '../../color';
import { Trace } from '../../trace';
import { fontInternalProperty } from '../styling/style-properties';
import { textTransformProperty, getTransformedText } from '../text-base';
import { ImageSource } from '../../image-source';
import { profile } from '../../profiling';
import { Frame } from '../frame';
import { SharedTransition } from '../transition/shared-transition';
import { layout } from '../../utils/layout-helper';
import { FONT_PREFIX, isFontIconURI, isSystemURI, SYSTEM_PREFIX } from '../../utils/common';
import { SDK_VERSION } from '../../utils/constants';
import { Device, Screen } from '../../platform';
export * from './tab-view-common';
var UITabBarControllerImpl = (function (_super) {
    __extends(UITabBarControllerImpl, _super);
    function UITabBarControllerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITabBarControllerImpl.initWithOwner = function (owner) {
        var handler = UITabBarControllerImpl.new();
        handler._owner = owner;
        return handler;
    };
    UITabBarControllerImpl.prototype.viewDidLoad = function () {
        _super.prototype.viewDidLoad.call(this);
        this.extendedLayoutIncludesOpaqueBars = true;
        if (SDK_VERSION >= 18) {
            try { this.mode = 2; } catch (e) {}
        }
    };
    UITabBarControllerImpl.prototype.viewWillAppear = function (animated) {
        var _a;
        _super.prototype.viewWillAppear.call(this, animated);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            return;
        }
        IOSHelper.updateAutoAdjustScrollInsets(this, owner);
        if (!owner.parent) {
            owner.callLoaded();
        }
    };
    UITabBarControllerImpl.prototype.viewDidDisappear = function (animated) {
        var _a;
        _super.prototype.viewDidDisappear.call(this, animated);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && !owner.parent && owner.isLoaded && !this.presentedViewController) {
            owner.callUnloaded();
        }
    };
    UITabBarControllerImpl.prototype.viewWillTransitionToSizeWithTransitionCoordinator = function (size, coordinator) {
        var _this = this;
        _super.prototype.viewWillTransitionToSizeWithTransitionCoordinator.call(this, size, coordinator);
        coordinator.animateAlongsideTransitionCompletion(null, function () {
            var _a;
            var owner = (_a = _this._owner) === null || _a === void 0 ? void 0 : _a.deref();
            if (owner && owner.items) {
                owner.items.forEach(function (tabItem) { return tabItem._updateTitleAndIconPositions(); });
            }
        });
    };
    UITabBarControllerImpl.prototype.traitCollectionDidChange = function (previousTraitCollection) {
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
    __decorate([
        profile
    ], UITabBarControllerImpl.prototype, "viewWillAppear", null);
    __decorate([
        profile
    ], UITabBarControllerImpl.prototype, "viewDidDisappear", null);
    return UITabBarControllerImpl;
}(UITabBarController));
var UITabBarControllerDelegateImpl = (function (_super) {
    __extends(UITabBarControllerDelegateImpl, _super);
    function UITabBarControllerDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITabBarControllerDelegateImpl.initWithOwner = function (owner) {
        var delegate = UITabBarControllerDelegateImpl.new();
        delegate._owner = owner;
        return delegate;
    };
    UITabBarControllerDelegateImpl.prototype.tabBarControllerShouldSelectViewController = function (tabBarController, viewController) {
        var _a;
        if (Trace.isEnabled()) {
            Trace.write("TabView.delegate.SHOULD_select(" + tabBarController + ", " + viewController + ");", Trace.categories.Debug);
        }
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner._handleTwoNavigationBars(false);
        }
        if (tabBarController.selectedViewController === viewController) {
            return false;
        }
        return true;
    };
    UITabBarControllerDelegateImpl.prototype.tabBarControllerDidSelectViewController = function (tabBarController, viewController) {
        var _a;
        if (Trace.isEnabled()) {
            Trace.write("TabView.delegate.DID_select(" + tabBarController + ", " + viewController + ");", Trace.categories.Debug);
        }
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var moreNav = tabBarController.moreNavigationController;
            if (moreNav && owner.moreNavigationControllerDelegate && moreNav.delegate !== owner.moreNavigationControllerDelegate) {
                moreNav.delegate = owner.moreNavigationControllerDelegate;
            }
            owner._onViewControllerShown(tabBarController, viewController);
        }
    };
    UITabBarControllerDelegateImpl.ObjCProtocols = [UITabBarControllerDelegate];
    return UITabBarControllerDelegateImpl;
}(NSObject));
var UINavigationControllerDelegateImpl = (function (_super) {
    __extends(UINavigationControllerDelegateImpl, _super);
    function UINavigationControllerDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UINavigationControllerDelegateImpl.initWithOwner = function (owner) {
        var delegate = UINavigationControllerDelegateImpl.new();
        delegate._owner = owner;
        return delegate;
    };
    UINavigationControllerDelegateImpl.prototype.navigationControllerWillShowViewControllerAnimated = function (navigationController, viewController, animated) {
        var _a, _b, _c;
        if (Trace.isEnabled()) {
            Trace.write("TabView.moreNavigationController.WILL_show(" + navigationController + ", " + viewController + ", " + animated + ");", Trace.categories.Debug);
        }
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var backToMoreWillBeVisible = (_c = (_b = navigationController.tabBarController) === null || _b === void 0 ? void 0 : _b.viewControllers) === null || _c === void 0 ? void 0 : _c.containsObject(viewController);
            owner._handleTwoNavigationBars(backToMoreWillBeVisible);
        }
    };
    UINavigationControllerDelegateImpl.prototype.navigationControllerDidShowViewControllerAnimated = function (navigationController, viewController, animated) {
        var _a, _b, _c;
        if (Trace.isEnabled()) {
            Trace.write("TabView.moreNavigationController.DID_show(" + navigationController + ", " + viewController + ", " + animated + ");", Trace.categories.Debug);
        }
        navigationController.navigationBar.topItem.rightBarButtonItem = null;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner._onViewControllerShown(navigationController.tabBarController, viewController);
            (_b = viewController === null || viewController === void 0 ? void 0 : viewController.view) === null || _b === void 0 ? void 0 : _b.setNeedsLayout();
            (_c = viewController === null || viewController === void 0 ? void 0 : viewController.view) === null || _c === void 0 ? void 0 : _c.layoutIfNeeded();
        }
    };
    UINavigationControllerDelegateImpl.ObjCProtocols = [UINavigationControllerDelegate];
    return UINavigationControllerDelegateImpl;
}(NSObject));
function updateTitleAndIconPositions(tabItem, tabBarItem, controller) {
    if (!tabItem || !tabBarItem) {
        return;
    }
    // For iOS <11 icon is *always* above the text.
    // For iOS 11 icon is above the text *only* on phones in portrait mode.
    const orientation = controller.interfaceOrientation;
    const isPortrait = orientation !== 4 /* UIInterfaceOrientation.LandscapeLeft */ && orientation !== 3 /* UIInterfaceOrientation.LandscapeRight */;
    const isIconAboveTitle = (!__VISIONOS__ && SDK_VERSION < 11) || (Device.deviceType === 'Phone' && isPortrait);
    if (!tabItem.iconSource) {
        if (isIconAboveTitle) {
            tabBarItem.titlePositionAdjustment = {
                horizontal: 0,
                vertical: -20,
            };
        }
        else {
            tabBarItem.titlePositionAdjustment = { horizontal: 0, vertical: 0 };
        }
    }
    if (!tabItem.title) {
        if (isIconAboveTitle) {
            tabBarItem.imageInsets = new UIEdgeInsets({
                top: 6,
                left: 0,
                bottom: -6,
                right: 0,
            });
        }
        else {
            tabBarItem.imageInsets = new UIEdgeInsets({
                top: 0,
                left: 0,
                bottom: 0,
                right: 0,
            });
        }
    }
}
export class TabViewItem extends TabViewItemBase {
    setViewController(controller, nativeView) {
        this.__controller = controller;
        this.setNativeView(nativeView);
    }
    disposeNativeView() {
        this.__controller = undefined;
        this.canBeLoaded = false;
        this.setNativeView(undefined);
    }
    loadView(view) {
        const tabView = this.parent;
        if (tabView && tabView.items) {
            const index = tabView.items.indexOf(this);
            if (index === tabView.selectedIndex) {
                super.loadView(view);
            }
        }
    }
    _update() {
        const parent = this.parent;
        const controller = this.__controller;
        if (parent && controller) {
            const icon = parent._getIcon(this);
            const index = parent.items.indexOf(this);
            const title = getTransformedText(this.title, this.style.textTransform);
            if (SDK_VERSION >= 18) {
                // iOS 18+: use UITab instead of UITabBarItem.
                // The UITab instances are created and managed at the TabView level,
                // so here we just update the corresponding tab for this controller.
                const identifier = `${index}`;
                const tabController = parent.viewController;
                try {
                    const tab = tabController.tabForIdentifier(identifier);
                    if (tab) {
                        tab.title = title;
                        tab.image = icon;
                    }
                }
                catch (e) {
                    // Fallback: if tabForIdentifier is not available for some reason,
                    // do not crash – rely on existing tab configuration.
                }
                const tabBarItem = UITabBarItem.alloc().initWithTitleImageTag(title, icon, index);
                updateTitleAndIconPositions(this, tabBarItem, controller);
                controller.tabBarItem = tabBarItem;
            }
            else {
                // iOS < 18: keep using UITabBarItem-based configuration.
                const tabBarItem = UITabBarItem.alloc().initWithTitleImageTag(title, icon, index);
                updateTitleAndIconPositions(this, tabBarItem, controller);
                // There is no need to request title styles update here in newer versions as styling is handled by bar appearance instance
                if (!__VISIONOS__ && SDK_VERSION < 15) {
                    // TODO: Repeating code. Make TabViewItemBase - ViewBase and move the colorProperty on tabViewItem.
                    // Delete the repeating code.
                    const states = getTitleAttributesForStates(parent);
                    applyStatesToItem(tabBarItem, states);
                }
                controller.tabBarItem = tabBarItem;
            }
        }
    }
    _updateTitleAndIconPositions() {
        // UITab-based configuration (iOS 18+) does not expose the same per-item
        // title/icon positioning APIs as UITabBarItem, so we only adjust
        // positions when using the legacy UITabBarItem setup.
        if (SDK_VERSION >= 18 || !this.__controller || !this.__controller.tabBarItem) {
            return;
        }
        updateTitleAndIconPositions(this, this.__controller.tabBarItem, this.__controller);
    }
    [textTransformProperty.setNative](value) {
        this._update();
    }
}
export class TabView extends TabViewBase {
    constructor() {
        super();
        this._iconsCache = {};
        this.viewController = this._ios = UITabBarControllerImpl.initWithOwner(new WeakRef(this));
    }
    createNativeView() {
        // View controller can be disposed during view disposal, so make sure to create a new one if not defined
        if (!this._ios) {
            this.viewController = this._ios = UITabBarControllerImpl.initWithOwner(new WeakRef(this));
        }
        return this._ios.view;
    }
    initNativeView() {
        super.initNativeView();
        this._delegate = UITabBarControllerDelegateImpl.initWithOwner(new WeakRef(this));
        this.moreNavigationControllerDelegate = UINavigationControllerDelegateImpl.initWithOwner(new WeakRef(this));
    }
    disposeNativeView() {
        this._delegate = null;
        this.moreNavigationControllerDelegate = null;
        this.viewController = null;
        this._ios = null;
        super.disposeNativeView();
    }
    onLoaded() {
        super.onLoaded();
        const selectedIndex = this.selectedIndex;
        const selectedView = this.items && this.items[selectedIndex] && this.items[selectedIndex].view;
        if (selectedView instanceof Frame) {
            selectedView._pushInFrameStackRecursive();
        }
        if (this._ios) {
            this._ios.delegate = this._delegate;
        }
        // Re-apply bottom accessory if set
        if (this.iosBottomAccessory) {
            this._applyBottomAccessory(this.iosBottomAccessory, false);
        }
    }
    onUnloaded() {
        if (this._ios) {
            this._ios.delegate = null;
            if (this._ios.moreNavigationController) {
                this._ios.moreNavigationController.delegate = null;
            }
        }
        // Avoid retaining custom view when unloading
        this._applyBottomAccessory(null, false);
        super.onUnloaded();
    }
    // @ts-ignore
    get ios() {
        return this._ios;
    }
    layoutNativeView(left, top, right, bottom) {
        //
    }
    _setNativeViewFrame(nativeView, frame) {
        if (nativeView) {
            nativeView.frame = frame;
        }
    }
    onSelectedIndexChanged(oldIndex, newIndex) {
        const items = this.items;
        if (!items) {
            return;
        }
        const oldItem = items[oldIndex];
        if (oldItem) {
            oldItem.unloadView(oldItem.view);
        }
        const newItem = items[newIndex];
        if (newItem && this.isLoaded) {
            const selectedView = items[newIndex].view;
            if (selectedView instanceof Frame) {
                selectedView._pushInFrameStackRecursive();
            }
            newItem.loadView(newItem.view);
        }
        super.onSelectedIndexChanged(oldIndex, newIndex);
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
    _onViewControllerShown(tabBarController, viewController) {
        // This method could be called with the moreNavigationController or its list controller, so we have to check.
        if (Trace.isEnabled()) {
            Trace.write('TabView._onViewControllerShown(' + viewController + ');', Trace.categories.Debug);
        }
        if (tabBarController?.viewControllers && tabBarController.viewControllers.containsObject(viewController)) {
            this.selectedIndex = tabBarController.viewControllers.indexOfObject(viewController);
        }
        else {
            if (Trace.isEnabled()) {
                Trace.write('TabView._onViewControllerShown: viewController is not one of our viewControllers', Trace.categories.Debug);
            }
        }
    }
    _handleTwoNavigationBars(backToMoreWillBeVisible) {
        if (Trace.isEnabled()) {
            Trace.write(`TabView._handleTwoNavigationBars(backToMoreWillBeVisible: ${backToMoreWillBeVisible})`, Trace.categories.Debug);
        }
        // The "< Back" and "< More" navigation bars should not be visible simultaneously.
        let page = this.page || this._selectedView?.page;
        if (!page && this._selectedView instanceof Frame) {
            page = this._selectedView.currentPage;
        }
        if (!page || !page.frame) {
            return;
        }
        const actionBarVisible = page.frame._getNavBarVisible(page);
        if (backToMoreWillBeVisible && actionBarVisible) {
            if (page.frame.ios) {
                page.frame.ios._disableNavBarAnimation = true;
                page.actionBarHidden = true;
                page.frame.ios._disableNavBarAnimation = false;
            }
            else {
                page.actionBarHidden = true;
            }
            this._actionBarHiddenByTabView = true;
            if (Trace.isEnabled()) {
                Trace.write(`TabView hid action bar`, Trace.categories.Debug);
            }
            return;
        }
        if (!backToMoreWillBeVisible && this._actionBarHiddenByTabView) {
            if (page.frame.ios) {
                page.frame.ios._disableNavBarAnimation = true;
                page.actionBarHidden = false;
                page.frame.ios._disableNavBarAnimation = false;
            }
            else {
                page.actionBarHidden = false;
            }
            this._actionBarHiddenByTabView = undefined;
            if (Trace.isEnabled()) {
                Trace.write(`TabView restored action bar`, Trace.categories.Debug);
            }
            return;
        }
    }
    getViewController(item) {
        let newController = item.view ? item.view.viewController : null;
        if (newController) {
            item.setViewController(newController, newController.view);
            return newController;
        }
        if (item.view.ios instanceof UIViewController) {
            newController = item.view.ios;
            item.setViewController(newController, newController.view);
        }
        else if (item.view.ios && item.view.ios.controller instanceof UIViewController) {
            newController = item.view.ios.controller;
            item.setViewController(newController, newController.view);
        }
        else {
            newController = IOSHelper.UILayoutViewController.initWithOwner(new WeakRef(item.view));
            newController.view.addSubview(item.view.nativeViewProtected);
            item.view.viewController = newController;
            item.setViewController(newController, item.view.nativeViewProtected);
        }
        return newController;
    }
    setViewControllers(items) {
        const length = items ? items.length : 0;
        if (length === 0) {
            if (SDK_VERSION >= 18) {
                // Clear tabs on iOS 18+ when there are no items.
                try {
                    this._ios.tabs = NSArray.arrayWithArray([]);
                }
                catch (e) {
                    // Fallback if tabs API is unavailable for some reason.
                    this._ios.viewControllers = null;
                }
            }
            else {
                this._ios.viewControllers = null;
            }
            return;
        }
        if (SDK_VERSION >= 18) {
            // iOS 18+: build UITab instances and assign them to the controller.
            const tabs = [];
            const controllers = [];
            items.forEach((item, i) => {
                const controller = this.getViewController(item);
                controllers.push(controller);
                const icon = this._getIcon(item);
                const title = item.title || '';
                const identifier = `${i}`;
                let tab;
                if (item.role === 'search') {
                    tab = UISearchTab.alloc().initWithTitleImageIdentifierViewControllerProvider(title, icon, identifier, (t) => {
                        return controller;
                    });
                }
                else {
                    tab = UITab.alloc().initWithTitleImageIdentifierViewControllerProvider(title, icon, identifier, (t) => {
                        return controller;
                    });
                }
                const tabBarItem = UITabBarItem.alloc().initWithTitleImageTag(title, icon, i);
                updateTitleAndIconPositions(item, tabBarItem, controller);
                controller.tabBarItem = tabBarItem;
                tabs.push(tab);
                item.canBeLoaded = true;
            });
            try {
                this._ios.mode = 2;
            } catch (e) {}
            try {
                // Prefer animated setter when available.
                this._ios.tabs = NSArray.arrayWithArray(tabs);
            }
            catch (e) { }
            this._ios.viewControllers = NSArray.arrayWithArray(controllers);
            this._ios.customizableViewControllers = null;
        }
        else {
            // iOS < 18: keep using UITabBarItem-based configuration.
            const controllers = [];
            const states = getTitleAttributesForStates(this);
            items.forEach((item, i) => {
                const controller = this.getViewController(item);
                const icon = this._getIcon(item);
                const tabBarItem = UITabBarItem.alloc().initWithTitleImageTag(item.title || '', icon, i);
                updateTitleAndIconPositions(item, tabBarItem, controller);
                if (!__VISIONOS__ && SDK_VERSION < 15) {
                    applyStatesToItem(tabBarItem, states);
                }
                controller.tabBarItem = tabBarItem;
                controllers.push(controller);
                item.canBeLoaded = true;
            });
            if (SDK_VERSION >= 15) {
                this.updateBarItemAppearance(this._ios.tabBar, states);
            }
            this._ios.viewControllers = NSArray.arrayWithArray(controllers);
            this._ios.customizableViewControllers = null;
        }
        // When we set this._ios.viewControllers, someone is clearing the moreNavigationController.delegate, so we have to reassign it each time here.
        if (this._ios.moreNavigationController) {
            this._ios.moreNavigationController.delegate = this.moreNavigationControllerDelegate;
        }
    }
    _getIconRenderingMode() {
        switch (this.iosIconRenderingMode) {
            case 'alwaysOriginal':
                return 1 /* UIImageRenderingMode.AlwaysOriginal */;
            case 'alwaysTemplate':
                return 2 /* UIImageRenderingMode.AlwaysTemplate */;
            case 'automatic':
            default:
                return 0 /* UIImageRenderingMode.Automatic */;
        }
    }
    _getIcon(item) {
        if (!item || !item.iconSource) {
            return null;
        }
        let image = this._iconsCache[item.iconSource];
        if (!image) {
            let is;
            if (isSystemURI(item.iconSource)) {
                is = ImageSource.fromSystemImageSync(item.iconSource.slice(SYSTEM_PREFIX.length));
            }
            else if (isFontIconURI(item.iconSource)) {
                // Allow specifying a separate font family for the icon via style.iconFontFamily.
                // If provided, construct a Font from the family and (optionally) size from fontInternal.
                let iconFont = item.style.fontInternal;
                const iconFontFamily = item.iconFontFamily || item.style.iconFontFamily;
                if (iconFontFamily) {
                    // Preserve size/style from existing fontInternal if present.
                    const baseFont = item.style.fontInternal || Font.default;
                    iconFont = baseFont.withFontFamily(iconFontFamily);
                }
                is = ImageSource.fromFontIconCodeSync(item.iconSource.slice(FONT_PREFIX.length), iconFont, item.style.color);
            }
            else {
                is = ImageSource.fromFileOrResourceSync(item.iconSource);
            }
            if (is && is.ios) {
                const originalRenderedImage = is.ios.imageWithRenderingMode(this._getIconRenderingMode());
                this._iconsCache[item.iconSource] = originalRenderedImage;
                image = originalRenderedImage;
            }
            else {
                traceMissingIcon(item.iconSource);
            }
        }
        return image;
    }
    _updateIOSTabBarColorsAndFonts() {
        if (!this.items) {
            return;
        }
        const tabBar = this.ios.tabBar;
        const states = getTitleAttributesForStates(this);
        if (SDK_VERSION >= 15) {
            this.updateBarItemAppearance(tabBar, states);
        }
        else {
            for (let i = 0; i < tabBar.items.count; i++) {
                applyStatesToItem(tabBar.items[i], states);
            }
        }
    }
    updateBarItemAppearance(tabBar, states) {
        const appearance = this._getAppearance(tabBar);
        const itemAppearances = ['stackedLayoutAppearance', 'inlineLayoutAppearance', 'compactInlineLayoutAppearance'];
        for (const itemAppearance of itemAppearances) {
            appearance[itemAppearance].normal.titleTextAttributes = states.normalState;
            appearance[itemAppearance].selected.titleTextAttributes = states.selectedState;
        }
        this._updateAppearance(tabBar, appearance);
    }
    _getAppearance(tabBar) {
        if (tabBar.standardAppearance == null) {
            const appearance = UITabBarAppearance.new();
            appearance.stackedLayoutAppearance = appearance.inlineLayoutAppearance = appearance.compactInlineLayoutAppearance = UITabBarItemAppearance.new();
            return appearance;
        }
        return tabBar.standardAppearance;
    }
    _updateAppearance(tabBar, appearance) {
        tabBar.standardAppearance = appearance;
        if (SDK_VERSION >= 15) {
            tabBar.scrollEdgeAppearance = appearance;
        }
    }
    [selectedIndexProperty.setNative](value) {
        if (Trace.isEnabled()) {
            Trace.write('TabView._onSelectedIndexPropertyChangedSetNativeValue(' + value + ')', Trace.categories.Debug);
        }
        if (value > -1) {
            this._ios.selectedIndex = value;
        }
    }
    [itemsProperty.getDefault]() {
        return null;
    }
    [itemsProperty.setNative](value) {
        this.setViewControllers(value);
        selectedIndexProperty.coerce(this);
    }
    [tabTextFontSizeProperty.getDefault]() {
        return null;
    }
    [tabTextFontSizeProperty.setNative](value) {
        this._updateIOSTabBarColorsAndFonts();
    }
    [tabTextColorProperty.getDefault]() {
        return null;
    }
    [tabTextColorProperty.setNative](value) {
        this._updateIOSTabBarColorsAndFonts();
    }
    [tabBackgroundColorProperty.getDefault]() {
        return this._ios.tabBar.barTintColor;
    }
    [tabBackgroundColorProperty.setNative](value) {
        if (SDK_VERSION >= 13) {
            const appearance = this._getAppearance(this._ios.tabBar);
            appearance.configureWithDefaultBackground();
            appearance.backgroundColor = value instanceof Color ? value.ios : value;
            this._updateAppearance(this._ios.tabBar, appearance);
        }
        else {
            this._ios.tabBar.barTintColor = value instanceof Color ? value.ios : value;
        }
    }
    [selectedTabTextColorProperty.getDefault]() {
        return this._ios.tabBar.tintColor;
    }
    [selectedTabTextColorProperty.setNative](value) {
        this._ios.tabBar.tintColor = value instanceof Color ? value.ios : value;
        this._updateIOSTabBarColorsAndFonts();
    }
    // TODO: Move this to TabViewItem
    [fontInternalProperty.getDefault]() {
        return null;
    }
    [fontInternalProperty.setNative](value) {
        this._updateIOSTabBarColorsAndFonts();
    }
    // TODO: Move this to TabViewItem
    [iosIconRenderingModeProperty.getDefault]() {
        return 'automatic';
    }
    [iosIconRenderingModeProperty.setNative](value) {
        this._iconsCache = {};
        const items = this.items;
        if (items && items.length) {
            for (let i = 0, length = items.length; i < length; i++) {
                const item = items[i];
                if (item.iconSource) {
                    item._update();
                }
            }
        }
    }
    // iOS 26+: bottom accessory support
    [iosBottomAccessoryProperty.getDefault]() {
        return null;
    }
    [iosBottomAccessoryProperty.setNative](value) {
        this._applyBottomAccessory(value, false);
    }
    // iOS 26+: tab bar minimize behavior
    [iosTabBarMinimizeBehaviorProperty.getDefault]() {
        return 'automatic';
    }
    [iosTabBarMinimizeBehaviorProperty.setNative](value) {
        if (SDK_VERSION < 26) {
            return;
        }
        let mapped;
        switch (value) {
            case 'never':
                mapped = 1 /* UITabBarMinimizeBehavior.Never */;
                break;
            case 'onScrollDown':
                mapped = 2 /* UITabBarMinimizeBehavior.OnScrollDown */;
                break;
            case 'onScrollUp':
                mapped = 3 /* UITabBarMinimizeBehavior.OnScrollUp */;
                break;
            case 'automatic':
            default:
                mapped = 0 /* UITabBarMinimizeBehavior.Automatic */;
        }
        this._ios.tabBarMinimizeBehavior = mapped;
    }
    _applyBottomAccessory(value, animated) {
        // Guard for platform availability
        if (SDK_VERSION < 26) {
            return;
        }
        const setAccessory = (accessory) => {
            try {
                this._ios.setBottomAccessoryAnimated(accessory, animated);
            }
            catch (err) {
                // Fallback to property if needed
                this._ios.bottomAccessory = accessory;
            }
        };
        // Clear previous
        if (!value) {
            // Clear on controller
            setAccessory(null);
            // Tear down previously managed NS view
            if (this._bottomAccessoryNsView) {
                // Unregister from SharedTransition before teardown so it isn't
                // queried in subsequent transitions.
                SharedTransition.unregisterExternalRoot(this._bottomAccessoryNsView);
                // Do not remove from a parent; we didn't add it to the NS view tree.
                try {
                    this._bottomAccessoryNsView._tearDownUI(true);
                }
                catch (_) { }
                this._bottomAccessoryNsView = null;
            }
            return;
        }
        // Ensure the NativeScript view has a native view
        const nsView = value;
        if (!nsView.nativeViewProtected) {
            // mirror dialogs approach to setup UI for a detached view
            nsView._setupUI({});
        }
        // Just mark it loaded, if not already, so measurement & styling are applied.
        if (!nsView.isLoaded) {
            // In detached scenarios we simply callLoaded after setup.
            nsView.callLoaded();
        }
        const contentView = nsView.nativeViewProtected;
        if (!contentView) {
            return;
        }
        // Use frame-based sizing; keep autoresizing mask-based behavior enabled (no Auto Layout constraints added here).
        contentView.translatesAutoresizingMaskIntoConstraints = true;
        // Measure desired height with the tab bar width
        let tabBarWidth = this._ios?.tabBar?.frame?.size?.width || Screen.mainScreen.screen.bounds.size.width;
        // Account for safe area insets so accessory doesn't extend visually past rounded corners
        if (this._ios?.tabBar?.safeAreaInsets) {
            const insets = this._ios.tabBar.safeAreaInsets;
            // Reduce usable width by left+right safe area (typically 0, but defensive)
            const horizontalInsets = insets.left + insets.right;
            if (horizontalInsets > 0 && horizontalInsets < tabBarWidth) {
                tabBarWidth -= horizontalInsets;
            }
        }
        const tabBarWidthPx = layout.toDevicePixels(tabBarWidth);
        // Prefer flooring to avoid overshooting container by +1px due to FP rounding
        const tabBarWidthPxRounded = Math.floor(tabBarWidthPx);
        let measuredHeight = 0;
        // Measure using device-pixel width; flooring prevents +1px expansion
        const widthSpec = layout.makeMeasureSpec(tabBarWidthPxRounded, layout.EXACTLY);
        const heightSpec = layout.makeMeasureSpec(0, layout.UNSPECIFIED);
        nsView.measure(widthSpec, heightSpec);
        measuredHeight = layout.toDeviceIndependentPixels(nsView.getMeasuredHeight());
        // Use a sensible minimum height (44pt button row) if measurement is tiny
        const minHeight = 44;
        const finalHeight = Math.max(minHeight, measuredHeight || 0);
        // Rely on container height constraint (below) and frame-based layout inside container.
        const container = NSTabAccessoryContainer.initWithOwner(new WeakRef(nsView));
        container.translatesAutoresizingMaskIntoConstraints = true;
        container.autoresizingMask = 2 /* UIViewAutoresizing.FlexibleWidth */ | 16 /* UIViewAutoresizing.FlexibleHeight */;
        // Mask any subpixel spill just in case
        container.clipsToBounds = true;
        container.addSubview(contentView);
        // Constrain the container height (not the content) so UIKit has a concrete size.
        const containerHeight = container.heightAnchor.constraintEqualToConstant(finalHeight);
        containerHeight.priority = 999;
        NSLayoutConstraint.activateConstraints([containerHeight]);
        const accessory = UITabAccessory.alloc().initWithContentView(container);
        setAccessory(accessory);
        // Work around UIKit occasionally caching accessory sizes too aggressively
        // by explicitly triggering a layout pass on the tab bar.
        const tabBar = this._ios?.tabBar;
        if (tabBar) {
            tabBar.setNeedsLayout();
            tabBar.layoutIfNeeded();
        }
        // Keep references for later teardown
        this._bottomAccessoryNsView = nsView;
        // Expose the accessory's NS subtree to shared transitions. Tagged views
        // inside the accessory (e.g. a "now playing" mini-player's artwork) can
        // then participate in transitions that originate from any page, even
        // though the accessory isn't reachable via the page's NS view tree.
        SharedTransition.registerExternalRoot(nsView);
    }
}
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], TabView.prototype, "onLoaded", null);
var NSTabAccessoryContainer = (function (_super) {
    __extends(NSTabAccessoryContainer, _super);
    function NSTabAccessoryContainer() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    NSTabAccessoryContainer.initWithOwner = function (owner) {
        var v = NSTabAccessoryContainer.new();
        v._owner = owner;
        return v;
    };
    NSTabAccessoryContainer.prototype.traitCollectionDidChange = function (previousTraitCollection) {
        var _a;
        _super.prototype.traitCollectionDidChange.call(this, previousTraitCollection);
        if (!previousTraitCollection) {
            return;
        }
        if (((_a = this.traitCollection) === null || _a === void 0 ? void 0 : _a.horizontalSizeClass) !== previousTraitCollection.horizontalSizeClass) {
            this.invalidateIntrinsicContentSize();
            this.setNeedsLayout();
            this.layoutIfNeeded();
        }
    };
    NSTabAccessoryContainer.prototype.layoutSubviews = function () {
        var _a;
        _super.prototype.layoutSubviews.call(this);
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!(owner === null || owner === void 0 ? void 0 : owner.nativeViewProtected))
            return;
        owner.nativeViewProtected.frame = this.bounds;
        var w = this.bounds.size.width;
        var h = this.bounds.size.height;
        try {
            var wp = Math.floor(layout.toDevicePixels(w));
            var hp = Math.floor(layout.toDevicePixels(h));
            var containerPxWidth = Math.floor(layout.toDevicePixels(this.bounds.size.width));
            if (wp > containerPxWidth) {
                wp = containerPxWidth;
            }
            var widthSpec = layout.makeMeasureSpec(wp, layout.EXACTLY);
            var heightSpec = layout.makeMeasureSpec(hp, layout.EXACTLY);
            owner.measure(widthSpec, heightSpec);
            owner.layout(0, 0, wp, hp);
        }
        catch (_) { }
    };
    return NSTabAccessoryContainer;
}(UIView));
function getTitleAttributesForStates(tabView) {
    const result = {
        normalState: NSMutableDictionary.new(),
        selectedState: NSMutableDictionary.new(),
    };
    const titleFontSize = tabView.style.tabTextFontSize;
    let font = tabView.style.fontInternal || Font.default;
    if (titleFontSize != null) {
        font = font.withFontSize(titleFontSize);
    }
    const nativeFont = font.getUIFont(UIFont.systemFontOfSize(UIFont.labelFontSize));
    result.normalState.setValueForKey(nativeFont, NSFontAttributeName);
    result.selectedState.setValueForKey(nativeFont, NSFontAttributeName);
    const titleColor = tabView.style.tabTextColor;
    if (titleColor instanceof Color) {
        result.normalState.setValueForKey(titleColor.ios, UITextAttributeTextColor);
    }
    const selectedTitleColor = tabView.style.selectedTabTextColor;
    if (selectedTitleColor instanceof Color) {
        result.selectedState.setValueForKey(selectedTitleColor.ios, UITextAttributeTextColor);
    }
    return result;
}
function applyStatesToItem(item, states) {
    item.setTitleTextAttributesForState(states.normalState, 0 /* UIControlState.Normal */);
    item.setTitleTextAttributesForState(states.selectedState, 4 /* UIControlState.Selected */);
}
//# sourceMappingURL=index.ios.js.map