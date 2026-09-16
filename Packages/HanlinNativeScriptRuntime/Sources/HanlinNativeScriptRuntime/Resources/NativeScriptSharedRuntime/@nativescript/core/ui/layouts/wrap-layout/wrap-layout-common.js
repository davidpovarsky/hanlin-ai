const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
import { LayoutBase } from '../layout-base';
import { CSSType } from '../../core/view';
import { Property, makeValidator, makeParser } from '../../core/properties';
import { Length } from '../../styling/length-shared';
import { CoreTypes } from '../../../core-types';
export * from '../layout-base';
let WrapLayoutBase = class WrapLayoutBase extends LayoutBase {
};
WrapLayoutBase = __decorate([
    CSSType('WrapLayout')
], WrapLayoutBase);
export { WrapLayoutBase };
WrapLayoutBase.prototype.recycleNativeView = 'auto';
export const itemWidthProperty = new Property({
    name: 'itemWidth',
    defaultValue: 'auto',
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueConverter: Length.parse,
    valueChanged: (target, oldValue, newValue) => (target.effectiveItemWidth = Length.toDevicePixels(newValue, -1)),
});
itemWidthProperty.register(WrapLayoutBase);
export const itemHeightProperty = new Property({
    name: 'itemHeight',
    defaultValue: 'auto',
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueConverter: Length.parse,
    valueChanged: (target, oldValue, newValue) => (target.effectiveItemHeight = Length.toDevicePixels(newValue, -1)),
});
itemHeightProperty.register(WrapLayoutBase);
const converter = makeParser(makeValidator(CoreTypes.Orientation.horizontal, CoreTypes.Orientation.vertical));
export const orientationProperty = new Property({
    name: 'orientation',
    defaultValue: CoreTypes.Orientation.horizontal,
    affectsLayout: __APPLE__,
    valueConverter: converter,
});
orientationProperty.register(WrapLayoutBase);
//# sourceMappingURL=wrap-layout-common.js.map