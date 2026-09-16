// Types
import { getClosestPropertyValue } from './text-base-common';
// Requires
import { Font } from '../styling/font';
import { iosAccessibilityAdjustsFontSizeProperty, iosAccessibilityMaxFontScaleProperty, iosAccessibilityMinFontScaleProperty } from '../../accessibility/accessibility-properties';
import { TextBaseCommon, textProperty, formattedTextProperty, textAlignmentProperty, textDecorationProperty, textTransformProperty, textShadowProperty, textStrokeProperty, letterSpacingProperty, lineHeightProperty, maxLinesProperty, resetSymbol } from './text-base-common';
import { Color } from '../../color';
import { Span } from './span';
import { colorProperty, fontInternalProperty, fontScaleInternalProperty } from '../styling/style-properties';
import { Length } from '../styling/length-shared';
import { isString, isNullOrUndefined } from '../../utils/types';
import { layout } from '../../utils';
import { SDK_VERSION } from '../../utils/constants';
import { CoreTypes } from '../../core-types';
export * from './text-base-common';
var UILabelClickHandlerImpl = (function (_super) {
    __extends(UILabelClickHandlerImpl, _super);
    function UILabelClickHandlerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UILabelClickHandlerImpl.initWithOwner = function (owner) {
        var handler = UILabelClickHandlerImpl.new();
        handler._owner = owner;
        return handler;
    };
    UILabelClickHandlerImpl.prototype.linkTap = function (tapGesture) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var nativeView = owner.nativeTextViewProtected instanceof UIButton ? owner.nativeTextViewProtected.titleLabel : owner.nativeTextViewProtected;
            var offsetXMultiplier = void 0;
            switch (owner.textAlignment) {
                case "center":
                    offsetXMultiplier = 0.5;
                    break;
                case "right":
                    offsetXMultiplier = 1;
                    break;
                default:
                    offsetXMultiplier = 0;
                    break;
            }
            var offsetYMultiplier = 0.5;
            var layoutManager = NSLayoutManager.alloc().init();
            var textContainer = NSTextContainer.alloc().initWithSize(CGSizeZero);
            var textStorage = NSTextStorage.alloc().initWithAttributedString(nativeView.attributedText);
            layoutManager.addTextContainer(textContainer);
            textStorage.addLayoutManager(layoutManager);
            textContainer.lineFragmentPadding = 0;
            if (nativeView instanceof UITextView) {
                textContainer.lineBreakMode = nativeView.textContainer.lineBreakMode;
                textContainer.maximumNumberOfLines = nativeView.textContainer.maximumNumberOfLines;
            }
            else {
                if (!(nativeView instanceof UITextField)) {
                    textContainer.lineBreakMode = nativeView.lineBreakMode;
                    textContainer.maximumNumberOfLines = nativeView.numberOfLines;
                }
            }
            var labelSize = nativeView.bounds.size;
            textContainer.size = labelSize;
            var locationOfTouchInLabel = tapGesture.locationInView(nativeView);
            var textBoundingBox = layoutManager.usedRectForTextContainer(textContainer);
            var textContainerOffset = CGPointMake((labelSize.width - textBoundingBox.size.width) * offsetXMultiplier - textBoundingBox.origin.x, (labelSize.height - textBoundingBox.size.height) * offsetYMultiplier - textBoundingBox.origin.y);
            var locationOfTouchInTextContainer = CGPointMake(locationOfTouchInLabel.x - textContainerOffset.x, locationOfTouchInLabel.y - textContainerOffset.y);
            if (CGRectContainsPoint(textBoundingBox, locationOfTouchInTextContainer)) {
                var glyphIndex = layoutManager.glyphIndexForPointInTextContainerFractionOfDistanceThroughGlyph(locationOfTouchInTextContainer, textContainer, null);
                var glyphRect = layoutManager.boundingRectForGlyphRangeInTextContainer({
                    location: glyphIndex,
                    length: 1,
                }, textContainer);
                if (CGRectContainsPoint(glyphRect, locationOfTouchInTextContainer)) {
                    var indexOfCharacter = layoutManager.characterIndexForGlyphAtIndex(glyphIndex);
                    var span = null;
                    for (var i = 0; i < owner._spanRanges.length; i++) {
                        var range = owner._spanRanges[i];
                        if (range.location <= indexOfCharacter && range.location + range.length > indexOfCharacter) {
                            if (owner.formattedText && owner.formattedText.spans.length > i) {
                                span = owner.formattedText.spans.getItem(i);
                            }
                            break;
                        }
                    }
                    if (span && span.tappable) {
                        span._emit(Span.linkTapEvent);
                    }
                }
            }
        }
    };
    UILabelClickHandlerImpl.ObjCExposedMethods = {
        linkTap: { returns: interop.types.void, params: [interop.types.id] },
    };
    return UILabelClickHandlerImpl;
}(NSObject));
export class TextBase extends TextBaseCommon {
    constructor() {
        super(...arguments);
        this._tappable = false;
    }
    get nativeTextViewProtected() {
        return super.nativeTextViewProtected;
    }
    initNativeView() {
        super.initNativeView();
        this._setTappableState(false);
    }
    disposeNativeView() {
        super.disposeNativeView();
        this._tappable = false;
        this._linkTapHandler = null;
        this._tapGestureRecognizer = null;
    }
    _setTappableState(tappable) {
        if (this._tappable !== tappable) {
            const nativeTextView = this.nativeTextViewProtected;
            this._tappable = tappable;
            if (this._tappable) {
                const tapHandler = UILabelClickHandlerImpl.initWithOwner(new WeakRef(this));
                // Associate handler with menuItem or it will get collected by JSC
                this._linkTapHandler = tapHandler;
                this._tapGestureRecognizer = UITapGestureRecognizer.alloc().initWithTargetAction(this._linkTapHandler, 'linkTap');
                nativeTextView.addGestureRecognizer(this._tapGestureRecognizer);
            }
            else {
                nativeTextView.removeGestureRecognizer(this._tapGestureRecognizer);
                this._linkTapHandler = null;
                this._tapGestureRecognizer = null;
            }
        }
    }
    [textProperty.getDefault]() {
        return resetSymbol;
    }
    [textProperty.setNative](value) {
        const reset = value === resetSymbol;
        if (!reset && this.formattedText) {
            return;
        }
        this._setNativeText(reset);
        this._requestLayoutOnTextChanged();
    }
    [formattedTextProperty.setNative](value) {
        this._setNativeText();
        this._setTappableState(isStringTappable(value));
        textProperty.nativeValueChange(this, !value ? '' : value.toString());
        this._requestLayoutOnTextChanged();
    }
    [colorProperty.getDefault]() {
        const nativeView = this.nativeTextViewProtected;
        if (nativeView instanceof UIButton) {
            return nativeView.titleColorForState(0 /* UIControlState.Normal */);
        }
        else {
            return nativeView.textColor;
        }
    }
    [colorProperty.setNative](value) {
        const color = (value instanceof Color || (value && value._isColor) || (value && value.ios instanceof UIColor)) ? value.ios : value;
        this._setColor(color);
    }
    [fontInternalProperty.getDefault]() {
        let nativeView = this.nativeTextViewProtected;
        nativeView = nativeView instanceof UIButton ? nativeView.titleLabel : nativeView;
        return nativeView.font;
    }
    [fontInternalProperty.setNative](value) {
        if (!(value instanceof Font) || !this.formattedText) {
            let nativeView = this.nativeTextViewProtected;
            nativeView = nativeView instanceof UIButton ? nativeView.titleLabel : nativeView;
            const font = (value instanceof Font || (value && typeof value.getUIFont === 'function')) ? value.getUIFont(nativeView.font) : value;
            nativeView.font = font;
        }
    }
    [fontScaleInternalProperty.setNative](value) {
        const nativeView = this.nativeTextViewProtected instanceof UIButton ? this.nativeTextViewProtected.titleLabel : this.nativeTextViewProtected;
        const font = this.style.fontInternal || Font.default.withFontSize(nativeView.font.pointSize);
        const finalValue = adjustMinMaxFontScale(value, this);
        // Request layout on font scale as it's not done automatically
        if (font.fontScale !== finalValue) {
            this.style.fontInternal = font.withFontScale(finalValue);
            this.requestLayout();
        }
        else {
            if (!this.style.fontInternal) {
                this.style.fontInternal = font;
            }
        }
    }
    [iosAccessibilityAdjustsFontSizeProperty.setNative](value) {
        this[fontScaleInternalProperty.setNative](this.style.fontScaleInternal);
    }
    [iosAccessibilityMinFontScaleProperty.setNative](value) {
        this[fontScaleInternalProperty.setNative](this.style.fontScaleInternal);
    }
    [iosAccessibilityMaxFontScaleProperty.setNative](value) {
        this[fontScaleInternalProperty.setNative](this.style.fontScaleInternal);
    }
    [textAlignmentProperty.setNative](value) {
        const nativeView = this.nativeTextViewProtected;
        switch (value) {
            case 'left':
                nativeView.textAlignment = 0 /* NSTextAlignment.Left */;
                break;
            case 'center':
                nativeView.textAlignment = 1 /* NSTextAlignment.Center */;
                break;
            case 'right':
                nativeView.textAlignment = 2 /* NSTextAlignment.Right */;
                break;
            case 'justify':
                nativeView.textAlignment = 3 /* NSTextAlignment.Justified */;
                break;
            default:
                nativeView.textAlignment = 4 /* NSTextAlignment.Natural */;
                break;
        }
    }
    [textDecorationProperty.setNative](value) {
        this._setNativeText();
    }
    [textTransformProperty.setNative](value) {
        this._setNativeText();
    }
    [textStrokeProperty.setNative](value) {
        this._setNativeText();
    }
    [letterSpacingProperty.setNative](value) {
        this._setNativeText();
    }
    [lineHeightProperty.setNative](value) {
        this._setNativeText();
    }
    [textShadowProperty.setNative](value) {
        this._setShadow(value);
    }
    [maxLinesProperty.setNative](value) {
        const nativeTextViewProtected = this.nativeTextViewProtected;
        const numberOfLines = this.whiteSpace !== CoreTypes.WhiteSpace.nowrap ? value : 1;
        const ellipsisType = this.direction === CoreTypes.LayoutDirection.rtl ? 3 /* NSLineBreakMode.ByTruncatingHead */ : 4 /* NSLineBreakMode.ByTruncatingTail */;
        if (nativeTextViewProtected instanceof UITextView) {
            nativeTextViewProtected.textContainer.maximumNumberOfLines = numberOfLines;
            if (value !== 0) {
                nativeTextViewProtected.textContainer.lineBreakMode = ellipsisType;
            }
            else {
                nativeTextViewProtected.textContainer.lineBreakMode = 0 /* NSLineBreakMode.ByWordWrapping */;
            }
        }
        else if (nativeTextViewProtected instanceof UILabel) {
            nativeTextViewProtected.numberOfLines = numberOfLines;
            nativeTextViewProtected.lineBreakMode = ellipsisType;
        }
        else if (nativeTextViewProtected instanceof UIButton) {
            nativeTextViewProtected.titleLabel.numberOfLines = numberOfLines;
        }
    }
    _setColor(color) {
        const nativeColor = (color && color.ios instanceof UIColor) ? color.ios : color;
        if (this.nativeTextViewProtected instanceof UIButton) {
            this.nativeTextViewProtected.setTitleColorForState(nativeColor, 0 /* UIControlState.Normal */);
            this.nativeTextViewProtected.titleLabel.textColor = nativeColor;
        }
        else {
            this.nativeTextViewProtected.textColor = nativeColor;
        }
    }
    _animationWrap(fn) {
        const shouldAnimate = this.iosTextAnimation === 'inherit' ? TextBase.iosTextAnimationFallback : this.iosTextAnimation;
        if (shouldAnimate) {
            fn();
        }
        else {
            UIView.performWithoutAnimation(fn);
        }
    }
    _setNativeText(reset = false) {
        this._animationWrap(() => {
            if (reset) {
                const nativeView = this.nativeTextViewProtected;
                if (nativeView instanceof UIButton) {
                    // Clear attributedText or title won't be affected.
                    nativeView.setAttributedTitleForState(null, 0 /* UIControlState.Normal */);
                    nativeView.setTitleForState(null, 0 /* UIControlState.Normal */);
                }
                else {
                    // Clear attributedText or text won't be affected.
                    nativeView.attributedText = null;
                    nativeView.text = null;
                }
                return;
            }
            const letterSpacing = this.style.letterSpacing ? this.style.letterSpacing : 0;
            const lineHeight = this.style.lineHeight ? this.style.lineHeight : 0;
            if (this.formattedText) {
                this.nativeTextViewProtected.nativeScriptSetFormattedTextDecorationAndTransformLetterSpacingLineHeight(this.getFormattedStringDetails(this.formattedText), letterSpacing, lineHeight);
            }
            else {
                // console.log('setTextDecorationAndTransform...')
                const text = getTransformedText(isNullOrUndefined(this.text) ? '' : `${this.text}`, this.textTransform);
                this.nativeTextViewProtected.nativeScriptSetTextDecorationAndTransformTextDecorationLetterSpacingLineHeight(text, this.style.textDecoration || '', letterSpacing, lineHeight);
                if (!this.style?.color && SDK_VERSION >= 13 && UIColor.labelColor) {
                    this._setColor(UIColor.labelColor);
                }
            }
            if (this.style?.textStroke) {
                this.nativeTextViewProtected.nativeScriptSetFormattedTextStrokeColor(Length.toDevicePixels(this.style.textStroke.width, 0), this.style.textStroke.color.ios);
            }
        });
    }
    createFormattedTextNative(value) {
        return NativeScriptUtils.createMutableStringWithDetails(this.getFormattedStringDetails(value));
    }
    getFormattedStringDetails(formattedString) {
        const details = {
            spans: [],
        };
        this._spanRanges = [];
        if (formattedString && formattedString.parent) {
            for (let i = 0, spanStart = 0, length = formattedString.spans.length; i < length; i++) {
                const span = formattedString.spans.getItem(i);
                const text = span.text;
                const textTransform = formattedString.parent.textTransform;
                let spanText = isNullOrUndefined(text) ? '' : `${text}`;
                if (textTransform !== 'none' && textTransform !== 'initial') {
                    spanText = getTransformedText(spanText, textTransform);
                }
                details.spans.push(this.createMutableStringDetails(span, spanText, spanStart));
                this._spanRanges.push({
                    location: spanStart,
                    length: spanText.length,
                });
                spanStart += spanText.length;
            }
        }
        return details;
    }
    createMutableStringDetails(span, text, index) {
        const fontScale = adjustMinMaxFontScale(span.style.fontScaleInternal, span);
        const font = new Font(span.style.fontFamily, span.style.fontSize, span.style.fontStyle, span.style.fontWeight, fontScale, span.style.fontVariationSettings);
        const iosFont = font.getUIFont(this.nativeTextViewProtected.font);
        // Use span or formatted string color
        const backgroundColor = span.style.backgroundColor || span.parent.backgroundColor;
        return {
            text,
            iosFont,
            color: span.color ? span.color.ios : null,
            backgroundColor: backgroundColor ? backgroundColor.ios : null,
            textDecoration: getClosestPropertyValue(textDecorationProperty, span),
            baselineOffset: this.getBaselineOffset(iosFont, span.style.verticalAlignment),
            index,
        };
    }
    createMutableStringForSpan(span, text) {
        const details = this.createMutableStringDetails(span, text);
        return NativeScriptUtils.createMutableStringForSpanFontColorBackgroundColorTextDecorationBaselineOffset(details.text, details.iosFont, details.color, details.backgroundColor, details.textDecoration, details.baselineOffset);
    }
    getBaselineOffset(font, align) {
        if (!align || ['stretch', 'baseline'].includes(align)) {
            return 0;
        }
        if (align === 'top') {
            return -this.fontSize - font.descender - font.ascender - font.leading / 2;
        }
        if (align === 'bottom') {
            return font.descender + font.leading / 2;
        }
        if (align === 'text-top') {
            return -this.fontSize - font.descender - font.ascender;
        }
        if (align === 'text-bottom') {
            return font.descender;
        }
        if (align === 'middle') {
            return (font.descender - font.ascender) / 2 - font.descender;
        }
        if (align === 'sup') {
            return -this.fontSize * 0.4;
        }
        if (align === 'sub') {
            return (font.descender - font.ascender) * 0.4;
        }
    }
    _setShadow(value) {
        const layer = this.nativeTextViewProtected.layer;
        if (isNullOrUndefined(value)) {
            // clear the text shadow
            layer.shadowOpacity = 0;
            layer.shadowRadius = 0;
            layer.shadowColor = UIColor.clearColor;
            layer.shadowOffset = CGSizeMake(0, 0);
            return;
        }
        // shadow opacity is handled on the shadow's color instance
        layer.shadowOpacity = value.color?.a ? value.color.a / 255 : 1;
        layer.shadowColor = value.color.ios.CGColor;
        layer.shadowRadius = layout.toDeviceIndependentPixels(Length.toDevicePixels(value.blurRadius, 0));
        // prettier-ignore
        layer.shadowOffset = CGSizeMake(layout.toDeviceIndependentPixels(Length.toDevicePixels(value.offsetX, 0)), layout.toDeviceIndependentPixels(Length.toDevicePixels(value.offsetY, 0)));
        layer.masksToBounds = false;
        // NOTE: generally should not need shouldRasterize
        // however for various detailed animation work which involves text-shadow applicable layers, we may want to give users the control of enabling this with text-shadow
        // if (!(this.nativeTextViewProtected instanceof UITextView)) {
        //   layer.shouldRasterize = true;
        // }
    }
}
export function getTransformedText(text, textTransform) {
    if (!text || !isString(text)) {
        return '';
    }
    // Use the NSString localized properties to get localized transformations.
    // This will respect the locale set by native apis or the localize plugins.
    switch (textTransform) {
        case 'uppercase':
            return NSStringFromNSAttributedString(text).localizedUppercaseString;
        case 'lowercase':
            return NSStringFromNSAttributedString(text).localizedLowercaseString;
        case 'capitalize':
            return NSStringFromNSAttributedString(text).localizedCapitalizedString;
        default:
            return text;
    }
}
function NSStringFromNSAttributedString(source) {
    return NSString.stringWithString((source instanceof NSAttributedString && source.string) || source);
}
function isStringTappable(formattedString) {
    if (!formattedString) {
        return false;
    }
    for (let i = 0, length = formattedString.spans.length; i < length; i++) {
        const span = formattedString.spans.getItem(i);
        if (span.tappable) {
            return true;
        }
    }
    return false;
}
function adjustMinMaxFontScale(value, view) {
    let finalValue;
    if (view.iosAccessibilityAdjustsFontSize) {
        finalValue = value;
        if (view.iosAccessibilityMinFontScale && view.iosAccessibilityMinFontScale > value) {
            finalValue = view.iosAccessibilityMinFontScale;
        }
        if (view.iosAccessibilityMaxFontScale && view.iosAccessibilityMaxFontScale < value) {
            finalValue = view.iosAccessibilityMaxFontScale;
        }
    }
    else {
        finalValue = 1.0;
    }
    return finalValue;
}
//# sourceMappingURL=index.ios.js.map