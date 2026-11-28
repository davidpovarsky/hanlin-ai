import { CORE_ANIMATION_DEFAULTS } from '../../utils/animation-helpers';
import { Transition } from '.';
export class FadeTransition extends Transition {
    iosNavigatedController(navigationController, operation, fromVC, toVC) {
        this.transitionController = FadeTransitionController.initWithOwner(new WeakRef(this));
        this.presented = toVC;
        this.presenting = fromVC;
        this.operation = operation;
        // console.log('presenting:', this.presenting);
        return this.transitionController;
    }
}
var FadeTransitionController = (function (_super) {
    __extends(FadeTransitionController, _super);
    function FadeTransitionController() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    FadeTransitionController.initWithOwner = function (owner) {
        var ctrl = FadeTransitionController.new();
        ctrl.owner = owner;
        return ctrl;
    };
    FadeTransitionController.prototype.transitionDuration = function (transitionContext) {
        var owner = this.owner.deref();
        if (owner) {
            return owner.getDuration();
        }
        return CORE_ANIMATION_DEFAULTS.duration;
    };
    FadeTransitionController.prototype.animateTransition = function (transitionContext) {
        var owner = this.owner.deref();
        if (owner) {
            var toView_1 = owner.presented.view;
            var originalToViewAlpha_1 = toView_1.alpha;
            var fromView_1 = owner.presenting.view;
            var originalFromViewAlpha_1 = fromView_1.alpha;
            toView_1.alpha = 0;
            fromView_1.alpha = 1;
            switch (owner.operation) {
                case UINavigationControllerOperation.Push:
                    transitionContext.containerView.insertSubviewAboveSubview(toView_1, fromView_1);
                    break;
                case UINavigationControllerOperation.Pop:
                    transitionContext.containerView.insertSubviewBelowSubview(toView_1, fromView_1);
                    break;
            }
            var duration = owner.getDuration();
            var curve_1 = owner.getCurve();
            UIView.animateWithDurationAnimationsCompletion(duration, function () {
                UIView.setAnimationCurve(curve_1);
                toView_1.alpha = 1;
                fromView_1.alpha = 0;
            }, function (finished) {
                toView_1.alpha = originalToViewAlpha_1;
                fromView_1.alpha = originalFromViewAlpha_1;
                transitionContext.completeTransition(finished);
            });
        }
    };
    FadeTransitionController.ObjCProtocols = [UIViewControllerAnimatedTransitioning];
    return FadeTransitionController;
}(NSObject));
export { FadeTransitionController };
//# sourceMappingURL=fade-transition.ios.js.map