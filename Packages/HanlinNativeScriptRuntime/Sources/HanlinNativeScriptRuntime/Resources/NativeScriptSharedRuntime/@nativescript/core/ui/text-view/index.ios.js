var TextView_1;
import { textProperty } from '../text-base';
import { iosWritingToolsAllowedInputProperty, iosWritingToolsBehaviorProperty, TextViewBase as TextViewBaseCommon, WritingToolsAllowedInput, WritingToolsBehavior } from './text-view-common';
import { editableProperty, hintProperty, placeholderColorProperty, _updateCharactersInRangeReplacementString } from '../editable-text-base';
import { CoreTypes } from '../../core-types';
import { CSSType } from '../core/view';
import { colorProperty, borderTopWidthProperty, borderRightWidthProperty, borderBottomWidthProperty, borderLeftWidthProperty, directionProperty, paddingInternalProperty, paddingTopProperty, paddingRightProperty, paddingBottomProperty, paddingLeftProperty, _hasPaddingSetNativeOverrides } from '../styling/style-properties';
import { layout, isRealDevice } from '../../utils';
import { SDK_VERSION } from '../../utils/constants';
export { WritingToolsAllowedInput, WritingToolsBehavior } from './text-view-common';
var UITextViewDelegateImpl = (function (_super) {
    __extends(UITextViewDelegateImpl, _super);
    function UITextViewDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITextViewDelegateImpl.initWithOwner = function (owner) {
        var impl = UITextViewDelegateImpl.new();
        impl._owner = owner;
        return impl;
    };
    UITextViewDelegateImpl.prototype.textViewShouldBeginEditing = function (textView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.textViewShouldBeginEditing(textView);
        }
        return true;
    };
    UITextViewDelegateImpl.prototype.textViewDidBeginEditing = function (textView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.textViewDidBeginEditing(textView);
        }
    };
    UITextViewDelegateImpl.prototype.textViewDidEndEditing = function (textView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.textViewDidEndEditing(textView);
        }
    };
    UITextViewDelegateImpl.prototype.textViewDidChange = function (textView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.textViewDidChange(textView);
        }
    };
    UITextViewDelegateImpl.prototype.textViewShouldChangeTextInRangeReplacementText = function (textView, range, replacementString) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.textViewShouldChangeTextInRangeReplacementText(textView, range, replacementString);
        }
        return true;
    };
    UITextViewDelegateImpl.prototype.scrollViewDidScroll = function (sv) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.scrollViewDidScroll(sv);
        }
    };
    UITextViewDelegateImpl.prototype.textViewWritingToolsWillBegin = function (textView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.isWritingToolsActive = true;
        }
    };
    UITextViewDelegateImpl.prototype.textViewWritingToolsDidEnd = function (textView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.isWritingToolsActive = false;
            owner.textViewDidChange(textView);
        }
    };
    UITextViewDelegateImpl.ObjCProtocols = [UITextViewDelegate];
    return UITextViewDelegateImpl;
}(NSObject));
var NoScrollAnimationUITextView = (function (_super) {
    __extends(NoScrollAnimationUITextView, _super);
    function NoScrollAnimationUITextView() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    NoScrollAnimationUITextView.prototype.setContentOffsetAnimated = function (contentOffset, animated) {
        _super.prototype.setContentOffsetAnimated.call(this, contentOffset, false);
    };
    return NoScrollAnimationUITextView;
}(UITextView));
let TextView = TextView_1 = class TextView extends TextViewBaseCommon {
    constructor() {
        super(...arguments);
        this._hintColor = SDK_VERSION <= 12 || !UIColor.placeholderTextColor ? UIColor.blackColor.colorWithAlphaComponent(0.22) : UIColor.placeholderTextColor;
        this._textColor = SDK_VERSION <= 12 || !UIColor.labelColor ? null : UIColor.labelColor;
    }
    createNativeView() {
        const textView = NoScrollAnimationUITextView.new();
        if (!textView.font) {
            textView.font = UIFont.systemFontOfSize(12);
        }
        return textView;
    }
    initNativeView() {
        super.initNativeView();
        this._delegate = UITextViewDelegateImpl.initWithOwner(new WeakRef(this));
        this.nativeTextViewProtected.delegate = this._delegate;
        this._setDefaultPaddings(this.nativeTextViewProtected.textContainerInset);
    }
    disposeNativeView() {
        this._delegate = null;
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    textViewShouldBeginEditing(textView) {
        if (this._isShowingHint) {
            this.showText();
        }
        return this.editable;
    }
    textViewDidBeginEditing(textView) {
        this._isEditing = true;
        this.notify({ eventName: TextView_1.focusEvent, object: this });
    }
    textViewDidEndEditing(textView) {
        if (this.updateTextTrigger === 'focusLost') {
            textProperty.nativeValueChange(this, textView.text);
        }
        this._isEditing = false;
        this.dismissSoftInput();
        this._refreshHintState(this.hint, textView.text);
    }
    textViewDidChange(textView) {
        if (!this.isWritingToolsActive || this.enableWritingToolsEvents) {
            if (this.updateTextTrigger === 'textChanged') {
                textProperty.nativeValueChange(this, textView.text);
            }
            this.requestLayout();
        }
    }
    textViewShouldChangeTextInRangeReplacementText(textView, range, replacementString) {
        const delta = replacementString.length - range.length;
        if (delta > 0) {
            if (textView.text.length + delta > this.maxLength) {
                return false;
            }
        }
        if (replacementString === '\n') {
            this.notify({ eventName: TextView_1.returnPressEvent, object: this });
        }
        if (this.formattedText) {
            _updateCharactersInRangeReplacementString(this.formattedText, range.location, range.length, replacementString);
        }
        return true;
    }
    scrollViewDidScroll(sv) {
        const contentOffset = this.nativeViewProtected.contentOffset;
        this.notify({
            object: this,
            eventName: 'scroll',
            scrollX: contentOffset.x,
            scrollY: contentOffset.y,
        });
    }
    _refreshHintState(hint, text) {
        if (this.formattedText) {
            return;
        }
        if (text !== null && text !== undefined && text !== '') {
            this.showText();
        }
        else if (!this._isEditing && hint !== null && hint !== undefined && hint !== '') {
            this.showHint(hint);
        }
        else {
            this._isShowingHint = false;
            this.nativeTextViewProtected.text = '';
        }
    }
    _refreshColor() {
        if (this._isShowingHint) {
            const placeholderColor = this.style.placeholderColor;
            const color = this.style.color;
            if (placeholderColor) {
                this.nativeTextViewProtected.textColor = placeholderColor.ios;
            }
            else if (color) {
                // Use semi-transparent version of color for back-compatibility
                this.nativeTextViewProtected.textColor = color.ios.colorWithAlphaComponent(0.22);
            }
            else {
                this.nativeTextViewProtected.textColor = this._hintColor;
            }
        }
        else {
            const color = this.style.color;
            if (color) {
                this.nativeTextViewProtected.textColor = color.ios;
                this.nativeTextViewProtected.tintColor = color.ios;
            }
            else {
                this.nativeTextViewProtected.textColor = this._textColor;
                this.nativeTextViewProtected.tintColor = this._textColor;
            }
        }
    }
    showHint(hint) {
        const nativeView = this.nativeTextViewProtected;
        this._isShowingHint = true;
        this._refreshColor();
        const hintAsString = hint === null || hint === undefined ? '' : hint.toString();
        nativeView.text = hintAsString;
    }
    showText() {
        this._isShowingHint = false;
        this._setNativeText();
        this._refreshColor();
        this.requestLayout();
    }
    [textProperty.getDefault]() {
        return '';
    }
    [textProperty.setNative](value) {
        this._refreshHintState(this.hint, value);
    }
    [directionProperty.setNative](value) {
        // Handle text ellipsis
        if (this.maxLines > 0) {
            const textContainer = this.nativeTextViewProtected.textContainer;
            textContainer.lineBreakMode = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
        }
        super[directionProperty.setNative](value);
    }
    [hintProperty.getDefault]() {
        return '';
    }
    [hintProperty.setNative](value) {
        this._refreshHintState(value, this.text);
    }
    [editableProperty.getDefault]() {
        return this.nativeTextViewProtected.editable;
    }
    [editableProperty.setNative](value) {
        this.nativeTextViewProtected.editable = value;
    }
    [colorProperty.setNative](color) {
        this._refreshColor();
    }
    [placeholderColorProperty.setNative](value) {
        this._refreshColor();
    }
    [borderTopWidthProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.top,
            unit: 'px',
        };
    }
    [borderTopWidthProperty.setNative](value) {
        const inset = this.nativeTextViewProtected.textContainerInset;
        const top = layout.toDeviceIndependentPixels(this.effectivePaddingTop + this.effectiveBorderTopWidth);
        this.nativeTextViewProtected.textContainerInset = new UIEdgeInsets({
            top: top,
            left: inset.left,
            bottom: inset.bottom,
            right: inset.right,
        });
    }
    [borderRightWidthProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.right,
            unit: 'px',
        };
    }
    [borderRightWidthProperty.setNative](value) {
        const inset = this.nativeTextViewProtected.textContainerInset;
        const right = layout.toDeviceIndependentPixels(this.effectivePaddingRight + this.effectiveBorderRightWidth);
        this.nativeTextViewProtected.textContainerInset = new UIEdgeInsets({
            top: inset.top,
            left: inset.left,
            bottom: inset.bottom,
            right: right,
        });
    }
    [borderBottomWidthProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.bottom,
            unit: 'px',
        };
    }
    [borderBottomWidthProperty.setNative](value) {
        const inset = this.nativeTextViewProtected.textContainerInset;
        const bottom = layout.toDeviceIndependentPixels(this.effectivePaddingBottom + this.effectiveBorderBottomWidth);
        this.nativeTextViewProtected.textContainerInset = new UIEdgeInsets({
            top: inset.top,
            left: inset.left,
            bottom: bottom,
            right: inset.right,
        });
    }
    [borderLeftWidthProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.left,
            unit: 'px',
        };
    }
    [borderLeftWidthProperty.setNative](value) {
        const inset = this.nativeTextViewProtected.textContainerInset;
        const left = layout.toDeviceIndependentPixels(this.effectivePaddingLeft + this.effectiveBorderLeftWidth);
        this.nativeTextViewProtected.textContainerInset = new UIEdgeInsets({
            top: inset.top,
            left: left,
            bottom: inset.bottom,
            right: inset.right,
        });
    }
    [paddingTopProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.top,
            unit: 'px',
        };
    }
    [paddingTopProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.top = layout.toDeviceIndependentPixels(this.effectivePaddingTop + this.effectiveBorderTopWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, TextView_1.prototype)) {
            const nativeView = this.nativeTextViewProtected;
            const inset = nativeView.textContainerInset;
            nativeView.textContainerInset = new UIEdgeInsets({
                top: layout.toDeviceIndependentPixels(this.effectivePaddingTop + this.effectiveBorderTopWidth),
                right: inset.right,
                bottom: inset.bottom,
                left: inset.left,
            });
        }
    }
    [paddingRightProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.right,
            unit: 'px',
        };
    }
    [paddingRightProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.right = layout.toDeviceIndependentPixels(this.effectivePaddingRight + this.effectiveBorderRightWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, TextView_1.prototype)) {
            const nativeView = this.nativeTextViewProtected;
            const inset = nativeView.textContainerInset;
            nativeView.textContainerInset = new UIEdgeInsets({
                top: inset.top,
                right: layout.toDeviceIndependentPixels(this.effectivePaddingRight + this.effectiveBorderRightWidth),
                bottom: inset.bottom,
                left: inset.left,
            });
        }
    }
    [paddingBottomProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.bottom,
            unit: 'px',
        };
    }
    [paddingBottomProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.bottom = layout.toDeviceIndependentPixels(this.effectivePaddingBottom + this.effectiveBorderBottomWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, TextView_1.prototype)) {
            const nativeView = this.nativeTextViewProtected;
            const inset = nativeView.textContainerInset;
            nativeView.textContainerInset = new UIEdgeInsets({
                top: inset.top,
                right: inset.right,
                bottom: layout.toDeviceIndependentPixels(this.effectivePaddingBottom + this.effectiveBorderBottomWidth),
                left: inset.left,
            });
        }
    }
    [paddingLeftProperty.getDefault]() {
        return {
            value: this.nativeTextViewProtected.textContainerInset.left,
            unit: 'px',
        };
    }
    [paddingLeftProperty.setNative](_value) {
        if (this._pendingPadding) {
            this._pendingPadding.left = layout.toDeviceIndependentPixels(this.effectivePaddingLeft + this.effectiveBorderLeftWidth);
        }
        else if (_hasPaddingSetNativeOverrides(this, TextView_1.prototype)) {
            const nativeView = this.nativeTextViewProtected;
            const inset = nativeView.textContainerInset;
            nativeView.textContainerInset = new UIEdgeInsets({
                top: inset.top,
                right: inset.right,
                bottom: inset.bottom,
                left: layout.toDeviceIndependentPixels(this.effectivePaddingLeft + this.effectiveBorderLeftWidth),
            });
        }
    }
    [paddingInternalProperty.setNative](_value) {
        if (_hasPaddingSetNativeOverrides(this, TextView_1.prototype)) {
            // An override owns padding application; each side applies through its own handler.
            return;
        }
        const nativeView = this.nativeTextViewProtected;
        const inset = nativeView.textContainerInset;
        this._pendingPadding = { top: inset.top, right: inset.right, bottom: inset.bottom, left: inset.left };
        this[paddingTopProperty.setNative](this.style.paddingTop);
        this[paddingRightProperty.setNative](this.style.paddingRight);
        this[paddingBottomProperty.setNative](this.style.paddingBottom);
        this[paddingLeftProperty.setNative](this.style.paddingLeft);
        nativeView.textContainerInset = new UIEdgeInsets(this._pendingPadding);
        this._pendingPadding = null;
    }
    [iosWritingToolsBehaviorProperty.setNative](value) {
        if (SDK_VERSION >= 18 && isRealDevice()) {
            this.nativeTextViewProtected.writingToolsBehavior = this._writingToolsBehaviorType(value);
        }
    }
    [iosWritingToolsAllowedInputProperty.setNative](value) {
        if (SDK_VERSION >= 18 && isRealDevice()) {
            let writingToolsInput = null;
            for (const inputType of value) {
                writingToolsInput = (writingToolsInput != null ? writingToolsInput : 0) + this._writingToolsAllowedType(inputType);
            }
            if (writingToolsInput === null) {
                writingToolsInput = 0 /* UIWritingToolsResultOptions.Default */;
            }
            this.nativeTextViewProtected.allowsEditingTextAttributes = true;
            this.nativeTextViewProtected.allowedWritingToolsResultOptions = writingToolsInput;
        }
    }
    _writingToolsBehaviorType(value) {
        switch (value) {
            case WritingToolsBehavior.Complete:
                return 1 /* UIWritingToolsBehavior.Complete */;
            case WritingToolsBehavior.Default:
                return 0 /* UIWritingToolsBehavior.Default */;
            case WritingToolsBehavior.Limited:
                return 2 /* UIWritingToolsBehavior.Limited */;
            case WritingToolsBehavior.None:
                return -1 /* UIWritingToolsBehavior.None */;
        }
    }
    _writingToolsAllowedType(value) {
        switch (value) {
            case WritingToolsAllowedInput.Default:
                return 0 /* UIWritingToolsResultOptions.Default */;
            case WritingToolsAllowedInput.List:
                return 4 /* UIWritingToolsResultOptions.List */;
            case WritingToolsAllowedInput.PlainText:
                return 1 /* UIWritingToolsResultOptions.PlainText */;
            case WritingToolsAllowedInput.RichText:
                return 2 /* UIWritingToolsResultOptions.RichText */;
        }
    }
};
TextView = TextView_1 = __decorate([
    CSSType('TextView')
], TextView);
export { TextView };
TextView.prototype.recycleNativeView = 'auto';
//# sourceMappingURL=index.ios.js.map