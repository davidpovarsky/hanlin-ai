import { SliderBase, valueProperty, minValueProperty, maxValueProperty } from './slider-common';
import { colorProperty, backgroundColorProperty, backgroundInternalProperty } from '../styling/style-properties';
import { Color } from '../../color';
import { LinearGradient } from '../styling/linear-gradient';
import { Screen } from '../../platform/screen';
export * from './slider-common';
var TNSSlider = (function (_super) {
    __extends(TNSSlider, _super);
    function TNSSlider() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    TNSSlider.initWithOwner = function (owner) {
        var slider = TNSSlider.new();
        slider.owner = owner;
        return slider;
    };
    TNSSlider.prototype.accessibilityIncrement = function () {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            this.value += 10;
        }
        else {
            this.value = owner._handlerAccessibilityIncrementEvent();
        }
        this.sendActionsForControlEvents(UIControlEvents.ValueChanged);
    };
    TNSSlider.prototype.accessibilityDecrement = function () {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (!owner) {
            this.value += 10;
        }
        else {
            this.value = owner._handlerAccessibilityDecrementEvent();
        }
        this.sendActionsForControlEvents(UIControlEvents.ValueChanged);
    };
    return TNSSlider;
}(UISlider));
var SliderChangeHandlerImpl = (function (_super) {
    __extends(SliderChangeHandlerImpl, _super);
    function SliderChangeHandlerImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    SliderChangeHandlerImpl.initWithOwner = function (owner) {
        var handler = SliderChangeHandlerImpl.new();
        handler._owner = owner;
        return handler;
    };
    SliderChangeHandlerImpl.prototype.sliderValueChanged = function (sender) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            valueProperty.nativeValueChange(owner, sender.value);
        }
    };
    SliderChangeHandlerImpl.ObjCExposedMethods = {
        sliderValueChanged: { returns: interop.types.void, params: [UISlider] },
    };
    return SliderChangeHandlerImpl;
}(NSObject));
export class Slider extends SliderBase {
    createNativeView() {
        return TNSSlider.initWithOwner(new WeakRef(this));
    }
    initNativeView() {
        super.initNativeView();
        const nativeView = this.nativeViewProtected;
        // default values
        nativeView.minimumValue = 0;
        nativeView.maximumValue = this.maxValue;
        this._changeHandler = SliderChangeHandlerImpl.initWithOwner(new WeakRef(this));
        nativeView.addTargetActionForControlEvents(this._changeHandler, 'sliderValueChanged', 4096 /* UIControlEvents.ValueChanged */);
    }
    disposeNativeView() {
        this._changeHandler = null;
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    [valueProperty.getDefault]() {
        return 0;
    }
    [valueProperty.setNative](value) {
        this.ios.value = value;
    }
    [minValueProperty.getDefault]() {
        return 0;
    }
    [minValueProperty.setNative](value) {
        this.ios.minimumValue = value;
    }
    [maxValueProperty.getDefault]() {
        return 100;
    }
    [maxValueProperty.setNative](value) {
        this.ios.maximumValue = value;
    }
    [colorProperty.getDefault]() {
        return this.ios.thumbTintColor;
    }
    [colorProperty.setNative](value) {
        const color = value instanceof Color ? value.ios : value;
        this.ios.thumbTintColor = color;
    }
    [backgroundColorProperty.getDefault]() {
        return this.ios.minimumTrackTintColor;
    }
    [backgroundColorProperty.setNative](value) {
        const color = value instanceof Color ? value.ios : value;
        this.ios.minimumTrackTintColor = color;
    }
    [backgroundInternalProperty.getDefault]() {
        return null;
    }
    [backgroundInternalProperty.setNative](value) {
        if (value && value.image instanceof LinearGradient) {
            this._applyGradientToTrack(value.image);
        }
    }
    _applyGradientToTrack(gradient) {
        const nativeView = this.nativeViewProtected;
        if (!nativeView) {
            return;
        }
        // Create a gradient layer
        const gradientLayer = CAGradientLayer.new();
        // Set up colors from the gradient stops
        const iosColors = NSMutableArray.alloc().initWithCapacity(gradient.colorStops.length);
        const iosStops = NSMutableArray.alloc().initWithCapacity(gradient.colorStops.length);
        let hasStops = false;
        gradient.colorStops.forEach((stop, index) => {
            iosColors.addObject(stop.color.ios.CGColor);
            if (stop.offset) {
                iosStops.addObject(stop.offset.value);
                hasStops = true;
            }
            else {
                // Default evenly distributed positions
                iosStops.addObject(index / (gradient.colorStops.length - 1));
            }
        });
        gradientLayer.colors = iosColors;
        if (hasStops) {
            gradientLayer.locations = iosStops;
        }
        // Calculate gradient direction based on angle
        const alpha = gradient.angle / (Math.PI * 2);
        const startX = Math.pow(Math.sin(Math.PI * (alpha + 0.75)), 2);
        const startY = Math.pow(Math.sin(Math.PI * (alpha + 0.5)), 2);
        const endX = Math.pow(Math.sin(Math.PI * (alpha + 0.25)), 2);
        const endY = Math.pow(Math.sin(Math.PI * alpha), 2);
        gradientLayer.startPoint = { x: startX, y: startY };
        gradientLayer.endPoint = { x: endX, y: endY };
        // Create track image from gradient
        // Use a reasonable default size for the track
        const trackWidth = 200;
        const trackHeight = 4;
        gradientLayer.frame = CGRectMake(0, 0, trackWidth, trackHeight);
        gradientLayer.cornerRadius = trackHeight / 2;
        // Create renderer format with proper scale
        const format = UIGraphicsImageRendererFormat.defaultFormat();
        format.scale = Screen.mainScreen.scale;
        format.opaque = false;
        const size = CGSizeMake(trackWidth, trackHeight);
        const renderer = UIGraphicsImageRenderer.alloc().initWithSizeFormat(size, format);
        // Render gradient to image
        const gradientImage = renderer.imageWithActions((rendererContext) => {
            gradientLayer.renderInContext(rendererContext.CGContext);
        });
        if (gradientImage) {
            // Create stretchable image for the track
            const capInsets = new UIEdgeInsets({
                top: 0,
                left: trackHeight / 2,
                bottom: 0,
                right: trackHeight / 2,
            });
            const stretchableImage = gradientImage.resizableImageWithCapInsetsResizingMode(capInsets, 1 /* UIImageResizingMode.Stretch */);
            // Set the gradient image for minimum track (filled portion)
            nativeView.setMinimumTrackImageForState(stretchableImage, 0 /* UIControlState.Normal */);
            // For maximum track, create a semi-transparent version
            const maxTrackImage = renderer.imageWithActions((rendererContext) => {
                CGContextSetAlpha(rendererContext.CGContext, 0.3);
                gradientLayer.renderInContext(rendererContext.CGContext);
            });
            if (maxTrackImage) {
                const maxCapInsets = new UIEdgeInsets({
                    top: 0,
                    left: trackHeight / 2,
                    bottom: 0,
                    right: trackHeight / 2,
                });
                const maxStretchableImage = maxTrackImage.resizableImageWithCapInsetsResizingMode(maxCapInsets, 1 /* UIImageResizingMode.Stretch */);
                nativeView.setMaximumTrackImageForState(maxStretchableImage, 0 /* UIControlState.Normal */);
            }
        }
    }
    getAccessibilityStep() {
        if (!this.accessibilityStep || this.accessibilityStep <= 0) {
            return 10;
        }
        return this.accessibilityStep;
    }
    _handlerAccessibilityIncrementEvent() {
        const args = {
            object: this,
            eventName: SliderBase.accessibilityIncrementEvent,
            value: this.value + this.getAccessibilityStep(),
        };
        this.notify(args);
        return args.value;
    }
    _handlerAccessibilityDecrementEvent() {
        const args = {
            object: this,
            eventName: SliderBase.accessibilityIncrementEvent,
            value: this.value - this.getAccessibilityStep(),
        };
        this.notify(args);
        return args.value;
    }
}
//# sourceMappingURL=index.ios.js.map