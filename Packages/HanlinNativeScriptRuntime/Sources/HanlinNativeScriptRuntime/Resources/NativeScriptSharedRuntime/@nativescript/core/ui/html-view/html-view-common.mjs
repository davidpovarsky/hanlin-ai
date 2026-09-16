import { View, CSSType } from '../core/view';
import { booleanConverter } from '../core/view-base';
import { Property } from '../core/properties';
import { Color } from '../../color';
let HtmlViewBase = class HtmlViewBase extends View {
};
HtmlViewBase = __decorate([
    CSSType('HtmlView')
], HtmlViewBase);
export { HtmlViewBase };
HtmlViewBase.prototype.recycleNativeView = 'auto';
// TODO: Can we use Label.ios optimization for affectsLayout???
export const htmlProperty = new Property({
    name: 'html',
    defaultValue: '',
    affectsLayout: true,
});
htmlProperty.register(HtmlViewBase);
export const selectableProperty = new Property({
    name: 'selectable',
    defaultValue: true,
    valueConverter: booleanConverter,
});
selectableProperty.register(HtmlViewBase);
export const linkColorProperty = new Property({
    name: 'linkColor',
    equalityComparer: Color.equals,
    valueConverter: (value) => new Color(value),
});
linkColorProperty.register(HtmlViewBase);
//# sourceMappingURL=html-view-common.js.map