import { ControlStateChangeListener } from '../core/control-state-change';
import { ButtonBase } from './button-common';
import { View, PseudoClassHandler } from '../core/view';
import { borderTopWidthProperty, borderRightWidthProperty, borderBottomWidthProperty, borderLeftWidthProperty, directionProperty, paddingInternalProperty, paddingTopProperty, paddingRightProperty, paddingBottomProperty, paddingLeftProperty, _hasPaddingSetNativeOverrides } from '../styling/style-properties';
import { textAlignmentProperty, whiteSpaceProperty, textOverflowProperty } from '../text-base';
import { layout } from '../../utils';
import { CoreTypes } from '../../core-types';
export * from './button-common';
const observableVisualStates = ['highlighted']; // States like :disabled are handled elsewhere
export class Button extends ButtonBase {
    createNativeView() {
        const nativeView = UIButton.buttonWithType(1 /* UIButtonType.System */);
        // This is the default for both platforms
        if (nativeView.titleLabel) {
            nativeView.titleLabel.textAlignment = 1 /* NSTextAlignment.Center */;
        }
        return nativeView;
    }
    initNativeView() {
        super.initNativeView();
        this._tapHandler = TapHandlerImpl.initWithOwner(new WeakRef(this));
        this.nativeViewProtected.addTargetActionForControlEvents(this._tapHandler, 'tap', 64 /* UIControlEvents.TouchUpInside */);
        this._setDefaultPaddings(this.nativeViewProtected.contentEdgeInsets);
    }
    disposeNativeView() {
        this._tapHandler = null;
        if (this._stateChangedHandler) {
            this._stateChangedHandler.stop();
            this._stateChangedHandler = null;
        }
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    _updateButtonStateChangeHandler(subscribe) {
        if (subscribe) {
            if (!this._stateChangedHandler) {
                const viewRef = new WeakRef(this);
                this._stateChangedHandler = new ControlStateChangeListener(this.nativeViewProtected, observableVisualStates, (state, add) => {
                    const view = viewRef?.deref?.();
                    if (view) {
                        if (add) {
                            view._addVisualState(state);
                        }
                        else {
                            view._removeVisualState(state);
                        }
                    }
                });
            }
            this._stateChangedHandler.start();
        }
        else {
            this._stateChangedHandler.stop();
            // Remove any possible pseudo-class leftovers
            for (const state of observableVisualStates) {
                this._removeVisualState(state);
            }
        }
    }
    [borderTopWidthProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.top,
            unit: 'px',
        };
    }
    [borderTopWidthProperty.setNative](value) {
        const inset = this.nativeViewProtected.contentEdgeInsets;
        const top = layout.toDeviceIndependentPixels(this.effectivePaddingTop + this.effectiveBorderTopWidth);
        this.nativeViewProtected.contentEdgeInsets = new UIEdgeInsets({
            top: top,
            left: inset.left,
            bottom: inset.bottom,
            right: inset.right,
        });
    }
    [borderRightWidthProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.right,
            unit: 'px',
        };
    }
    [borderRightWidthProperty.setNative](value) {
        const inset = this.nativeViewProtected.contentEdgeInsets;
        const right = layout.toDeviceIndependentPixels(this.effectivePaddingRight + this.effectiveBorderRightWidth);
        this.nativeViewProtected.contentEdgeInsets = new UIEdgeInsets({
            top: inset.top,
            left: inset.left,
            bottom: inset.bottom,
            right: right,
        });
    }
    [borderBottomWidthProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.bottom,
            unit: 'px',
        };
    }
    [borderBottomWidthProperty.setNative](value) {
        const inset = this.nativeViewProtected.contentEdgeInsets;
        const bottom = layout.toDeviceIndependentPixels(this.effectivePaddingBottom + this.effectiveBorderBottomWidth);
        this.nativeViewProtected.contentEdgeInsets = new UIEdgeInsets({
            top: inset.top,
            left: inset.left,
            bottom: bottom,
            right: inset.right,
        });
    }
    [borderLeftWidthProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.left,
            unit: 'px',
        };
    }
    [borderLeftWidthProperty.setNative](value) {
        const inset = this.nativeViewProtected.contentEdgeInsets;
        const left = layout.toDeviceIndependentPixels(this.effectivePaddingLeft + this.effectiveBorderLeftWidth);
        this.nativeViewProtected.contentEdgeInsets = new UIEdgeInsets({
            top: inset.top,
            left: left,
            bottom: inset.bottom,
            right: inset.right,
        });
    }
    [paddingTopProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.top,
            unit: 'px',
        };
    }
    [paddingTopProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.top = layout.toDeviceIndependentPixels(this.effectivePaddingTop + this.effectiveBorderTopWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, Button.prototype)) {
            const nativeView = this.nativeViewProtected;
            const inset = nativeView.contentEdgeInsets;
            nativeView.contentEdgeInsets = new UIEdgeInsets({
                top: layout.toDeviceIndependentPixels(this.effectivePaddingTop + this.effectiveBorderTopWidth),
                right: inset.right,
                bottom: inset.bottom,
                left: inset.left,
            });
        }
    }
    [paddingRightProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.right,
            unit: 'px',
        };
    }
    [paddingRightProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.right = layout.toDeviceIndependentPixels(this.effectivePaddingRight + this.effectiveBorderRightWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, Button.prototype)) {
            const nativeView = this.nativeViewProtected;
            const inset = nativeView.contentEdgeInsets;
            nativeView.contentEdgeInsets = new UIEdgeInsets({
                top: inset.top,
                right: layout.toDeviceIndependentPixels(this.effectivePaddingRight + this.effectiveBorderRightWidth),
                bottom: inset.bottom,
                left: inset.left,
            });
        }
    }
    [paddingBottomProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.bottom,
            unit: 'px',
        };
    }
    [paddingBottomProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.bottom = layout.toDeviceIndependentPixels(this.effectivePaddingBottom + this.effectiveBorderBottomWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, Button.prototype)) {
            const nativeView = this.nativeViewProtected;
            const inset = nativeView.contentEdgeInsets;
            nativeView.contentEdgeInsets = new UIEdgeInsets({
                top: inset.top,
                right: inset.right,
                bottom: layout.toDeviceIndependentPixels(this.effectivePaddingBottom + this.effectiveBorderBottomWidth),
                left: inset.left,
            });
        }
    }
    [paddingLeftProperty.getDefault]() {
        return {
            value: this.nativeViewProtected.contentEdgeInsets.left,
            unit: 'px',
        };
    }
    [paddingLeftProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.left = layout.toDeviceIndependentPixels(this.effectivePaddingLeft + this.effectiveBorderLeftWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, Button.prototype)) {
            const nativeView = this.nativeViewProtected;
            const inset = nativeView.contentEdgeInsets;
            nativeView.contentEdgeInsets = new UIEdgeInsets({
                top: inset.top,
                right: inset.right,
                bottom: inset.bottom,
                left: layout.toDeviceIndependentPixels(this.effectivePaddingLeft + this.effectiveBorderLeftWidth),
            });
        }
    }
    [paddingInternalProperty.setNative](_value) {
        if (_hasPaddingSetNativeOverrides(this, Button.prototype)) {
            // An override owns padding application; each side applies through its own handler.
            return;
        }
        const nativeView = this.nativeViewProtected;
        const inset = nativeView.contentEdgeInsets;
        this._pendingPadding = { top: inset.top, right: inset.right, bottom: inset.bottom, left: inset.left };
        this[paddingTopProperty.setNative](this.style.paddingTop);
        this[paddingRightProperty.setNative](this.style.paddingRight);
        this[paddingBottomProperty.setNative](this.style.paddingBottom);
        this[paddingLeftProperty.setNative](this.style.paddingLeft);
        nativeView.contentEdgeInsets = new UIEdgeInsets(this._pendingPadding);
        this._pendingPadding = null;
    }
    [textAlignmentProperty.setNative](value) {
        switch (value) {
            case 'left':
                this.nativeViewProtected.titleLabel.textAlignment = 0 /* NSTextAlignment.Left */;
                this.nativeViewProtected.contentHorizontalAlignment = 1 /* UIControlContentHorizontalAlignment.Left */;
                break;
            case 'right':
                this.nativeViewProtected.titleLabel.textAlignment = 2 /* NSTextAlignment.Right */;
                this.nativeViewProtected.contentHorizontalAlignment = 2 /* UIControlContentHorizontalAlignment.Right */;
                break;
            case 'justify':
                this.nativeViewProtected.titleLabel.textAlignment = 3 /* NSTextAlignment.Justified */;
                this.nativeViewProtected.contentHorizontalAlignment = 0 /* UIControlContentHorizontalAlignment.Center */;
                break;
            default:
                // initial | center
                this.nativeViewProtected.titleLabel.textAlignment = 1 /* NSTextAlignment.Center */;
                this.nativeViewProtected.contentHorizontalAlignment = 0 /* UIControlContentHorizontalAlignment.Center */;
                break;
        }
    }
    [whiteSpaceProperty.setNative](value) {
        this.adjustLineBreak();
    }
    [textOverflowProperty.setNative](value) {
        this.adjustLineBreak();
    }
    [directionProperty.setNative](value) {
        // Handle text ellipsis
        if (this.textOverflow === 'ellipsis' || this.maxLines > 0) {
            const nativeTextView = this.nativeViewProtected.titleLabel;
            nativeTextView.lineBreakMode = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
        }
        super[directionProperty.setNative](value);
    }
    adjustLineBreak() {
        const whiteSpace = this.whiteSpace;
        const textOverflow = this.textOverflow;
        const nativeView = this.nativeViewProtected.titleLabel;
        switch (whiteSpace) {
            case 'wrap':
            case 'normal':
                nativeView.lineBreakMode = 0 /* NSLineBreakMode.ByWordWrapping */;
                nativeView.numberOfLines = this.maxLines;
                break;
            case 'initial':
                nativeView.lineBreakMode = 5 /* NSLineBreakMode.ByTruncatingMiddle */;
                nativeView.numberOfLines = 1;
                break;
            case 'nowrap':
                switch (textOverflow) {
                    case 'clip':
                        nativeView.lineBreakMode = 2 /* NSLineBreakMode.ByClipping */;
                        nativeView.numberOfLines = this.maxLines;
                        break;
                    case 'ellipsis':
                        nativeView.lineBreakMode = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
                        nativeView.numberOfLines = 1;
                        break;
                    default:
                        nativeView.lineBreakMode = 5 /* NSLineBreakMode.ByTruncatingMiddle */;
                        nativeView.numberOfLines = 1;
                        break;
                }
                break;
        }
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        // If there is text-wrap UIButton.sizeThatFits will return wrong result (not respecting the text wrap).
        // So fallback to original onMeasure if there is no text-wrap and use custom measure otherwise.
        if (!this.textWrap) {
            return super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        }
        const nativeView = this.nativeViewProtected;
        if (nativeView) {
            const width = layout.getMeasureSpecSize(widthMeasureSpec);
            const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
            const height = layout.getMeasureSpecSize(heightMeasureSpec);
            const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
            const horizontalPadding = this.effectivePaddingLeft + this.effectiveBorderLeftWidth + this.effectivePaddingRight + this.effectiveBorderRightWidth;
            let verticalPadding = this.effectivePaddingTop + this.effectiveBorderTopWidth + this.effectivePaddingBottom + this.effectiveBorderBottomWidth;
            // The default button padding for UIButton - 6dip top and bottom.
            if (verticalPadding === 0) {
                verticalPadding = layout.toDevicePixels(12);
            }
            const desiredSize = layout.measureNativeView(nativeView.titleLabel, width - horizontalPadding, widthMode, height - verticalPadding, heightMode);
            desiredSize.width = desiredSize.width + horizontalPadding;
            desiredSize.height = desiredSize.height + verticalPadding;
            const measureWidth = Math.max(desiredSize.width, this.effectiveMinWidth);
            const measureHeight = Math.max(desiredSize.height, this.effectiveMinHeight);
            const widthAndState = View.resolveSizeAndState(measureWidth, width, widthMode, 0);
            const heightAndState = View.resolveSizeAndState(measureHeight, height, heightMode, 0);
            this.setMeasuredDimension(widthAndState, heightAndState);
        }
    }
}
__decorate([
    PseudoClassHandler('normal', 'highlighted', 'pressed', 'active'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Boolean]),
    __metadata("design:returntype", void 0)
], Button.prototype, "_updateButtonStateChangeHandler", null);
var TapHandlerImpl = (function (_super) {
    __extends(TapHandlerImpl, _super);
    function TapHandlerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    TapHandlerImpl.initWithOwner = function (owner) {
        var handler = TapHandlerImpl.new();
        handler._owner = owner;
        return handler;
    };
    TapHandlerImpl.prototype.tap = function (args) {
        var _a;
        if (this._owner) {
            var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
            if (owner) {
                owner._emit(ButtonBase.tapEvent);
            }
        }
    };
    TapHandlerImpl.ObjCExposedMethods = {
        tap: { returns: interop.types.void, params: [interop.types.id] },
    };
    return TapHandlerImpl;
}(NSObject));
//# sourceMappingURL=index.ios.js.map