import { profile } from '../../profiling';
import { View, CSSType } from '../core/view';
import { ViewBase, booleanConverter } from '../core/view-base';
import { Trace } from '../../trace';
import { ShorthandProperty, CssProperty, Property } from '../core/properties';
import { unsetValue } from '../core/properties/property-shared';
import { horizontalAlignmentProperty, verticalAlignmentProperty } from '../styling/style-properties';
import { Length } from '../styling/length-shared';
import { Style } from '../styling/style';
let ActionBarBase = class ActionBarBase extends View {
    disposeNativeView() {
        super.disposeNativeView();
    }
    get navigationButton() {
        return this._navigationButton;
    }
    set navigationButton(value) {
        if (this._navigationButton !== value) {
            if (this._navigationButton) {
                this._removeView(this._navigationButton);
                this._navigationButton.actionBar = undefined;
            }
            this._navigationButton = value;
            if (this._navigationButton) {
                this._navigationButton.actionBar = this;
                this._addView(this._navigationButton);
            }
            this.update();
        }
    }
    get actionItems() {
        return this._actionItems;
    }
    set actionItems(value) {
        throw new Error('actionItems property is read-only');
    }
    get titleView() {
        return this._titleView;
    }
    set titleView(value) {
        if (this._titleView !== value) {
            if (this._titleView) {
                this._removeView(this._titleView);
                this._titleView.style[horizontalAlignmentProperty.cssName] = unsetValue;
                this._titleView.style[verticalAlignmentProperty.cssName] = unsetValue;
            }
            this._titleView = value;
            if (value) {
                // Addview will reset CSS properties so we first add it then set aligments with lowest priority.
                this._addView(value);
                const style = value.style;
                if (!horizontalAlignmentProperty.isSet(style)) {
                    style[horizontalAlignmentProperty.cssName] = 'center';
                }
                if (!verticalAlignmentProperty.isSet(style)) {
                    style[verticalAlignmentProperty.cssName] = 'middle';
                }
            }
            this.update();
        }
    }
    get androidContentInset() {
        return this.style.androidContentInset;
    }
    set androidContentInset(value) {
        this.style.androidContentInset = value;
    }
    get androidContentInsetLeft() {
        return this.style.androidContentInsetLeft;
    }
    set androidContentInsetLeft(value) {
        this.style.androidContentInsetLeft = value;
    }
    get androidContentInsetRight() {
        return this.style.androidContentInsetRight;
    }
    set androidContentInsetRight(value) {
        this.style.androidContentInsetRight = value;
    }
    // @ts-ignore
    get ios() {
        return undefined;
    }
    // @ts-ignore
    get android() {
        return undefined;
    }
    get _childrenCount() {
        let actionViewsCount = 0;
        this._actionItems?.getItems().forEach((actionItem) => {
            if (actionItem.actionView) {
                actionViewsCount++;
            }
        });
        return actionViewsCount + (this.titleView ? 1 : 0);
    }
    constructor() {
        super();
        // prefer large titles
        this.iosLargeTitle = false;
        // show bottom border shadow (always defaulted to true)
        this.iosShadow = true;
        this._actionItems = new ActionItems(this);
    }
    update() {
        //
    }
    _onTitlePropertyChanged() {
        //
    }
    _addArrayFromBuilder(name, value) {
        if (name === 'actionItems') {
            this.actionItems?.setItems(value);
        }
    }
    eachChildView(callback) {
        const titleView = this.titleView;
        if (titleView) {
            callback(titleView);
        }
    }
    eachChild(callback) {
        const titleView = this.titleView;
        if (titleView) {
            callback(titleView);
        }
        const navigationButton = this._navigationButton;
        if (navigationButton) {
            callback(navigationButton);
        }
        this.actionItems?.getItems().forEach((actionItem) => {
            callback(actionItem);
        });
    }
    _isEmpty() {
        if (this.title || this.titleView || (this.android && this.android.icon) || this.navigationButton || this.actionItems?.getItems().length > 0) {
            return false;
        }
        return true;
    }
};
ActionBarBase = __decorate([
    CSSType('ActionBar'),
    __metadata("design:paramtypes", [])
], ActionBarBase);
export { ActionBarBase };
export class ActionItems {
    constructor(actionBar) {
        this._items = new Array();
        this._actionBar = actionBar;
    }
    addItem(item) {
        if (!item) {
            throw new Error('Cannot add empty item');
        }
        this._items.push(item);
        item.actionBar = this._actionBar;
        this._actionBar._addView(item);
        this.invalidate();
    }
    removeItem(item) {
        if (!item) {
            throw new Error('Cannot remove empty item');
        }
        const itemIndex = this._items.indexOf(item);
        if (itemIndex < 0) {
            throw new Error('Cannot find item to remove');
        }
        this._items.splice(itemIndex, 1);
        this._actionBar._removeView(item);
        item.actionBar = undefined;
        this.invalidate();
    }
    getItems() {
        return this._items.slice();
    }
    getVisibleItems() {
        const visibleItems = [];
        this._items.forEach((item) => {
            if (isVisible(item)) {
                visibleItems.push(item);
            }
        });
        return visibleItems;
    }
    getItemAt(index) {
        if (index < 0 || index >= this._items.length) {
            return undefined;
        }
        return this._items[index];
    }
    setItems(items) {
        // Remove all existing items
        while (this._items.length > 0) {
            this.removeItem(this._items[this._items.length - 1]);
        }
        // Add new items
        for (let i = 0; i < items.length; i++) {
            this.addItem(items[i]);
        }
        this.invalidate();
    }
    invalidate() {
        if (this._actionBar) {
            this._actionBar.update();
        }
    }
}
export class ActionItemBase extends ViewBase {
    get actionView() {
        return this._actionView;
    }
    set actionView(value) {
        if (this._actionView !== value) {
            if (this._actionView) {
                this._actionView.style[horizontalAlignmentProperty.cssName] = unsetValue;
                this._actionView.style[verticalAlignmentProperty.cssName] = unsetValue;
                this._removeView(this._actionView);
            }
            this._actionView = value;
            if (this._actionView) {
                this._addView(this._actionView);
            }
            if (this._actionBar) {
                this._actionBar.update();
            }
        }
    }
    get actionBar() {
        return this._actionBar;
    }
    set actionBar(value) {
        if (value !== this._actionBar) {
            this._actionBar = value;
        }
    }
    onLoaded() {
        if (this._actionView) {
            this._actionView.style[horizontalAlignmentProperty.cssName] = 'center';
            this._actionView.style[verticalAlignmentProperty.cssName] = 'middle';
        }
        super.onLoaded();
    }
    _raiseTap() {
        this._emit(ActionItemBase.tapEvent);
    }
    _addChildFromBuilder(name, value) {
        this.actionView = value;
    }
    _onVisibilityChanged(visibility) {
        if (this.actionBar) {
            this.actionBar.update();
        }
    }
    eachChild(callback) {
        if (this._actionView) {
            callback(this._actionView);
        }
    }
}
ActionItemBase.tapEvent = 'tap';
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], ActionItemBase.prototype, "onLoaded", null);
export function isVisible(item) {
    return item.visibility === 'visible';
}
function onTitlePropertyChanged(actionBar, oldValue, newValue) {
    actionBar._onTitlePropertyChanged();
}
export const titleProperty = new Property({
    name: 'title',
    valueChanged: onTitlePropertyChanged,
});
titleProperty.register(ActionBarBase);
function onItemChanged(item, oldValue, newValue) {
    if (item.actionBar) {
        item.actionBar.update();
    }
}
function onVisibilityChanged(item, oldValue, newValue) {
    item._onVisibilityChanged(newValue);
}
export function traceMissingIcon(icon) {
    Trace.write('Could not load action bar icon: ' + icon, Trace.categories.Error, Trace.messageType.error);
}
function convertToContentInset(value) {
    if (typeof value === 'string' && value !== 'auto') {
        const insets = value.split(/[ ,]+/);
        return [
            [androidContentInsetLeftProperty, Length.parse(insets[0])],
            [androidContentInsetRightProperty, Length.parse(insets[1] || insets[0])],
        ];
    }
    else {
        return [
            [androidContentInsetLeftProperty, value],
            [androidContentInsetRightProperty, value],
        ];
    }
}
export const iosIconRenderingModeProperty = new Property({ name: 'iosIconRenderingMode', defaultValue: 'alwaysOriginal' });
iosIconRenderingModeProperty.register(ActionBarBase);
export const iosLargeTitleProperty = new Property({ name: 'iosLargeTitle', defaultValue: false, valueConverter: booleanConverter });
iosLargeTitleProperty.register(ActionBarBase);
export const iosShadowProperty = new Property({ name: 'iosShadow', defaultValue: true, valueConverter: booleanConverter });
iosShadowProperty.register(ActionBarBase);
export const textProperty = new Property({
    name: 'text',
    defaultValue: '',
    valueChanged: onItemChanged,
});
textProperty.register(ActionItemBase);
export const iconProperty = new Property({
    name: 'icon',
    valueChanged: onItemChanged,
});
iconProperty.register(ActionItemBase);
export const visibilityProperty = new Property({
    name: 'visibility',
    defaultValue: 'visible',
    valueChanged: onVisibilityChanged,
});
visibilityProperty.register(ActionItemBase);
export const flatProperty = new Property({
    name: 'flat',
    defaultValue: false,
    valueConverter: booleanConverter,
});
flatProperty.register(ActionBarBase);
const androidContentInsetProperty = new ShorthandProperty({
    name: 'androidContentInset',
    cssName: 'android-content-inset',
    getter: function () {
        if (Length.equals(this.androidContentInsetLeft, this.androidContentInsetRight)) {
            return this.androidContentInsetLeft;
        }
        return `${Length.convertToString(this.androidContentInsetLeft)} ${Length.convertToString(this.androidContentInsetRight)}`;
    },
    converter: convertToContentInset,
});
androidContentInsetProperty.register(Style);
export const androidContentInsetLeftProperty = new CssProperty({
    name: 'androidContentInsetLeft',
    cssName: 'android-content-inset-left',
    defaultValue: 'auto',
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectiveContentInsetLeft = Length.toDevicePixels(newValue);
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
androidContentInsetLeftProperty.register(Style);
export const androidContentInsetRightProperty = new CssProperty({
    name: 'androidContentInsetRight',
    cssName: 'android-content-inset-right',
    defaultValue: 'auto',
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectiveContentInsetRight = Length.toDevicePixels(newValue);
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
androidContentInsetRightProperty.register(Style);
//# sourceMappingURL=action-bar-common.js.map