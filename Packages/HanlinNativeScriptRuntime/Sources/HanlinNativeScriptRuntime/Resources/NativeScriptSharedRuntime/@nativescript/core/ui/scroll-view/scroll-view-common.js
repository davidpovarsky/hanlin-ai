const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
var ScrollViewBase_1;
import { ContentView } from '../content-view';
import { Property, makeParser, makeValidator } from '../core/properties';
import { CSSType } from '../core/view';
import { booleanConverter } from '../core/view-base';
import { CoreTypes } from '../../core-types';
let ScrollViewBase = ScrollViewBase_1 = class ScrollViewBase extends ContentView {
    constructor() {
        super(...arguments);
        this._addedScrollEvent = false;
    }
    addEventListener(eventName, callback, thisArg, once) {
        const hasExistingScrollListeners = this.hasListeners(ScrollViewBase_1.scrollEvent);
        super.addEventListener(eventName, callback, thisArg, once);
        // This indicates that a scroll listener was added for first time
        if (!hasExistingScrollListeners && this.hasListeners(ScrollViewBase_1.scrollEvent)) {
            this._addedScrollEvent = true;
            if (this.nativeViewProtected) {
                this.attachNative();
            }
        }
    }
    removeEventListener(eventName, callback, thisArg) {
        const hasExistingScrollListeners = this.hasListeners(ScrollViewBase_1.scrollEvent);
        super.removeEventListener(eventName, callback, thisArg);
        // This indicates that the final scroll listener was removed
        if (hasExistingScrollListeners && !this.hasListeners(ScrollViewBase_1.scrollEvent)) {
            this._addedScrollEvent = false;
            if (this.nativeViewProtected) {
                this.detachNative();
            }
        }
    }
    initNativeView() {
        super.initNativeView();
        if (this._addedScrollEvent) {
            this.attachNative();
        }
    }
    disposeNativeView() {
        if (this._addedScrollEvent) {
            this.detachNative();
        }
        super.disposeNativeView();
    }
    attachNative() {
        //
    }
    detachNative() {
        //
    }
    get horizontalOffset() {
        return 0;
    }
    get verticalOffset() {
        return 0;
    }
    get scrollableWidth() {
        return 0;
    }
    get scrollableHeight() {
        return 0;
    }
};
ScrollViewBase.scrollEvent = 'scroll';
ScrollViewBase = ScrollViewBase_1 = __decorate([
    CSSType('ScrollView')
], ScrollViewBase);
export { ScrollViewBase };
const converter = makeParser(makeValidator(CoreTypes.Orientation.horizontal, CoreTypes.Orientation.vertical));
export const orientationProperty = new Property({
    name: 'orientation',
    defaultValue: CoreTypes.Orientation.vertical,
    affectsLayout: true,
    valueChanged: (target, oldValue, newValue) => {
        target._onOrientationChanged();
    },
    valueConverter: converter,
});
orientationProperty.register(ScrollViewBase);
export const scrollBarIndicatorVisibleProperty = new Property({
    name: 'scrollBarIndicatorVisible',
    defaultValue: true,
    valueConverter: booleanConverter,
});
scrollBarIndicatorVisibleProperty.register(ScrollViewBase);
export const isScrollEnabledProperty = new Property({
    name: 'isScrollEnabled',
    defaultValue: true,
    valueConverter: booleanConverter,
});
isScrollEnabledProperty.register(ScrollViewBase);
const insetAdjustmentConverter = makeParser(makeValidator('never', 'automatic', 'scrollableAxes', 'always'));
export const iosContentInsetAdjustmentBehaviorProperty = new Property({
    name: 'iosContentInsetAdjustmentBehavior',
    defaultValue: 'never',
    affectsLayout: __APPLE__,
    valueConverter: insetAdjustmentConverter,
});
iosContentInsetAdjustmentBehaviorProperty.register(ScrollViewBase);
//# sourceMappingURL=scroll-view-common.js.map