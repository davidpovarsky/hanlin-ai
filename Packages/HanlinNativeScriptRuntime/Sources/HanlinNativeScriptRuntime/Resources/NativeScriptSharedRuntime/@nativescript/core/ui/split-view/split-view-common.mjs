const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
import { LayoutBase } from '../layouts/layout-base';
import { View, CSSType } from '../core/view';
import { Property, makeParser, makeValidator } from '../core/properties';
import { Color } from '../../color';
const splitRoleConverter = makeParser(makeValidator('primary', 'secondary', 'supplementary', 'inspector'));
const splitDisplayModeConverter = makeParser(makeValidator('automatic', 'secondaryOnly', 'oneBesideSecondary', 'oneOverSecondary', 'twoBesideSecondary', 'twoOverSecondary', 'twoDisplaceSecondary'));
const splitBehaviorConverter = makeParser(makeValidator('automatic', 'tile', 'overlay', 'displace'));
// Default child roles (helps authoring without setting splitRole on children)
const ROLE_ORDER = ['primary', 'secondary', 'supplementary', 'inspector'];
let SplitViewBase = class SplitViewBase extends LayoutBase {
    static getInstance() {
        // Platform-specific implementations may override
        return null;
    }
    /**
     * Get child role (primary, secondary, supplementary, inspector)
     */
    static getRole(element) {
        return element.splitRole;
    }
    /**
     * Set child role (primary, secondary, supplementary, inspector)
     */
    static setRole(element, value) {
        element.splitRole = value;
    }
    // Called when a child's role changes; platform impls may override
    onRoleChanged(view, oldValue, newValue) {
        this.requestLayout();
    }
    showPrimary() {
        // Platform-specific implementations may override
    }
    hidePrimary() {
        // Platform-specific implementations may override
    }
    showSecondary() {
        // Platform-specific implementations may override
    }
    hideSecondary() {
        // Platform-specific implementations may override
    }
    showSupplementary() {
        // Platform-specific implementations may override
    }
    hideSupplementary() {
        // Platform-specific implementations may override
    }
    showInspector() {
        // Platform-specific implementations may override
    }
    hideInspector() {
        // Platform-specific implementations may override
    }
    /**
     * Invalidate layouts for all child views in the SplitView.
     * Useful when columns change, orientation changes, or any scenario
     * requiring a full layout refresh of all split view children.
     * @param delay Optional delay in milliseconds (default 350ms to wait for animations)
     */
    invalidateChildLayouts(delay = 0) {
        // Platform-specific implementations may override
    }
    // Utility to infer a role by index when none specified
    _roleByIndex(index) {
        return ROLE_ORDER[Math.max(0, Math.min(index, ROLE_ORDER.length - 1))];
    }
};
SplitViewBase = __decorate([
    CSSType('SplitView')
], SplitViewBase);
export { SplitViewBase };
SplitViewBase.prototype.recycleNativeView = 'auto';
export const splitRoleProperty = new Property({
    name: 'splitRole',
    defaultValue: 'primary',
    valueChanged: (target, oldValue, newValue) => {
        const parent = target.parent;
        if (parent instanceof SplitViewBase) {
            parent.onRoleChanged(target, oldValue, newValue);
        }
    },
    valueConverter: splitRoleConverter,
});
splitRoleProperty.register(View);
export const displayModeProperty = new Property({
    name: 'displayMode',
    defaultValue: 'automatic',
    affectsLayout: __APPLE__,
    valueConverter: splitDisplayModeConverter,
});
displayModeProperty.register(SplitViewBase);
export const splitBehaviorProperty = new Property({
    name: 'splitBehavior',
    defaultValue: 'automatic',
    affectsLayout: __APPLE__,
    valueConverter: splitBehaviorConverter,
});
splitBehaviorProperty.register(SplitViewBase);
export const preferredPrimaryColumnWidthFractionProperty = new Property({
    name: 'preferredPrimaryColumnWidthFraction',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueConverter: (v) => Math.max(0, Math.min(1, parseFloat(v))),
});
preferredPrimaryColumnWidthFractionProperty.register(SplitViewBase);
export const preferredSupplementaryColumnWidthFractionProperty = new Property({
    name: 'preferredSupplementaryColumnWidthFraction',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueConverter: (v) => Math.max(0, Math.min(1, parseFloat(v))),
});
preferredSupplementaryColumnWidthFractionProperty.register(SplitViewBase);
export const preferredInspectorColumnWidthFractionProperty = new Property({
    name: 'preferredInspectorColumnWidthFraction',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueConverter: (v) => Math.max(0, Math.min(1, parseFloat(v))),
});
preferredInspectorColumnWidthFractionProperty.register(SplitViewBase);
export const navigationBarTintColorProperty = new Property({
    name: 'navigationBarTintColor',
    equalityComparer: Color.equals,
    valueConverter: (v) => new Color(v),
});
navigationBarTintColorProperty.register(SplitViewBase);
//# sourceMappingURL=split-view-common.js.map