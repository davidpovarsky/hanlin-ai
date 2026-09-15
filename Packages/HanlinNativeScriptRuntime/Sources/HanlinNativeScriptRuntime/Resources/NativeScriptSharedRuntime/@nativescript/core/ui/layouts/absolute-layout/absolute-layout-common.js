import { LayoutBase } from '../layout-base';
import { CoreTypes } from '../../../core-types';
import { View, CSSType } from '../../core/view';
import { Property } from '../../core/properties';
import { Length } from '../../styling/length-shared';
export * from '../layout-base';
View.prototype.effectiveLeft = 0;
View.prototype.effectiveTop = 0;
function validateArgs(element) {
    if (!element) {
        throw new Error('element cannot be null or undefinied.');
    }
    return element;
}
let AbsoluteLayoutBase = class AbsoluteLayoutBase extends LayoutBase {
    // TODO: Do we still need this? it can be get like view.left
    static getLeft(element) {
        return validateArgs(element).left;
    }
    // TODO: Do we still need this? it can be set like view.left=value
    static setLeft(element, value) {
        validateArgs(element).left = value;
    }
    // TODO: Do we still need this? it can be get like view.top
    static getTop(element) {
        return validateArgs(element).top;
    }
    // TODO: Do we still need this? it can be set like view.top=value
    static setTop(element, value) {
        validateArgs(element).top = value;
    }
    onLeftChanged(view, oldValue, newValue) {
        //
    }
    onTopChanged(view, oldValue, newValue) {
        //
    }
};
AbsoluteLayoutBase = __decorate([
    CSSType('AbsoluteLayout')
], AbsoluteLayoutBase);
export { AbsoluteLayoutBase };
AbsoluteLayoutBase.prototype.recycleNativeView = 'auto';
export const leftProperty = new Property({
    name: 'left',
    defaultValue: CoreTypes.zeroLength,
    valueChanged: (target, oldValue, newValue) => {
        target.effectiveLeft = Length.toDevicePixels(newValue, 0);
        const layout = target.parent;
        if (layout instanceof AbsoluteLayoutBase) {
            layout.onLeftChanged(target, oldValue, newValue);
        }
    },
    equalityComparer: Length.equals,
    valueConverter: Length.parse,
});
leftProperty.register(View);
export const topProperty = new Property({
    name: 'top',
    defaultValue: CoreTypes.zeroLength,
    valueChanged: (target, oldValue, newValue) => {
        target.effectiveTop = Length.toDevicePixels(newValue, 0);
        const layout = target.parent;
        if (layout instanceof AbsoluteLayoutBase) {
            layout.onTopChanged(target, oldValue, newValue);
        }
    },
    equalityComparer: Length.equals,
    valueConverter: Length.parse,
});
topProperty.register(View);
//# sourceMappingURL=absolute-layout-common.js.map