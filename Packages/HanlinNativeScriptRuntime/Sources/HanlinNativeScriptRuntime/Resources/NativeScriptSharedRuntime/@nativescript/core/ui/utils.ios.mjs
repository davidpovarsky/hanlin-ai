import { Screen } from '../platform';
import * as utils from '../utils';
export var ios;
(function (ios) {
    let LayerMask;
    (function (LayerMask) {
        LayerMask.BORDER = 'BORDER';
        LayerMask.CLIP_PATH = 'CLIP_PATH';
    })(LayerMask = ios.LayerMask || (ios.LayerMask = {}));
    function getActualHeight(view) {
        if (view.window && !view.hidden) {
            return utils.layout.toDevicePixels(view.frame.size.height);
        }
        return 0;
    }
    ios.getActualHeight = getActualHeight;
    function getStatusBarHeight(viewController) {
        const app = UIApplication.sharedApplication;
        if (!app || app.statusBarHidden) {
            return 0;
        }
        if (viewController && viewController.prefersStatusBarHidden) {
            return 0;
        }
        const statusFrame = app.statusBarFrame;
        const min = Math.min(statusFrame.size.width, statusFrame.size.height);
        return utils.layout.toDevicePixels(min);
    }
    ios.getStatusBarHeight = getStatusBarHeight;
    function drawGradient(nativeView, gradientLayer, gradient, gradientLayerOpacity) {
        if (!nativeView || !gradient) {
            return;
        }
        if (typeof gradientLayerOpacity === 'number') {
            gradientLayer.opacity = gradientLayerOpacity;
        }
        // Update these properties instead of layer frame as the latter messes with animations
        gradientLayer.bounds = nativeView.bounds;
        gradientLayer.anchorPoint = CGPointMake(0, 0);
        gradientLayer.allowsEdgeAntialiasing = true;
        gradientLayer.contentsScale = Screen.mainScreen.scale;
        const iosColors = NSMutableArray.alloc().initWithCapacity(gradient.colorStops.length);
        const iosStops = NSMutableArray.alloc().initWithCapacity(gradient.colorStops.length);
        let hasStops = false;
        gradient.colorStops.forEach((stop) => {
            iosColors.addObject(stop.color.ios.CGColor);
            if (stop.offset) {
                iosStops.addObject(stop.offset.value);
                hasStops = true;
            }
        });
        gradientLayer.colors = iosColors;
        if (hasStops) {
            gradientLayer.locations = iosStops;
        }
        const alpha = gradient.angle / (Math.PI * 2);
        const startX = Math.pow(Math.sin(Math.PI * (alpha + 0.75)), 2);
        const startY = Math.pow(Math.sin(Math.PI * (alpha + 0.5)), 2);
        const endX = Math.pow(Math.sin(Math.PI * (alpha + 0.25)), 2);
        const endY = Math.pow(Math.sin(Math.PI * alpha), 2);
        gradientLayer.startPoint = { x: startX, y: startY };
        gradientLayer.endPoint = { x: endX, y: endY };
    }
    ios.drawGradient = drawGradient;
})(ios || (ios = {}));
//# sourceMappingURL=utils.ios.js.map