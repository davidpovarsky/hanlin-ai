import { ScrollViewBase, scrollBarIndicatorVisibleProperty, isScrollEnabledProperty, iosContentInsetAdjustmentBehaviorProperty, iosScrollEdgeEffectProperty } from './scroll-view-common';
import { layout } from '../../utils';
import { SDK_VERSION } from '../../utils/constants';
import { View } from '../core/view';
import { IOSHelper, ScrollEdgeContainers } from '../core/view/view-helper';
import { CoreTypes } from '../enums';
export * from './scroll-view-common';
var UIScrollViewDelegateImpl = (function (_super) {
    __extends(UIScrollViewDelegateImpl, _super);
    function UIScrollViewDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UIScrollViewDelegateImpl.initWithOwner = function (owner) {
        var impl = UIScrollViewDelegateImpl.new();
        impl._owner = owner;
        return impl;
    };
    UIScrollViewDelegateImpl.prototype.scrollViewDidScroll = function (sv) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.notify({
                object: owner,
                eventName: "scroll",
                scrollX: owner.horizontalOffset,
                scrollY: owner.verticalOffset,
            });
        }
    };
    UIScrollViewDelegateImpl.ObjCProtocols = [UIScrollViewDelegate];
    return UIScrollViewDelegateImpl;
}(NSObject));
export class ScrollView extends ScrollViewBase {
    constructor() {
        super(...arguments);
        this._contentMeasuredWidth = 0;
        this._contentMeasuredHeight = 0;
        this._isFirstLayout = true;
    }
    createNativeView() {
        return UIScrollView.new();
    }
    initNativeView() {
        super.initNativeView();
        this.updateScrollBarVisibility(this.scrollBarIndicatorVisible);
        this._setNativeClipToBounds();
        // UIKit defaults to `automatic` while the property defaults to `never`, and
        // setNative only runs for non-default values — so apply it up front.
        this.updateContentInsetAdjustmentBehavior(this.iosContentInsetAdjustmentBehavior);
        this._scrollEdgeContainers?.attach();
    }
    disposeNativeView() {
        this._scrollEdgeContainers?.detach();
        super.disposeNativeView();
        this._isFirstLayout = true;
    }
    addScrollEdgeContainer(view, edge) {
        if (!this._scrollEdgeContainers) {
            this._scrollEdgeContainers = new ScrollEdgeContainers(this);
        }
        this._scrollEdgeContainers.add(view, edge);
    }
    removeScrollEdgeContainer(view) {
        this._scrollEdgeContainers?.remove(view);
    }
    _setNativeClipToBounds() {
        if (!this.nativeViewProtected) {
            return;
        }
        // Always set clipsToBounds for scroll-view
        this.nativeViewProtected.clipsToBounds = true;
    }
    attachNative() {
        if (!this._delegate) {
            this._delegate = UIScrollViewDelegateImpl.initWithOwner(new WeakRef(this));
            this.nativeViewProtected.delegate = this._delegate;
        }
    }
    detachNative() {
        if (this._delegate) {
            if (this.nativeViewProtected) {
                this.nativeViewProtected.delegate = null;
            }
            this._delegate = null;
        }
    }
    updateScrollBarVisibility(value) {
        if (!this.nativeViewProtected) {
            return;
        }
        if (this.orientation === 'horizontal') {
            this.nativeViewProtected.showsHorizontalScrollIndicator = value;
        }
        else {
            this.nativeViewProtected.showsVerticalScrollIndicator = value;
        }
    }
    updateContentInsetAdjustmentBehavior(value) {
        if (!this.nativeViewProtected || SDK_VERSION <= 10) {
            return;
        }
        // https://developer.apple.com/documentation/uikit/uiscrollview/contentinsetadjustmentbehavior
        let behavior = 2 /* UIScrollViewContentInsetAdjustmentBehavior.Never */;
        if (value === 'automatic') {
            behavior = 0 /* UIScrollViewContentInsetAdjustmentBehavior.Automatic */;
        }
        else if (value === 'scrollableAxes') {
            behavior = 1 /* UIScrollViewContentInsetAdjustmentBehavior.ScrollableAxes */;
        }
        else if (value === 'always') {
            behavior = 3 /* UIScrollViewContentInsetAdjustmentBehavior.Always */;
        }
        this.nativeViewProtected.contentInsetAdjustmentBehavior = behavior;
    }
    get horizontalOffset() {
        return this.nativeViewProtected ? this.nativeViewProtected.contentOffset.x : 0;
    }
    get verticalOffset() {
        return this.nativeViewProtected ? this.nativeViewProtected.contentOffset.y : 0;
    }
    // Each is the largest offset a scroll reaches, end inset included, so scrolling to it shows the end of the
    // content above a keyboard or docked bar that sets contentInset.bottom.
    get scrollableWidth() {
        if (!this.nativeViewProtected || this.orientation !== 'horizontal') {
            return 0;
        }
        const nativeView = this.nativeViewProtected;
        return Math.max(0, nativeView.contentSize.width + nativeView.adjustedContentInset.right - nativeView.bounds.size.width);
    }
    get scrollableHeight() {
        if (!this.nativeViewProtected || this.orientation !== 'vertical') {
            return 0;
        }
        const nativeView = this.nativeViewProtected;
        return Math.max(0, nativeView.contentSize.height + nativeView.adjustedContentInset.bottom - nativeView.bounds.size.height);
    }
    [isScrollEnabledProperty.getDefault]() {
        return this.nativeViewProtected.scrollEnabled;
    }
    [isScrollEnabledProperty.setNative](value) {
        this.nativeViewProtected.scrollEnabled = value;
    }
    [scrollBarIndicatorVisibleProperty.getDefault]() {
        return true;
    }
    [scrollBarIndicatorVisibleProperty.setNative](value) {
        this.updateScrollBarVisibility(value);
    }
    [iosContentInsetAdjustmentBehaviorProperty.setNative](value) {
        this.updateContentInsetAdjustmentBehavior(value);
    }
    [iosScrollEdgeEffectProperty.setNative](value) {
        IOSHelper.setScrollEdgeEffect(this.nativeViewProtected, value);
    }
    // The offset is set directly rather than through scrollRectToVisible with a
    // viewport-sized rect: that rect cannot fit inside a content inset, so UIKit
    // would land contentInset.bottom (or .right) past the requested offset. The
    // value is clamped to the range a user scroll can reach.
    scrollToVerticalOffset(value, animated) {
        const nativeView = this.nativeViewProtected;
        if (nativeView && this.orientation === 'vertical' && this.isScrollEnabled) {
            const inset = nativeView.adjustedContentInset;
            const min = -inset.top;
            const max = Math.max(min, nativeView.contentSize.height + inset.bottom - nativeView.bounds.size.height);
            nativeView.setContentOffsetAnimated(CGPointMake(nativeView.contentOffset.x, Math.min(Math.max(value, min), max)), animated);
        }
    }
    scrollToHorizontalOffset(value, animated) {
        const nativeView = this.nativeViewProtected;
        if (nativeView && this.orientation === 'horizontal' && this.isScrollEnabled) {
            const inset = nativeView.adjustedContentInset;
            const min = -inset.left;
            const max = Math.max(min, nativeView.contentSize.width + inset.right - nativeView.bounds.size.width);
            nativeView.setContentOffsetAnimated(CGPointMake(Math.min(Math.max(value, min), max), nativeView.contentOffset.y), animated);
        }
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        // Don't call measure because it will measure content twice.
        const width = layout.getMeasureSpecSize(widthMeasureSpec);
        const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
        const height = layout.getMeasureSpecSize(heightMeasureSpec);
        const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
        const child = this.layoutView;
        this._contentMeasuredWidth = this.effectiveMinWidth;
        this._contentMeasuredHeight = this.effectiveMinHeight;
        if (child) {
            let childSize;
            if (this.orientation === 'vertical') {
                childSize = View.measureChild(this, child, widthMeasureSpec, layout.makeMeasureSpec(0, layout.UNSPECIFIED));
            }
            else {
                childSize = View.measureChild(this, child, layout.makeMeasureSpec(0, layout.UNSPECIFIED), heightMeasureSpec);
            }
            this._contentMeasuredWidth = Math.max(childSize.measuredWidth, this.effectiveMinWidth);
            this._contentMeasuredHeight = Math.max(childSize.measuredHeight, this.effectiveMinHeight);
        }
        const widthAndState = View.resolveSizeAndState(this._contentMeasuredWidth, width, widthMode, 0);
        const heightAndState = View.resolveSizeAndState(this._contentMeasuredHeight, height, heightMode, 0);
        this.setMeasuredDimension(widthAndState, heightAndState);
    }
    onLayout(left, top, right, bottom) {
        if (!this.nativeViewProtected) {
            return;
        }
        // When iOS adjusts content insets itself, don't also subtract safe-area insets here —
        // doing both makes contentSize track the dynamic navbar height and causes scroll drift with large titles.
        const useIOSInsetAdjustment = SDK_VERSION > 10 && this.iosContentInsetAdjustmentBehavior !== 'never';
        const insets = useIOSInsetAdjustment ? { left: 0, top: 0, right: 0, bottom: 0 } : this.getSafeAreaInsets();
        let scrollWidth = right - left - insets.right - insets.left;
        let scrollHeight = bottom - top - insets.bottom - insets.top;
        let scrollInsetWidth = scrollWidth + insets.left + insets.right;
        let scrollInsetHeight = scrollHeight + insets.top + insets.bottom;
        if (this.orientation === 'horizontal') {
            scrollInsetWidth = Math.max(this._contentMeasuredWidth + insets.left + insets.right, scrollInsetWidth);
            scrollWidth = Math.max(this._contentMeasuredWidth, scrollWidth);
        }
        else {
            scrollInsetHeight = Math.max(this._contentMeasuredHeight + insets.top + insets.bottom, scrollInsetHeight);
            scrollHeight = Math.max(this._contentMeasuredHeight, scrollHeight);
        }
        this.nativeViewProtected.contentSize = CGSizeMake(layout.toDeviceIndependentPixels(scrollInsetWidth), layout.toDeviceIndependentPixels(scrollInsetHeight));
        // RTL handling
        if (this.orientation === 'horizontal') {
            if (this._isFirstLayout) {
                this._isFirstLayout = false;
                if (this.direction === CoreTypes.LayoutDirection.rtl) {
                    const scrollableWidth = scrollInsetWidth - this.getMeasuredWidth();
                    if (scrollableWidth > 0) {
                        this.nativeViewProtected.contentOffset = CGPointMake(layout.toDeviceIndependentPixels(scrollableWidth), this.verticalOffset);
                    }
                }
            }
        }
        View.layoutChild(this, this.layoutView, insets.left, insets.top, insets.left + scrollWidth, insets.top + scrollHeight);
    }
    _onOrientationChanged() {
        this._isFirstLayout = true;
        this.updateScrollBarVisibility(this.scrollBarIndicatorVisible);
    }
}
ScrollView.prototype.recycleNativeView = 'auto';
//# sourceMappingURL=index.ios.js.map