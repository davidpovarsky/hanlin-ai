import { SegmentedBarItemBase, SegmentedBarBase, selectedIndexProperty, itemsProperty, selectedBackgroundColorProperty } from './segmented-bar-common';
import { colorProperty, fontInternalProperty } from '../styling/style-properties';
import { Color } from '../../color';
import { Trace } from '../../trace';
import { SDK_VERSION } from '../../utils';
export * from './segmented-bar-common';
export class SegmentedBarItem extends SegmentedBarItemBase {
    _update() {
        const parent = this.parent;
        if (parent?.ios) {
            const tabIndex = parent.items.indexOf(this);
            let title = this.title;
            title = title === null || title === undefined ? '' : title;
            parent.ios.setTitleForSegmentAtIndex(title, tabIndex);
        }
    }
}
export class SegmentedBar extends SegmentedBarBase {
    createNativeView() {
        return UISegmentedControl.new();
    }
    initNativeView() {
        super.initNativeView();
        this._selectionHandler = SelectionHandlerImpl.initWithOwner(new WeakRef(this));
        this.nativeViewProtected.addTargetActionForControlEvents(this._selectionHandler, 'selected', 4096 /* UIControlEvents.ValueChanged */);
    }
    disposeNativeView() {
        this._selectionHandler = null;
        super.disposeNativeView();
    }
    onLoaded() {
        super.onLoaded();
        // Force background redraw to ensure border radius is applied.
        // This fixes the visual glitch where backgroundColor initially has sharp corners.
        if (this.nativeBackgroundState === 'invalid') {
            this._redrawNativeBackground(this.style.backgroundInternal);
        }
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    [selectedIndexProperty.getDefault]() {
        return -1;
    }
    [selectedIndexProperty.setNative](value) {
        this.ios.selectedSegmentIndex = value;
    }
    [itemsProperty.getDefault]() {
        return null;
    }
    [itemsProperty.setNative](value) {
        const segmentedControl = this.ios;
        segmentedControl.removeAllSegments();
        const newItems = value;
        if (newItems && newItems.length) {
            newItems.forEach((item, index, arr) => {
                let title = item.title;
                title = title === null || title === undefined ? '' : title;
                segmentedControl.insertSegmentWithTitleAtIndexAnimated(title, index, false);
            });
        }
        selectedIndexProperty.coerce(this);
    }
    [selectedBackgroundColorProperty.getDefault]() {
        return SDK_VERSION < 13 ? this.ios.tintColor : this.ios.selectedSegmentTintColor;
    }
    [selectedBackgroundColorProperty.setNative](value) {
        const color = value instanceof Color ? value.ios : value;
        if (SDK_VERSION < 13) {
            this.ios.tintColor = color;
        }
        else {
            this.ios.selectedSegmentTintColor = color;
        }
        this.setSelectedTextColor(this.ios);
    }
    [colorProperty.getDefault]() {
        return null;
    }
    [colorProperty.setNative](value) {
        const color = value instanceof Color ? value.ios : value;
        const bar = this.ios;
        const currentAttrs = bar.titleTextAttributesForState(0 /* UIControlState.Normal */);
        const attrs = currentAttrs ? currentAttrs.mutableCopy() : NSMutableDictionary.new();
        attrs.setValueForKey(color, NSForegroundColorAttributeName);
        bar.setTitleTextAttributesForState(attrs, 0 /* UIControlState.Normal */);
        // Set the selected text color
        this.setSelectedTextColor(bar);
    }
    [fontInternalProperty.getDefault]() {
        return null;
    }
    [fontInternalProperty.setNative](value) {
        const font = value ? value.getUIFont(UIFont.systemFontOfSize(UIFont.labelFontSize)) : null;
        const bar = this.ios;
        const currentAttrs = bar.titleTextAttributesForState(0 /* UIControlState.Normal */);
        const attrs = currentAttrs ? currentAttrs.mutableCopy() : NSMutableDictionary.new();
        attrs.setValueForKey(font, NSFontAttributeName);
        bar.setTitleTextAttributesForState(attrs, 0 /* UIControlState.Normal */);
    }
    setSelectedTextColor(bar) {
        try {
            const selectedTextColor = this.getColorForIOS(this?.selectedTextColor ?? this?.color ?? '#000000');
            if (!selectedTextColor) {
                Trace.write(`unable te set selectedTextColor`, Trace.categories.Error);
            }
            const selectedText = bar.titleTextAttributesForState(4 /* UIControlState.Selected */);
            const attrsSelected = selectedText ? selectedText.mutableCopy() : NSMutableDictionary.new();
            attrsSelected.setValueForKey(selectedTextColor, NSForegroundColorAttributeName);
            bar.setTitleTextAttributesForState(attrsSelected, 4 /* UIControlState.Selected */);
        }
        catch (e) {
            console.error(`SegmentedBar:`, e);
        }
    }
    getColorForIOS(color) {
        if (typeof color === 'string') {
            return new Color(color).ios;
        }
        else if (color instanceof Color) {
            return color.ios;
        }
    }
}
var SelectionHandlerImpl = (function (_super) {
    __extends(SelectionHandlerImpl, _super);
    function SelectionHandlerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    SelectionHandlerImpl.initWithOwner = function (owner) {
        var handler = SelectionHandlerImpl.new();
        handler._owner = owner;
        return handler;
    };
    SelectionHandlerImpl.prototype.selected = function (sender) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            owner.selectedIndex = sender.selectedSegmentIndex;
            owner.setSelectedTextColor(sender);
        }
    };
    SelectionHandlerImpl.ObjCExposedMethods = {
        selected: { returns: interop.types.void, params: [UISegmentedControl] },
    };
    return SelectionHandlerImpl;
}(NSObject));
//# sourceMappingURL=index.ios.js.map