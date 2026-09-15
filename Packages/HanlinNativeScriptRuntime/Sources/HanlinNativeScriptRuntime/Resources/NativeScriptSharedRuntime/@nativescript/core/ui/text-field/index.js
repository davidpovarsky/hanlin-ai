import { TextFieldBase, secureProperty } from './text-field-common';
import { textOverflowProperty, textProperty, whiteSpaceProperty } from '../text-base';
import { hintProperty, placeholderColorProperty, _updateCharactersInRangeReplacementString } from '../editable-text-base';
import { CoreTypes } from '../../core-types';
import { Color } from '../../color';
import { colorProperty, directionProperty, paddingInternalProperty, paddingTopProperty, paddingRightProperty, paddingBottomProperty, paddingLeftProperty } from '../styling/style-properties';
import { layout, isEmoji } from '../../utils';
export * from './text-field-common';
var UITextFieldDelegateImpl = (function (_super) {
    __extends(UITextFieldDelegateImpl, _super);
    function UITextFieldDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITextFieldDelegateImpl.initWithOwner = function (owner) {
        var delegate = UITextFieldDelegateImpl.new();
        delegate._owner = owner;
        return delegate;
    };
    UITextFieldDelegateImpl.prototype.textFieldShouldBeginEditing = function (textField) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.textFieldShouldBeginEditing(textField);
        }
        return true;
    };
    UITextFieldDelegateImpl.prototype.textFieldDidBeginEditing = function (textField) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.textFieldDidBeginEditing(textField);
        }
    };
    UITextFieldDelegateImpl.prototype.textFieldDidEndEditing = function (textField) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.textFieldDidEndEditing(textField);
        }
    };
    UITextFieldDelegateImpl.prototype.textFieldShouldClear = function (textField) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.textFieldShouldClear(textField);
        }
        return true;
    };
    UITextFieldDelegateImpl.prototype.textFieldShouldReturn = function (textField) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.textFieldShouldReturn(textField);
        }
        return true;
    };
    UITextFieldDelegateImpl.prototype.textFieldShouldChangeCharactersInRangeReplacementString = function (textField, range, replacementString) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            return owner.textFieldShouldChangeCharactersInRangeReplacementString(textField, range, replacementString);
        }
        return true;
    };
    UITextFieldDelegateImpl.ObjCProtocols = [UITextFieldDelegate];
    return UITextFieldDelegateImpl;
}(NSObject));
var UITextFieldImpl = (function (_super) {
    __extends(UITextFieldImpl, _super);
    function UITextFieldImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UITextFieldImpl.initWithOwner = function (owner) {
        var handler = UITextFieldImpl.new();
        handler._owner = owner;
        return handler;
    };
    UITextFieldImpl.prototype._getTextRectForBounds = function (bounds) {
        var owner = this._owner ? this._owner.deref() : null;
        if (!owner) {
            return bounds;
        }
        var size = bounds.size;
        var x = layout.toDeviceIndependentPixels(owner.effectiveBorderLeftWidth + owner.effectivePaddingLeft);
        var y = layout.toDeviceIndependentPixels(owner.effectiveBorderTopWidth + owner.effectivePaddingTop);
        var width = layout.toDeviceIndependentPixels(layout.toDevicePixels(size.width) - (owner.effectiveBorderLeftWidth + owner.effectivePaddingLeft + owner.effectivePaddingRight + owner.effectiveBorderRightWidth));
        var height = layout.toDeviceIndependentPixels(layout.toDevicePixels(size.height) - (owner.effectiveBorderTopWidth + owner.effectivePaddingTop + owner.effectivePaddingBottom + owner.effectiveBorderBottomWidth));
        return CGRectMake(x, y, width, height);
    };
    UITextFieldImpl.prototype.textRectForBounds = function (bounds) {
        return this._getTextRectForBounds(bounds);
    };
    UITextFieldImpl.prototype.editingRectForBounds = function (bounds) {
        return this._getTextRectForBounds(bounds);
    };
    return UITextFieldImpl;
}(UITextField));
export class TextField extends TextFieldBase {
    createNativeView() {
        return UITextFieldImpl.initWithOwner(new WeakRef(this));
    }
    initNativeView() {
        super.initNativeView();
        this._delegate = UITextFieldDelegateImpl.initWithOwner(new WeakRef(this));
        this.nativeViewProtected.delegate = this._delegate;
        this._applySecureWithoutAutofillTraits(this.nativeViewProtected);
    }
    disposeNativeView() {
        this._delegate = null;
        this._firstEdit = false;
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    textFieldShouldBeginEditing(textField) {
        this._firstEdit = true;
        this._applySecureWithoutAutofillTraits(textField);
        return this.editable;
    }
    textFieldDidBeginEditing(textField) {
        this.notify({ eventName: TextField.focusEvent, object: this });
    }
    textFieldDidEndEditing(textField) {
        if (this.updateTextTrigger === 'focusLost') {
            textProperty.nativeValueChange(this, textField.text);
        }
        this.dismissSoftInput();
    }
    textFieldShouldClear(textField) {
        this._firstEdit = false;
        textProperty.nativeValueChange(this, '');
        return true;
    }
    textFieldShouldReturn(textField) {
        // Called when the user presses the return button.
        if (this.closeOnReturn) {
            this.dismissSoftInput();
        }
        this.notify({ eventName: TextField.returnPressEvent, object: this });
        return true;
    }
    textFieldShouldChangeCharactersInRangeReplacementString(textField, range, replacementString) {
        this._applySecureWithoutAutofillTraits(textField);
        const delta = replacementString.length - range.length;
        if (delta > 0) {
            if (textField.text.length + delta > this.maxLength) {
                return false;
            }
        }
        if (this.updateTextTrigger === 'textChanged') {
            if (this.valueFormatter) {
                // format/replace
                const currentValue = textField.text;
                let nativeValueChange = `${textField.text}${replacementString}`;
                if (replacementString === '') {
                    // clearing when empty
                    nativeValueChange = currentValue.slice(0, delta);
                }
                const formattedValue = this.valueFormatter(nativeValueChange);
                textField.text = formattedValue;
                textProperty.nativeValueChange(this, formattedValue);
                return false;
            }
            else {
                // 1. secureTextEntry with firstEdit should not replace
                // 2. emoji's should not replace value
                // 3. convenient keyboard shortcuts should not replace value (eg, '.com')
                const shouldReplaceString = (textField.secureTextEntry && this._firstEdit) || (delta > 1 && !isEmoji(replacementString) && delta !== replacementString.length);
                if (shouldReplaceString) {
                    textProperty.nativeValueChange(this, replacementString);
                }
                else {
                    if (range.location <= textField.text.length) {
                        const newText = NSString.stringWithString(textField.text).stringByReplacingCharactersInRangeWithString(range, replacementString);
                        textProperty.nativeValueChange(this, newText);
                    }
                }
            }
        }
        if (this.formattedText) {
            _updateCharactersInRangeReplacementString(this.formattedText, range.location, range.length, replacementString);
        }
        if (this.width === 'auto') {
            // if the textfield is in auto size we need to request a layout to take the new text width into account
            this.requestLayout();
        }
        this._firstEdit = false;
        return true;
    }
    [hintProperty.getDefault]() {
        return this.nativeTextViewProtected.placeholder;
    }
    [hintProperty.setNative](value) {
        this._updateAttributedPlaceholder();
    }
    [secureProperty.getDefault]() {
        return this.nativeTextViewProtected.secureTextEntry;
    }
    [secureProperty.setNative](value) {
        this.nativeTextViewProtected.secureTextEntry = value;
        this._applySecureWithoutAutofillTraits(this.nativeTextViewProtected);
    }
    _applySecureWithoutAutofillTraits(textField) {
        if (!textField || !this.secureWithoutAutofill || !this.secure) {
            return;
        }
        let shouldReloadInputViews = false;
        if (!textField.secureTextEntry) {
            textField.secureTextEntry = true;
            shouldReloadInputViews = true;
        }
        if (textField.textContentType !== undefined && textField.textContentType !== UITextContentTypeOneTimeCode) {
            textField.textContentType = UITextContentTypeOneTimeCode;
            shouldReloadInputViews = true;
        }
        if (textField.autocorrectionType !== undefined && textField.autocorrectionType !== 1 /* UITextAutocorrectionType.No */) {
            textField.autocorrectionType = 1 /* UITextAutocorrectionType.No */;
            shouldReloadInputViews = true;
        }
        if (textField.spellCheckingType !== undefined && textField.spellCheckingType !== 1 /* UITextSpellCheckingType.No */) {
            textField.spellCheckingType = 1 /* UITextSpellCheckingType.No */;
            shouldReloadInputViews = true;
        }
        if (textField.smartDashesType !== undefined && textField.smartDashesType !== 1 /* UITextSmartDashesType.No */) {
            textField.smartDashesType = 1 /* UITextSmartDashesType.No */;
            shouldReloadInputViews = true;
        }
        if (textField.smartQuotesType !== undefined && textField.smartQuotesType !== 1 /* UITextSmartQuotesType.No */) {
            textField.smartQuotesType = 1 /* UITextSmartQuotesType.No */;
            shouldReloadInputViews = true;
        }
        if (textField.smartInsertDeleteType !== undefined && textField.smartInsertDeleteType !== 1 /* UITextSmartInsertDeleteType.No */) {
            textField.smartInsertDeleteType = 1 /* UITextSmartInsertDeleteType.No */;
            shouldReloadInputViews = true;
        }
        if (textField.passwordRules !== undefined && textField.passwordRules !== null) {
            textField.passwordRules = null;
            shouldReloadInputViews = true;
        }
        if (shouldReloadInputViews && textField.isFirstResponder) {
            textField.reloadInputViews();
        }
    }
    [colorProperty.getDefault]() {
        return {
            textColor: this.nativeTextViewProtected.textColor,
            tintColor: this.nativeTextViewProtected.tintColor,
        };
    }
    [colorProperty.setNative](value) {
        if (value instanceof Color) {
            const color = value instanceof Color ? value.ios : value;
            this.nativeTextViewProtected.textColor = color;
            this.nativeTextViewProtected.tintColor = color;
        }
        else {
            this.nativeTextViewProtected.textColor = value.textColor;
            this.nativeTextViewProtected.tintColor = value.tintColor;
        }
    }
    [placeholderColorProperty.getDefault]() {
        return null;
    }
    [placeholderColorProperty.setNative](value) {
        this._updateAttributedPlaceholder();
    }
    _updateAttributedPlaceholder() {
        let stringValue = this.hint;
        if (stringValue === null || stringValue === void 0) {
            stringValue = '';
        }
        else {
            stringValue = stringValue + '';
        }
        if (stringValue === '') {
            // we do not use empty string since initWithStringAttributes does not return proper value and
            // nativeView.attributedPlaceholder will be null
            stringValue = ' ';
        }
        const attributes = {};
        if (this.style.placeholderColor) {
            attributes[NSForegroundColorAttributeName] = this.style.placeholderColor.ios;
        }
        const attributedPlaceholder = NSAttributedString.alloc().initWithStringAttributes(stringValue, attributes);
        this.nativeTextViewProtected.attributedPlaceholder = attributedPlaceholder;
    }
    [paddingTopProperty.getDefault]() {
        return CoreTypes.zeroLength;
    }
    [paddingTopProperty.setNative](_value) {
        // Padding is realized via UITextFieldImpl.textRectForBounds method
    }
    [paddingRightProperty.getDefault]() {
        return CoreTypes.zeroLength;
    }
    [paddingRightProperty.setNative](_value) {
        // Padding is realized via UITextFieldImpl.textRectForBounds method
    }
    [paddingBottomProperty.getDefault]() {
        return CoreTypes.zeroLength;
    }
    [paddingBottomProperty.setNative](_value) {
        // Padding is realized via UITextFieldImpl.textRectForBounds method
    }
    [paddingLeftProperty.getDefault]() {
        return CoreTypes.zeroLength;
    }
    [paddingLeftProperty.setNative](_value) {
        // Padding is realized via UITextFieldImpl.textRectForBounds method
    }
    [paddingInternalProperty.setNative](_value) {
        // Padding is realized via UITextFieldImpl.textRectForBounds method
    }
    [whiteSpaceProperty.setNative](value) {
        this.adjustLineBreak();
    }
    [textOverflowProperty.setNative](value) {
        this.adjustLineBreak();
    }
    [directionProperty.setNative](value) {
        this.adjustLineBreak();
        super[directionProperty.setNative](value);
    }
    adjustLineBreak() {
        let paragraphStyle;
        switch (this.whiteSpace) {
            case 'nowrap':
                switch (this.textOverflow) {
                    case 'clip':
                        paragraphStyle = NSMutableParagraphStyle.new();
                        paragraphStyle.lineBreakMode = 2 /* NSLineBreakMode.ByClipping */;
                        break;
                    default:
                        // ellipsis
                        paragraphStyle = NSMutableParagraphStyle.new();
                        paragraphStyle.lineBreakMode = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
                        break;
                }
                break;
            case 'wrap':
            case 'normal':
                paragraphStyle = NSMutableParagraphStyle.new();
                paragraphStyle.lineBreakMode = 0 /* NSLineBreakMode.ByWordWrapping */;
                break;
        }
        if (paragraphStyle) {
            const attributedString = NSMutableAttributedString.alloc().initWithString(this.nativeViewProtected.text || '');
            attributedString.addAttributeValueRange(NSParagraphStyleAttributeName, paragraphStyle, NSRangeFromString(`{0,${attributedString.length}}`));
            this.nativeViewProtected.attributedText = attributedString;
        }
    }
}
//# sourceMappingURL=index.ios.js.map