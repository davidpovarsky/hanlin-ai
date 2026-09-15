import { Color } from '../../color';
import { Font } from '../styling/font';
import { colorProperty, fontInternalProperty } from '../styling/style-properties';
import { HtmlViewBase, htmlProperty, selectableProperty, linkColorProperty } from './html-view-common';
import { View } from '../core/view';
import { layout } from '../../utils';
import { SDK_VERSION } from '../../utils/constants';
export * from './html-view-common';
export class HtmlView extends HtmlViewBase {
    createNativeView() {
        const nativeView = UITextView.new();
        nativeView.scrollEnabled = false;
        nativeView.editable = false;
        nativeView.selectable = true;
        nativeView.userInteractionEnabled = true;
        nativeView.dataDetectorTypes = -1 /* UIDataDetectorTypes.All */;
        return nativeView;
    }
    initNativeView() {
        super.initNativeView();
        // Remove extra padding
        this.nativeViewProtected.textContainer.lineFragmentPadding = 0;
        this.nativeViewProtected.textContainerInset = UIEdgeInsetsZero;
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        const nativeView = this.nativeViewProtected;
        if (nativeView) {
            const width = layout.getMeasureSpecSize(widthMeasureSpec);
            const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
            const height = layout.getMeasureSpecSize(heightMeasureSpec);
            const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
            const desiredSize = layout.measureNativeView(nativeView, width, widthMode, height, heightMode);
            const labelWidth = widthMode === layout.AT_MOST ? Math.min(desiredSize.width, width) : desiredSize.width;
            const measureWidth = Math.max(labelWidth, this.effectiveMinWidth);
            const measureHeight = Math.max(desiredSize.height, this.effectiveMinHeight);
            const widthAndState = View.resolveSizeAndState(measureWidth, width, widthMode, 0);
            const heightAndState = View.resolveSizeAndState(measureHeight, height, heightMode, 0);
            this.setMeasuredDimension(widthAndState, heightAndState);
        }
    }
    renderWithStyles() {
        const bodyStyles = [];
        let htmlContent = this.html ?? '';
        htmlContent += '<style>';
        bodyStyles.push(`font-size: ${this.style.fontSize}px;`);
        if (this.style.fontFamily) {
            bodyStyles.push(`font-family: '${this.style.fontFamily}';`);
        }
        if (this.style.color) {
            bodyStyles.push(`color: ${this.style.color.hex};`);
        }
        htmlContent += `body {${bodyStyles.join('')}}`;
        if (this.linkColor) {
            htmlContent += `a, a:link, a:visited { color: ${this.linkColor.hex} !important; }`;
        }
        htmlContent += '</style>';
        const htmlString = NSString.stringWithString(htmlContent);
        const nsData = htmlString.dataUsingEncoding(NSUnicodeStringEncoding);
        const attributes = NSDictionary.dictionaryWithObjectForKey(NSHTMLTextDocumentType, NSDocumentTypeDocumentAttribute);
        this.nativeViewProtected.attributedText = NSAttributedString.alloc().initWithDataOptionsDocumentAttributesError(nsData, attributes, null);
        if (!this.style.color && SDK_VERSION >= 13 && UIColor.labelColor) {
            this.nativeViewProtected.textColor = UIColor.labelColor;
        }
    }
    [htmlProperty.getDefault]() {
        return '';
    }
    [htmlProperty.setNative](value) {
        this.renderWithStyles();
    }
    [selectableProperty.getDefault]() {
        return true;
    }
    [selectableProperty.setNative](value) {
        this.nativeViewProtected.selectable = value;
    }
    [colorProperty.getDefault]() {
        return this.nativeViewProtected.textColor;
    }
    [colorProperty.setNative](value) {
        const color = value instanceof Color ? value.ios : value;
        this.nativeViewProtected.textColor = color;
        this.renderWithStyles();
    }
    [linkColorProperty.setNative](value) {
        this.renderWithStyles();
    }
    [fontInternalProperty.getDefault]() {
        return this.nativeViewProtected.font;
    }
    [fontInternalProperty.setNative](value) {
        const font = value instanceof Font ? value.getUIFont(this.nativeViewProtected.font) : value;
        this.nativeViewProtected.font = font;
        this.renderWithStyles();
    }
}
//# sourceMappingURL=index.ios.js.map