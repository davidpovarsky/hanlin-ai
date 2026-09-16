import { View, CustomLayoutView } from '../core/view';
import { booleanConverter, getViewById } from '../core/view-base';
import { Property } from '../core/properties';
export class LayoutBaseCommon extends CustomLayoutView {
    constructor() {
        super(...arguments);
        this._subViews = new Array();
    }
    _addChildFromBuilder(name, value) {
        if (value instanceof View) {
            this.addChild(value);
        }
    }
    getChildrenCount() {
        return this._subViews.length;
    }
    // overrides the base property.
    get _childrenCount() {
        return this._subViews.length;
    }
    getChildAt(index) {
        return this._subViews[index];
    }
    getChildIndex(child) {
        return this._subViews.indexOf(child);
    }
    getChildById(id) {
        return getViewById(this, id);
    }
    _registerLayoutChild(child) {
        //Overridden
    }
    _unregisterLayoutChild(child) {
        //Overridden
    }
    addChild(child) {
        // TODO: Do we need this method since we have the core logic in the View implementation?
        this._subViews.push(child);
        this._addView(child);
        this._registerLayoutChild(child);
    }
    insertChild(child, atIndex) {
        if (atIndex > -1) {
            // A re-attached child keeps its scope, so inheriting it won't re-match its css state
            const isReattached = child._styleScope === this._styleScope;
            this._subViews.splice(atIndex, 0, child);
            this._addView(child, atIndex);
            this._registerLayoutChild(child);
            this._invalidateSiblingCssState(isReattached ? atIndex : atIndex + 1, atIndex + 2);
            return true;
        }
        return false;
    }
    removeChild(child) {
        this._removeView(child);
        // TODO: consider caching the index on the child.
        const index = this._subViews.indexOf(child);
        if (index > -1) {
            this._subViews.splice(index, 1);
            this._unregisterLayoutChild(child);
            this._invalidateSiblingCssState(index, index + 1);
        }
    }
    // Sibling combinator matches are cached and never re-queried on tree changes.
    // Appending changes no predecessor, so addChild skips invalidation.
    _invalidateSiblingCssState(fromIndex, adjacentEndIndex) {
        const scope = this._styleScope;
        if (!scope) {
            return;
        }
        const general = scope.hasSiblingCombinatorSelectors;
        if (!general && !scope.hasAdjacentCombinatorSelectors) {
            return;
        }
        // '+' only affects views whose direct predecessor changed
        const end = Math.min(general ? this._subViews.length : adjacentEndIndex, this._subViews.length);
        for (let i = fromIndex; i < end; i++) {
            this._subViews[i]._onCssStateChange();
        }
    }
    removeChildren() {
        while (this.getChildrenCount() !== 0) {
            this.removeChild(this._subViews[this.getChildrenCount() - 1]);
        }
    }
    get padding() {
        return this.style.padding;
    }
    set padding(value) {
        this.style.padding = value;
    }
    get paddingTop() {
        return this.style.paddingTop;
    }
    set paddingTop(value) {
        this.style.paddingTop = value;
    }
    get paddingRight() {
        return this.style.paddingRight;
    }
    set paddingRight(value) {
        this.style.paddingRight = value;
    }
    get paddingBottom() {
        return this.style.paddingBottom;
    }
    set paddingBottom(value) {
        this.style.paddingBottom = value;
    }
    get paddingLeft() {
        return this.style.paddingLeft;
    }
    set paddingLeft(value) {
        this.style.paddingLeft = value;
    }
    _childIndexToNativeChildIndex(index) {
        if (index === undefined) {
            return undefined;
        }
        let result = 0;
        for (let i = 0; i < index && i < this._subViews.length; i++) {
            result += this._subViews[i]._getNativeViewsCount();
        }
        return result;
    }
    eachChildView(callback) {
        for (let i = 0, length = this._subViews.length; i < length; i++) {
            const retVal = callback(this._subViews[i]);
            if (retVal === false) {
                break;
            }
        }
    }
    eachLayoutChild(callback) {
        let lastChild = null;
        this.eachChildView((cv) => {
            cv._eachLayoutView((lv) => {
                if (lastChild && !lastChild.isCollapsed) {
                    callback(lastChild, false);
                }
                lastChild = lv;
            });
            return true;
        });
        if (lastChild && !lastChild.isCollapsed) {
            callback(lastChild, true);
        }
    }
}
export const clipToBoundsProperty = new Property({
    name: 'clipToBounds',
    defaultValue: true,
    valueConverter: booleanConverter,
});
clipToBoundsProperty.register(LayoutBaseCommon);
export const isPassThroughParentEnabledProperty = new Property({
    name: 'isPassThroughParentEnabled',
    defaultValue: false,
    valueConverter: booleanConverter,
});
isPassThroughParentEnabledProperty.register(LayoutBaseCommon);
//# sourceMappingURL=layout-base-common.js.map