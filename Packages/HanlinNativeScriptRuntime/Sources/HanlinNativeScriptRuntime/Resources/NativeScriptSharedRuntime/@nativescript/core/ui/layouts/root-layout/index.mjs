import { Color } from '../../../color';
import { RootLayoutBase, defaultShadeCoverOptions } from './root-layout-common';
import { LinearGradient } from '../../styling/linear-gradient';
import { ios as iosViewUtils } from '../../utils';
import { parseLinearGradient } from '../../../css/parser';
export * from './root-layout-common';
export class RootLayout extends RootLayoutBase {
    disposeNativeView() {
        super.disposeNativeView();
        this._cleanupPlatformShadeCover();
    }
    _bringToFront(view) {
        this.nativeViewProtected.bringSubviewToFront(view.nativeViewProtected);
    }
    _initShadeCover(view, shadeOptions) {
        const initialState = {
            ...defaultShadeCoverOptions.animation.enterFrom,
            ...shadeOptions?.animation?.enterFrom,
        };
        this._applyAnimationProperties(view, initialState);
    }
    _updateShadeCover(view, shadeOptions) {
        return new Promise((resolve) => {
            const options = {
                ...defaultShadeCoverOptions,
                ...shadeOptions,
            };
            if (view?.nativeViewProtected) {
                const duration = this._convertDurationToSeconds(options.animation?.enterFrom?.duration || defaultShadeCoverOptions.animation.enterFrom.duration);
                if (options.color && options.color.startsWith('linear-gradient')) {
                    if (options.color !== this._currentGradient) {
                        this._currentGradient = options.color;
                        const parsedGradient = parseLinearGradient(options.color);
                        this._gradientLayer = CAGradientLayer.new();
                        iosViewUtils.drawGradient(view.nativeViewProtected, this._gradientLayer, LinearGradient.parse(parsedGradient.value));
                        view.nativeViewProtected.layer.insertSublayerAtIndex(this._gradientLayer, 0);
                    }
                }
                else {
                    // Dispose gradient if new color is null or a plain color
                    this._cleanupPlatformShadeCover();
                }
                UIView.animateWithDurationAnimationsCompletion(duration, () => {
                    if (this._gradientLayer) {
                        this._gradientLayer.opacity = 1;
                    }
                    else if (options.color && view?.nativeViewProtected) {
                        view.nativeViewProtected.backgroundColor = new Color(options.color).ios;
                    }
                    this._applyAnimationProperties(view, {
                        translateX: 0,
                        translateY: 0,
                        scaleX: 1,
                        scaleY: 1,
                        rotate: 0,
                        opacity: shadeOptions.opacity,
                    });
                }, (completed) => {
                    resolve();
                });
            }
        });
    }
    _closeShadeCover(view, shadeOptions) {
        return new Promise((resolve) => {
            const exitState = {
                ...defaultShadeCoverOptions.animation.exitTo,
                ...shadeOptions?.animation?.exitTo,
            };
            if (view && view.nativeViewProtected) {
                UIView.animateWithDurationAnimationsCompletion(this._convertDurationToSeconds(exitState.duration), () => {
                    this._applyAnimationProperties(view, exitState);
                }, (completed) => {
                    resolve();
                });
            }
        });
    }
    _cleanupPlatformShadeCover() {
        this._currentGradient = null;
        if (this._gradientLayer != null) {
            this._gradientLayer.removeFromSuperlayer();
            this._gradientLayer = null;
        }
    }
    _applyAnimationProperties(view, shadeCoverAnimation) {
        if (view?.nativeViewProtected) {
            const translate = CGAffineTransformMakeTranslation(shadeCoverAnimation.translateX, shadeCoverAnimation.translateY);
            // ios doesn't like scale being 0, default it to a small number greater than 0
            const scale = CGAffineTransformMakeScale(shadeCoverAnimation.scaleX || 0.1, shadeCoverAnimation.scaleY || 0.1);
            const rotate = CGAffineTransformMakeRotation((shadeCoverAnimation.rotate * Math.PI) / 180); // convert degress to radians
            const translateAndScale = CGAffineTransformConcat(translate, scale);
            view.nativeViewProtected.transform = CGAffineTransformConcat(rotate, translateAndScale);
            view.nativeViewProtected.alpha = shadeCoverAnimation.opacity;
        }
    }
    _convertDurationToSeconds(duration) {
        return duration / 1000;
    }
}
//# sourceMappingURL=index.ios.js.map