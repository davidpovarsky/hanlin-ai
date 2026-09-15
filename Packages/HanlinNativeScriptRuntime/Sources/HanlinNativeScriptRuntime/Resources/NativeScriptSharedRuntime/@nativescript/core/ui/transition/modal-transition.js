import { CORE_ANIMATION_DEFAULTS, getDurationWithDampingFromSpring } from '../../utils/animation-helpers';
import { isNumber } from '../../utils/types';
import { Transition } from '.';
import { SharedTransition, SharedTransitionAnimationType } from './shared-transition';
import { SharedTransitionHelper, removeInteractiveDismissShadow, syncInteractiveDismissShadow } from './shared-transition-helper';
import { GestureStateTypes } from '../gestures';
export class ModalTransition extends Transition {
    iosPresentedController(presented, presenting, source) {
        this.transitionController = ModalTransitionController.initWithOwner(new WeakRef(this));
        this.presented = presented;
        // console.log('presenting:', presenting)
        return this.transitionController;
    }
    iosDismissedController(dismissed) {
        this.transitionController = ModalTransitionController.initWithOwner(new WeakRef(this));
        this.presented = dismissed;
        return this.transitionController;
    }
    iosInteractionDismiss(animator) {
        // console.log('-- iosInteractionDismiss --');
        this.interactiveController = PercentInteractiveController.initWithOwner(new WeakRef(this));
        return this.interactiveController;
    }
    iosInteractionPresented(animator) {
        // console.log('-- iosInteractionPresented --');
        return null;
    }
    setupInteractiveGesture(startCallback, view) {
        this._interactiveStartCallback = startCallback;
        this._interactiveDismissGesture = this._interactiveDismissGestureHandler.bind(this);
        view.on('pan', this._interactiveDismissGesture);
        // this.interactiveGestureRecognizer = UIScreenEdgePanGestureRecognizer.alloc().initWithTargetAction()
        // 			let edgeSwipeGestureRecognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        // edgeSwipeGestureRecognizer.edges = .left
        // view.addGestureRecognizer(edgeSwipeGestureRecognizer)
    }
    _interactiveDismissGestureHandler(args) {
        if (args?.ios?.view) {
            const state = SharedTransition.getState(this.id);
            const morph = !!state.interactive?.dismiss?.morph;
            const morphOptions = typeof state.interactive?.dismiss?.morph === 'object' ? state.interactive.dismiss.morph : null;
            const viewH = args.ios.view.bounds.size.height;
            const dist = Math.hypot(args.deltaX, args.deltaY);
            const morphPercent = dist / viewH;
            // 1:1 with finger movement (SwiftUI default). Dragging across the full
            // view height corresponds to percent = 1. Halving the divisor — the
            // previous default — made the modal run twice as fast as the finger.
            const percent = state.interactive?.dismiss?.percentFormula ? state.interactive.dismiss.percentFormula(args) : morph ? morphPercent : args.deltaY / viewH;
            if (SharedTransition.DEBUG) {
                console.log('Interactive dismissal percentage:', percent);
            }
            switch (args.state) {
                case GestureStateTypes.began:
                    SharedTransition.updateState(this.id, {
                        interactiveBegan: true,
                        interactiveCancelled: false,
                    });
                    // Dismiss shadow is applied from SharedTransitionHelper.interactiveStart
                    // (it runs after UIKit has reparented the modal view into the
                    // transition's containerView).
                    if (this._interactiveStartCallback) {
                        this._interactiveStartCallback();
                    }
                    break;
                case GestureStateTypes.changed:
                    if (morph) {
                        const presentedView = this.presented?.view;
                        if (presentedView) {
                            const minScale = morphOptions?.minScale ?? 0.5;
                            const scale = Math.max(minScale, 1 - dist / viewH);
                            presentedView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(args.deltaX, args.deltaY), CGAffineTransformMakeScale(scale, scale));
                        }
                    }
                    if (percent < 1 && this.interactiveController) {
                        this.interactiveController.updateInteractiveTransition(percent);
                    }
                    // Mirror the modal's current visual state onto the sibling shadow
                    // layer. Done for both morph (direct transform) and non-morph
                    // (UIViewPropertyAnimator-driven frame/cornerRadius) — sync reads
                    // the presentation layer so it works for both.
                    syncInteractiveDismissShadow(this.presented?.view);
                    break;
                case GestureStateTypes.cancelled:
                case GestureStateTypes.ended:
                    if (this.interactiveController) {
                        const finishThreshold = isNumber(state.interactive?.dismiss?.finishThreshold) ? state.interactive.dismiss.finishThreshold : 0.5;
                        if (percent > finishThreshold) {
                            this.interactiveController.finishInteractiveTransition();
                        }
                        else {
                            SharedTransition.updateState(this.id, {
                                interactiveCancelled: true,
                            });
                            this.interactiveController.cancelInteractiveTransition();
                        }
                        // Always restore the modal's layer state we touched to render
                        // the dismiss shadow — both on cancel (view is being kept) and
                        // on finish (the same NS view instance may be reused on a
                        // subsequent presentation, and leaked shadow state would
                        // stack up across dismissals).
                        removeInteractiveDismissShadow(this.presented?.view);
                    }
                    break;
            }
        }
    }
}
var PercentInteractiveController = (function (_super) {
    __extends(PercentInteractiveController, _super);
    function PercentInteractiveController() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    PercentInteractiveController.initWithOwner = function (owner) {
        var ctrl = PercentInteractiveController.new();
        ctrl.owner = owner;
        return ctrl;
    };
    PercentInteractiveController.prototype.startInteractiveTransition = function (transitionContext) {
        var _a;
        if (!this.interactiveState) {
            this.interactiveState = {
                transitionContext: transitionContext,
            };
            var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
            if (owner) {
                var state = SharedTransition.getState(owner.id);
                SharedTransitionHelper.interactiveStart(state, this.interactiveState, "modal");
            }
        }
    };
    PercentInteractiveController.prototype.updateInteractiveTransition = function (percentComplete) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            SharedTransitionHelper.interactiveUpdate(state, this.interactiveState, "modal", percentComplete);
        }
    };
    PercentInteractiveController.prototype.cancelInteractiveTransition = function () {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            SharedTransitionHelper.interactiveCancel(state, this.interactiveState, "modal");
        }
    };
    PercentInteractiveController.prototype.finishInteractiveTransition = function () {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            SharedTransitionHelper.interactiveFinish(state, this.interactiveState, "modal");
        }
    };
    PercentInteractiveController.ObjCProtocols = [UIViewControllerInteractiveTransitioning];
    return PercentInteractiveController;
}(UIPercentDrivenInteractiveTransition));
var ModalTransitionController = (function (_super) {
    __extends(ModalTransitionController, _super);
    function ModalTransitionController() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    ModalTransitionController.initWithOwner = function (owner) {
        var ctrl = ModalTransitionController.new();
        ctrl.owner = owner;
        return ctrl;
    };
    ModalTransitionController.prototype.transitionDuration = function (transitionContext) {
        var _a, _b, _c, _d, _e, _f;
        var owner = this.owner.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            switch (state === null || state === void 0 ? void 0 : state.activeType) {
                case SharedTransitionAnimationType.present: if (isNumber((_a = state === null || state === void 0 ? void 0 : state.pageEnd) === null || _a === void 0 ? void 0 : _a.duration)) {
                    return ((_b = state.pageEnd) === null || _b === void 0 ? void 0 : _b.duration) / 1000;
                }
                else {
                    return getDurationWithDampingFromSpring((_c = state.pageEnd) === null || _c === void 0 ? void 0 : _c.spring).duration;
                }
                case SharedTransitionAnimationType.dismiss: if (isNumber((_d = state === null || state === void 0 ? void 0 : state.pageReturn) === null || _d === void 0 ? void 0 : _d.duration)) {
                    return ((_e = state.pageReturn) === null || _e === void 0 ? void 0 : _e.duration) / 1000;
                }
                else {
                    return getDurationWithDampingFromSpring((_f = state.pageReturn) === null || _f === void 0 ? void 0 : _f.spring).duration;
                }
            }
        }
        return CORE_ANIMATION_DEFAULTS.duration;
    };
    ModalTransitionController.prototype.animateTransition = function (transitionContext) {
        var owner = this.owner.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            if (!state) {
                return;
            }
            SharedTransitionHelper.animate(state, transitionContext, "modal");
        }
    };
    ModalTransitionController.ObjCProtocols = [UIViewControllerAnimatedTransitioning];
    return ModalTransitionController;
}(NSObject));
//# sourceMappingURL=modal-transition.ios.js.map