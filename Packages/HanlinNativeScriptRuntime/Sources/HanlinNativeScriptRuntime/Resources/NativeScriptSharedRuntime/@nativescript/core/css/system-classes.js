import { CoreTypes } from '../core-types';
const MODAL = 'modal';
const ROOT = 'root';
const cssClasses = [];
export var CSSUtils;
(function (CSSUtils) {
    CSSUtils.CLASS_PREFIX = 'ns-';
    CSSUtils.MODAL_ROOT_VIEW_CSS_CLASS = `${CSSUtils.CLASS_PREFIX}${MODAL}`;
    CSSUtils.ROOT_VIEW_CSS_CLASS = `${CSSUtils.CLASS_PREFIX}${ROOT}`;
    // prettier-ignore
    CSSUtils.ORIENTATION_CSS_CLASSES = [
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.DeviceOrientation.portrait}`,
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.DeviceOrientation.landscape}`,
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.DeviceOrientation.unknown}`,
    ];
    // prettier-ignore
    CSSUtils.SYSTEM_APPEARANCE_CSS_CLASSES = [
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.SystemAppearance.light}`,
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.SystemAppearance.dark}`,
    ];
    // prettier-ignore
    CSSUtils.LAYOUT_DIRECTION_CSS_CLASSES = [
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.LayoutDirection.ltr}`,
        `${CSSUtils.CLASS_PREFIX}${CoreTypes.LayoutDirection.rtl}`,
    ];
    /**
     * Classes describing the state of a single window. Two windows can legitimately
     * disagree on all of them, so they live on each window's root view (and the modals
     * presented over it) rather than in the process-wide system class list.
     */
    CSSUtils.WINDOW_SCOPED_CSS_CLASSES = [...CSSUtils.ORIENTATION_CSS_CLASSES, ...CSSUtils.SYSTEM_APPEARANCE_CSS_CLASSES, ...CSSUtils.LAYOUT_DIRECTION_CSS_CLASSES];
    function getSystemCssClasses() {
        return cssClasses;
    }
    CSSUtils.getSystemCssClasses = getSystemCssClasses;
    function pushToSystemCssClasses(value) {
        const index = cssClasses.indexOf(value);
        if (index == -1) {
            cssClasses.push(value);
        }
        return cssClasses.length;
    }
    CSSUtils.pushToSystemCssClasses = pushToSystemCssClasses;
    function removeSystemCssClass(value) {
        const index = cssClasses.indexOf(value);
        let removedElement;
        if (index > -1) {
            removedElement = cssClasses.splice(index, 1);
        }
        return removedElement;
    }
    CSSUtils.removeSystemCssClass = removeSystemCssClass;
    function getModalRootViewCssClass() {
        return CSSUtils.MODAL_ROOT_VIEW_CSS_CLASS;
    }
    CSSUtils.getModalRootViewCssClass = getModalRootViewCssClass;
    function getRootViewCssClasses() {
        return [CSSUtils.ROOT_VIEW_CSS_CLASS, ...cssClasses];
    }
    CSSUtils.getRootViewCssClasses = getRootViewCssClasses;
    function pushToRootViewCssClasses(value) {
        return pushToSystemCssClasses(value) + 1; // because of ROOT_VIEW_CSS_CLASS
    }
    CSSUtils.pushToRootViewCssClasses = pushToRootViewCssClasses;
    function removeFromRootViewCssClasses(value) {
        return removeSystemCssClass(value);
    }
    CSSUtils.removeFromRootViewCssClasses = removeFromRootViewCssClasses;
})(CSSUtils || (CSSUtils = {}));
//# sourceMappingURL=system-classes.js.map