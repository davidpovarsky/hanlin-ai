import { Transition } from '.';
import { Screen } from '../../platform/screen';
import { CORE_ANIMATION_DEFAULTS } from '../../utils/animation-helpers';
export class SlideTransition extends Transition {
    constructor(direction, duration, curve) {
        super(duration, curve);
        this.direction = direction;
    }
    iosNavigatedController(navigationController, operation, fromVC, toVC) {
        this.transitionController = SlideTransitionController.initWithOwner(new WeakRef(this));
        this.presented = toVC;
        this.presenting = fromVC;
        this.operation = operation;
        // console.log('presenting:', presenting)
        return this.transitionController;
    }
}
var SlideTransitionController = (function (_super) {
    __extends(SlideTransitionController, _super);
    function SlideTransitionController() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    SlideTransitionController.initWithOwner = function (owner) {
        var ctrl = SlideTransitionController.new();
        ctrl.owner = owner;
        return ctrl;
    };
    SlideTransitionController.prototype.transitionDuration = function (transitionContext) {
        var owner = this.owner.deref();
        if (owner) {
            return owner.getDuration();
        }
        return CORE_ANIMATION_DEFAULTS.duration;
    };
    SlideTransitionController.prototype.animateTransition = function (transitionContext) {
        var owner = this.owner.deref();
        if (owner) {
            var toView_1 = owner.presented.view;
            var originalToViewTransform_1 = toView_1.transform;
            var fromView_1 = owner.presenting.view;
            var originalFromViewTransform_1 = fromView_1.transform;
            var fromViewEndTransform_1;
            var toViewBeginTransform = void 0;
            var push = owner.operation === UINavigationControllerOperation.Push;
            var leftEdge = CGAffineTransformMakeTranslation(-Screen.mainScreen.widthDIPs, 0);
            var rightEdge = CGAffineTransformMakeTranslation(Screen.mainScreen.widthDIPs, 0);
            var topEdge = CGAffineTransformMakeTranslation(0, -Screen.mainScreen.heightDIPs);
            var bottomEdge = CGAffineTransformMakeTranslation(0, Screen.mainScreen.heightDIPs);
            switch (owner.direction) {
                case "left":
                    toViewBeginTransform = push ? rightEdge : leftEdge;
                    fromViewEndTransform_1 = push ? leftEdge : rightEdge;
                    break;
                case "right":
                    toViewBeginTransform = push ? leftEdge : rightEdge;
                    fromViewEndTransform_1 = push ? rightEdge : leftEdge;
                    break;
                case "top":
                    toViewBeginTransform = push ? bottomEdge : topEdge;
                    fromViewEndTransform_1 = push ? topEdge : bottomEdge;
                    break;
                case "bottom":
                    toViewBeginTransform = push ? topEdge : bottomEdge;
                    fromViewEndTransform_1 = push ? bottomEdge : topEdge;
                    break;
            }
            toView_1.transform = toViewBeginTransform;
            fromView_1.transform = CGAffineTransformIdentity;
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
                toView_1.transform = CGAffineTransformIdentity;
                fromView_1.transform = fromViewEndTransform_1;
            }, function (finished) {
                toView_1.transform = originalToViewTransform_1;
                fromView_1.transform = originalFromViewTransform_1;
                transitionContext.completeTransition(finished);
            });
        }
    };
    SlideTransitionController.ObjCProtocols = [UIViewControllerAnimatedTransitioning];
    return SlideTransitionController;
}(NSObject));
export { SlideTransitionController };
//# sourceMappingURL=slide-transition.ios.js.map