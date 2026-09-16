import * as layoutCommon from './layout-helper-common';
import { ios as iosUtils } from '../native-helper';
// Cache the screen scale to avoid repeated marshalling calls into UIKit
// (window resolution + screen + scale) on every dp/px conversion during
// measure and layout passes. The scale of the device's main screen never
// changes at runtime, and `Screen.mainScreen` relies on the same invariant.
let mainScreenScale = 0;
function getMainScreenScale() {
    return mainScreenScale || (mainScreenScale = iosUtils.getMainScreen().scale);
}
export var layout;
(function (layout) {
    // cache the MeasureSpec constants here, to prevent extensive marshaling calls to and from Objective C
    // TODO: While this boosts the performance it is error-prone in case Google changes these constants
    layout.MODE_SHIFT = 30;
    layout.MODE_MASK = 0x3 << layout.MODE_SHIFT;
    layout.UNSPECIFIED = 0 << layout.MODE_SHIFT;
    layout.EXACTLY = 1 << layout.MODE_SHIFT;
    layout.AT_MOST = 2 << layout.MODE_SHIFT;
    layout.MEASURED_HEIGHT_STATE_SHIFT = 0x00000010; /* 16 */
    layout.MEASURED_STATE_TOO_SMALL = 0x01000000;
    layout.MEASURED_STATE_MASK = 0xff000000;
    layout.MEASURED_SIZE_MASK = 0x00ffffff;
    function getMode(mode) {
        return layoutCommon.getMode(mode);
    }
    layout.getMode = getMode;
    function getMeasureSpecMode(spec) {
        return layoutCommon.getMeasureSpecMode(spec);
    }
    layout.getMeasureSpecMode = getMeasureSpecMode;
    function getMeasureSpecSize(spec) {
        return layoutCommon.getMeasureSpecSize(spec);
    }
    layout.getMeasureSpecSize = getMeasureSpecSize;
    function makeMeasureSpec(size, mode) {
        return (Math.round(Math.max(0, size)) & ~layout.MODE_MASK) | (mode & layout.MODE_MASK);
    }
    layout.makeMeasureSpec = makeMeasureSpec;
    function hasRtlSupport() {
        return true;
    }
    layout.hasRtlSupport = hasRtlSupport;
    function getDisplayDensity() {
        return getMainScreenScale();
    }
    layout.getDisplayDensity = getDisplayDensity;
    function toDevicePixels(value) {
        return value * getMainScreenScale();
    }
    layout.toDevicePixels = toDevicePixels;
    function toDeviceIndependentPixels(value) {
        return value / getMainScreenScale();
    }
    layout.toDeviceIndependentPixels = toDeviceIndependentPixels;
    function round(value) {
        return layoutCommon.round(value);
    }
    layout.round = round;
    function measureNativeView(nativeView /* UIView */, width, widthMode, height, heightMode) {
        const view = nativeView;
        const nativeSize = view.sizeThatFits({
            width: widthMode === 0 /* layout.UNSPECIFIED */ ? Number.POSITIVE_INFINITY : toDeviceIndependentPixels(width),
            height: heightMode === 0 /* layout.UNSPECIFIED */ ? Number.POSITIVE_INFINITY : toDeviceIndependentPixels(height),
        });
        nativeSize.width = round(toDevicePixels(nativeSize.width));
        nativeSize.height = round(toDevicePixels(nativeSize.height));
        return nativeSize;
    }
    layout.measureNativeView = measureNativeView;
    function measureSpecToString(measureSpec) {
        return layoutCommon.measureSpecToString(measureSpec);
    }
    layout.measureSpecToString = measureSpecToString;
})(layout || (layout = {}));
//# sourceMappingURL=index.ios.js.map