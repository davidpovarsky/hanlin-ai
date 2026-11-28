import { Background } from '../styling/background';
import { borderTopWidthProperty, borderRightWidthProperty, borderBottomWidthProperty, borderLeftWidthProperty, directionProperty, paddingInternalProperty } from '../styling/style-properties';
import { booleanConverter } from '../core/view-base';
import { View, CSSType } from '../core/view';
import { CoreTypes } from '../../core-types';
import { TextBase, whiteSpaceProperty, textOverflowProperty } from '../text-base';
import { layout } from '../../utils';
import { ios } from '../styling/background';
var FixedSize;
(function (FixedSize) {
    FixedSize[FixedSize["NONE"] = 0] = "NONE";
    FixedSize[FixedSize["WIDTH"] = 1] = "WIDTH";
    FixedSize[FixedSize["HEIGHT"] = 2] = "HEIGHT";
    FixedSize[FixedSize["BOTH"] = 3] = "BOTH";
})(FixedSize || (FixedSize = {}));
let Label = class Label extends TextBase {
    createNativeView() {
        const view = TNSLabel.new();
        view.userInteractionEnabled = true;
        return view;
    }
    disposeNativeView() {
        super.disposeNativeView();
        this._fixedSize = null;
    }
    // @ts-ignore
    get ios() {
        return this.nativeTextViewProtected;
    }
    get textWrap() {
        return this.style.whiteSpace === 'normal';
    }
    set textWrap(value) {
        if (typeof value === 'string') {
            value = booleanConverter(value);
        }
        this.style.whiteSpace = value ? 'normal' : 'nowrap';
    }
    _requestLayoutOnTextChanged() {
        if (this._fixedSize === FixedSize.BOTH) {
            return;
        }
        if (this._fixedSize === FixedSize.WIDTH && !this.textWrap && this.getMeasuredHeight() > 0) {
            // Single line label with fixed width will skip request layout on text change.
            return;
        }
        super._requestLayoutOnTextChanged();
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        const nativeView = this.nativeTextViewProtected;
        if (nativeView) {
            const width = layout.getMeasureSpecSize(widthMeasureSpec);
            const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
            const height = layout.getMeasureSpecSize(heightMeasureSpec);
            const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
            this._fixedSize = (widthMode === layout.EXACTLY ? FixedSize.WIDTH : FixedSize.NONE) | (heightMode === layout.EXACTLY ? FixedSize.HEIGHT : FixedSize.NONE);
            let nativeSize;
            if (this.textWrap) {
                // https://github.com/NativeScript/NativeScript/issues/4834
                // NOTE: utils.measureNativeView(...) relies on UIView.sizeThatFits(...) that
                // seems to have various issues when laying out UILabel instances.
                // We use custom measure logic here that relies on overriden
                // UILabel.textRectForBounds:limitedToNumberOfLines: in TNSLabel widget.
                nativeSize = this._measureNativeView(width, widthMode, height, heightMode);
            }
            else {
                // https://github.com/NativeScript/NativeScript/issues/6059
                // NOTE: _measureNativeView override breaks a scenario with StackLayout that arranges
                // labels horizontally (with textWrap=false) e.g. we are measuring label #2 within 356px,
                // label #2 needs more, and decides to show ellipsis(...) but because of this its native size
                // returned from UILabel.textRectForBounds:limitedToNumberOfLines: logic becomes 344px, so
                // StackLayout tries to measure label #3 within the remaining 12px which is wrong;
                // label #2 with ellipsis should take the whole 356px and label #3 should not be visible at all.
                nativeSize = layout.measureNativeView(nativeView, width, widthMode, height, heightMode);
            }
            let labelWidth = nativeSize.width;
            if (this.textWrap && widthMode === layout.AT_MOST) {
                labelWidth = Math.min(labelWidth, width);
            }
            const measureWidth = Math.max(labelWidth, this.effectiveMinWidth);
            const measureHeight = Math.max(nativeSize.height, this.effectiveMinHeight);
            const widthAndState = View.resolveSizeAndState(measureWidth, width, widthMode, 0);
            const heightAndState = View.resolveSizeAndState(measureHeight, height, heightMode, 0);
            this.setMeasuredDimension(widthAndState, heightAndState);
        }
    }
    _measureNativeView(width, widthMode, height, heightMode) {
        const view = this.nativeTextViewProtected;
        const nativeSize = view.textRectForBoundsLimitedToNumberOfLines(CGRectMake(0, 0, widthMode === 0 /* layout.UNSPECIFIED */ ? Number.POSITIVE_INFINITY : layout.toDeviceIndependentPixels(width), heightMode === 0 /* layout.UNSPECIFIED */ ? Number.POSITIVE_INFINITY : layout.toDeviceIndependentPixels(height)), view.numberOfLines).size;
        nativeSize.width = layout.round(layout.toDevicePixels(nativeSize.width));
        nativeSize.height = layout.round(layout.toDevicePixels(nativeSize.height));
        return nativeSize;
    }
    [whiteSpaceProperty.setNative](value) {
        this.adjustLineBreak();
    }
    [textOverflowProperty.setNative](value) {
        this.adjustLineBreak();
    }
    [directionProperty.setNative](value) {
        // Handle text ellipsis
        if ((this.whiteSpace === 'nowrap' && this.textOverflow !== 'clip') || this.maxLines > 0) {
            const nativeTextView = this.nativeTextViewProtected;
            nativeTextView.lineBreakMode = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
        }
        super[directionProperty.setNative](value);
    }
    adjustLineBreak() {
        const whiteSpace = this.whiteSpace;
        const textOverflow = this.textOverflow;
        const nativeView = this.nativeTextViewProtected;
        switch (whiteSpace) {
            case 'wrap':
            case 'normal':
                nativeView.lineBreakMode = 0 /* NSLineBreakMode.ByWordWrapping */;
                nativeView.numberOfLines = this.maxLines;
                break;
            case 'initial':
                nativeView.lineBreakMode = 4 /* NSLineBreakMode.ByTruncatingTail */;
                nativeView.numberOfLines = 1;
                break;
            case 'nowrap':
                switch (textOverflow) {
                    case 'clip':
                        nativeView.lineBreakMode = 2 /* NSLineBreakMode.ByClipping */;
                        nativeView.numberOfLines = this.maxLines;
                        break;
                    default:
                        nativeView.lineBreakMode = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
                        nativeView.numberOfLines = 1;
                        break;
                }
                break;
        }
    }
    _redrawNativeBackground(value) {
        if (value instanceof Background) {
            const nativeView = this.nativeTextViewProtected;
            if (nativeView) {
                ios.createBackgroundUIColor(this, (color) => {
                    const cgColor = color ? color.CGColor : null;
                    nativeView.layer.backgroundColor = cgColor;
                }, true);
            }
        }
        this._setNativeClipToBounds();
    }
    [borderTopWidthProperty.setNative](value) {
        const nativeView = this.nativeTextViewProtected;
        const border = nativeView.borderThickness;
        nativeView.borderThickness = new UIEdgeInsets({
            top: layout.toDeviceIndependentPixels(this.effectiveBorderTopWidth),
            right: border.right,
            bottom: border.bottom,
            left: border.left,
        });
    }
    [borderRightWidthProperty.setNative](value) {
        const nativeView = this.nativeTextViewProtected;
        const border = nativeView.borderThickness;
        nativeView.borderThickness = new UIEdgeInsets({
            top: border.top,
            right: layout.toDeviceIndependentPixels(this.effectiveBorderRightWidth),
            bottom: border.bottom,
            left: border.left,
        });
    }
    [borderBottomWidthProperty.setNative](value) {
        const nativeView = this.nativeTextViewProtected;
        const border = nativeView.borderThickness;
        nativeView.borderThickness = new UIEdgeInsets({
            top: border.top,
            right: border.right,
            bottom: layout.toDeviceIndependentPixels(this.effectiveBorderBottomWidth),
            left: border.left,
        });
    }
    [borderLeftWidthProperty.setNative](value) {
        const nativeView = this.nativeTextViewProtected;
        const border = nativeView.borderThickness;
        nativeView.borderThickness = new UIEdgeInsets({
            top: border.top,
            right: border.right,
            bottom: border.bottom,
            left: layout.toDeviceIndependentPixels(this.effectiveBorderLeftWidth),
        });
    }
    [paddingInternalProperty.setNative](_value) {
        this.nativeTextViewProtected.padding = new UIEdgeInsets({
            top: layout.toDeviceIndependentPixels(this.effectivePaddingTop),
            right: layout.toDeviceIndependentPixels(this.effectivePaddingRight),
            bottom: layout.toDeviceIndependentPixels(this.effectivePaddingBottom),
            left: layout.toDeviceIndependentPixels(this.effectivePaddingLeft),
        });
    }
};
Label = __decorate([
    CSSType('Label')
], Label);
export { Label };
Label.prototype.recycleNativeView = 'auto';
//# sourceMappingURL=index.ios.js.map