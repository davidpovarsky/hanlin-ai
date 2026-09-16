import { Transition } from '.';
import { isNumber } from '../../utils/types';
import { CORE_ANIMATION_DEFAULTS, getDurationWithDampingFromSpring } from '../../utils/animation-helpers';
import { GestureStateTypes } from '../gestures';
import { ios as iOSUtils } from '../../utils/native-helper';
import { SharedTransition, SharedTransitionAnimationType } from './shared-transition';
import { SharedTransitionHelper, removeInteractiveDismissShadow, syncInteractiveDismissShadow } from './shared-transition-helper';
function _findInnerScroll(view) {
    // Walk the destination's view subtree breadth-first looking for the first
    // UIScrollView. Returned so the dismiss handler can both read its current
    // contentOffset (to tell "was scrolled" from "was at top") and pin it in
    // place while an interactive dismiss is engaged.
    if (!view)
        return null;
    const queue = [view];
    while (queue.length) {
        const v = queue.shift();
        if (!v)
            continue;
        if (v instanceof UIScrollView) {
            return v;
        }
        const subviews = v.subviews;
        if (!subviews)
            continue;
        for (let i = 0; i < subviews.count; i++) {
            queue.push(subviews.objectAtIndex(i));
        }
    }
    return null;
}
export class PageTransition extends Transition {
    constructor() {
        super(...arguments);
        // Tracks the gesture's lifecycle:
        //  - 'idle'    : no active touch.
        //  - 'pending' : touched and might be panning, but we haven't seen enough
        //                motion to know whether it's a dismiss or a scroll.
        //  - 'active'  : confirmed dismiss intent — UIKit interactive transition
        //                is engaged and the morph transform tracks the finger.
        //  - 'ignored' : determined the gesture is a scroll (or upward at the top
        //                of a non-scrolling area); we let the gesture run out
        //                without engaging UIKit.
        this._gesturePhase = 'idle';
        this._gestureScrollY = 0;
        // The inner UIScrollView (if any) discovered at gesture-began. Held so we
        // can freeze it (scrollEnabled = false) while the dismiss is active and
        // restore the prior value when the gesture ends.
        this._innerScroll = null;
        // Captured at engagement: the matching source element's frame expressed in
        // the destination view's coordinate system. Morph progress interpolates
        // from identity toward this frame so the destination shrinks into place.
        this._morphTarget = null;
    }
    iosNavigatedController(navigationController, operation, fromVC, toVC) {
        this.navigationController = navigationController;
        if (!this.transitionController) {
            this.presented = toVC;
            this.presenting = fromVC;
        }
        this.transitionController = PageTransitionController.initWithOwner(new WeakRef(this));
        // console.log('iosNavigatedController presenting:', this.presenting);
        this.operation = operation;
        return this.transitionController;
    }
    iosInteractionDismiss(animator) {
        // console.log('-- iosInteractionDismiss --');
        this.interactiveController = PercentInteractiveController.initWithOwner(new WeakRef(this));
        return this.interactiveController;
    }
    setupInteractiveGesture(startCallback, view) {
        // console.log(' -- setupInteractiveGesture --');
        this._interactiveStartCallback = startCallback;
        if (!this._interactiveDismissGesture) {
            // console.log('setup but tearing down first!');
            view.off('pan', this._interactiveDismissGesture);
            this._interactiveDismissGesture = this._interactiveDismissGestureHandler.bind(this);
        }
        view.on('pan', this._interactiveDismissGesture);
        this._interactiveGestureTeardown = () => {
            // console.log(`-- TEARDOWN setupInteractiveGesture --`);
            if (view) {
                view.off('pan', this._interactiveDismissGesture);
            }
            this._interactiveDismissGesture = null;
        };
        return this._interactiveGestureTeardown;
    }
    _interactiveDismissGestureHandler(args) {
        if (!args?.ios?.view)
            return;
        const state = SharedTransition.getState(this.id);
        if (!state) {
            this._teardownGesture();
            return;
        }
        const morph = !!state.interactive?.dismiss?.morph;
        const morphOptions = typeof state.interactive?.dismiss?.morph === 'object' ? state.interactive.dismiss.morph : null;
        const viewW = args.ios.view.bounds.size.width;
        const viewH = args.ios.view.bounds.size.height;
        const dx = args.deltaX;
        const dy = args.deltaY;
        const dist = Math.hypot(dx, dy);
        const morphPercent = dist / viewH;
        const percent = state.interactive?.dismiss?.percentFormula ? state.interactive.dismiss.percentFormula(args) : morph ? morphPercent : dx / viewW;
        if (SharedTransition.DEBUG) {
            console.log('Interactive dismissal percentage:', percent, 'phase:', this._gesturePhase);
        }
        switch (args.state) {
            case GestureStateTypes.began: {
                // Defensive reset: a previous interactive dismiss may have been
                // interrupted before its cleanup ran, leaving a lingering
                // transform on the presented view or alpha=0 on source views.
                // Recover from that here so each gesture starts from a clean
                // slate regardless of prior animation state.
                const presentedView = this.presented?.view;
                if (presentedView) {
                    presentedView.transform = CGAffineTransformIdentity;
                    presentedView.alpha = 1;
                }
                const sources = state.instance?.sharedElements?._allPresentingViews || [];
                for (const v of sources) {
                    if (v?.ios)
                        v.ios.alpha = v.opacity ?? 1;
                }
                // Don't engage UIKit yet — we need a few points of motion to know
                // whether this is a dismiss gesture or a scroll. Cache the inner
                // scrollview and its contentOffset at gesture start so the decision
                // can tell "was scrolled" from "was at top".
                this._gesturePhase = 'pending';
                this._innerScroll = _findInnerScroll(this.presented?.view);
                this._gestureScrollY = this._innerScroll?.contentOffset.y ?? 0;
                break;
            }
            case GestureStateTypes.changed:
                if (this._gesturePhase === 'ignored')
                    return;
                if (this._gesturePhase === 'pending') {
                    // Wait for enough motion to make a confident direction call.
                    const motionThreshold = 8;
                    const absX = Math.abs(dx);
                    const absY = Math.abs(dy);
                    if (absX < motionThreshold && absY < motionThreshold)
                        return;
                    const horizontalDominant = absX > absY;
                    const downward = dy > 0;
                    const scrollWasAtTop = this._gestureScrollY <= 0;
                    // Engagement rule:
                    //  - Primarily horizontal motion → always allow (swipe-back).
                    //  - Vertical-downward motion → only when the inner scrollview
                    //    was at its top at gesture start (sheet-style dismiss).
                    //  - Anything else → ignore so the scrollview can take over.
                    const shouldEngage = horizontalDominant || (downward && scrollWasAtTop);
                    if (!shouldEngage) {
                        this._gesturePhase = 'ignored';
                        return;
                    }
                    this._gesturePhase = 'active';
                    // Freeze the inner scrollview at its current offset for the
                    // duration of the dismiss so the page contents don't scroll
                    // along with the dismiss drag (which would shift the morph
                    // source mid-flight and make the snap-back look off).
                    if (this._innerScroll) {
                        this._scrollWasEnabled = this._innerScroll.scrollEnabled;
                        this._innerScroll.scrollEnabled = false;
                    }
                    SharedTransition.updateState(this.id, {
                        interactiveBegan: true,
                        interactiveCancelled: false,
                    });
                    if (this._interactiveStartCallback) {
                        this._interactiveStartCallback();
                    }
                    // Compute morph target: the matching source element's frame in
                    // the destination view's coordinate system. We capture it once
                    // at engagement so subsequent moves interpolate toward a stable
                    // anchor, even if the source page is scrolled during the drag.
                    this._morphTarget = null;
                    const stateNow = SharedTransition.getState(this.id);
                    if (morph && stateNow) {
                        const presented = stateNow.instance?.sharedElements?.presented?.[0];
                        const destTag = presented?.view?.sharedTransitionTag;
                        const sources = stateNow.instance?.sharedElements?._allPresentingViews || [];
                        const matchingSource = sources.find?.((v) => v?.sharedTransitionTag === destTag) || sources[0];
                        const srcIos = matchingSource?.ios;
                        const destView = this.presented?.view;
                        const destSharedIos = presented?.view?.ios;
                        if (srcIos && destView) {
                            const f = srcIos.convertRectToView(srcIos.bounds, destView);
                            const bounds = destView.bounds;
                            if (bounds.size.width > 0 && bounds.size.height > 0 && f.size.width > 0) {
                                // Uniform scale during drag — feels grabbed/proportional
                                // rather than squished. The release spring switches to
                                // non-uniform scale + anchored translation in interactiveFinish
                                // so the modal's matched element lands exactly on the source.
                                const scaleT = Math.min(f.size.width / bounds.size.width, f.size.height / bounds.size.height);
                                // Anchor on the modal's internal matched element so the
                                // modal and the matched element snapshot converge on the
                                // source thumbnail along the same trajectory, instead of
                                // the modal drifting toward a center-of-modal target while
                                // the matched snapshot heads to the source.
                                let txT;
                                let tyT;
                                const sharedFrameInModal = destSharedIos ? destSharedIos.convertRectToView(destSharedIos.bounds, destView) : null;
                                if (sharedFrameInModal && sharedFrameInModal.size.width > 0 && sharedFrameInModal.size.height > 0) {
                                    const internalCx = sharedFrameInModal.origin.x + sharedFrameInModal.size.width / 2;
                                    const internalCy = sharedFrameInModal.origin.y + sharedFrameInModal.size.height / 2;
                                    txT = f.origin.x + f.size.width / 2 - bounds.size.width / 2 - (internalCx - bounds.size.width / 2) * scaleT;
                                    tyT = f.origin.y + f.size.height / 2 - bounds.size.height / 2 - (internalCy - bounds.size.height / 2) * scaleT;
                                }
                                else {
                                    txT = f.origin.x + f.size.width / 2 - bounds.size.width / 2;
                                    tyT = f.origin.y + f.size.height / 2 - bounds.size.height / 2;
                                }
                                this._morphTarget = { scale: scaleT, tx: txT, ty: tyT };
                            }
                        }
                        // Hide every source-side element so it doesn't show through
                        // the morphing destination. Restored on cancel/finish.
                        for (const v of sources) {
                            if (v?.ios)
                                v.ios.alpha = 0;
                        }
                        // Reveal source-only orphan views (e.g. other album thumbnails,
                        // section headers' info) so the source page looks intact behind
                        // the morphing modal. They were hidden during present; without
                        // restoring them now, the user sees blank spots through the
                        // shrinking modal where artwork/text should be.
                        //
                        // We also re-apply each view's NS background to nudge UIKit into
                        // re-displaying the layer with its corner-radius mask. Without
                        // this, some plugin-backed image views (e.g. SDAnimatedImageView)
                        // render their cached content with square corners during the
                        // transition's compositor pass even though the layer's
                        // cornerRadius/masksToBounds are still set correctly.
                        for (const ind of stateNow.instance?.sharedElements?.independent || []) {
                            if (!ind.isPresented && ind.view?.ios) {
                                ind.view.ios.alpha = ind.view.opacity;
                                const v = ind.view;
                                if (typeof v._redrawNativeBackground === 'function') {
                                    try {
                                        v._redrawNativeBackground(v.style?.backgroundInternal);
                                    }
                                    catch (_) { }
                                }
                                ind.view.ios.layer?.setNeedsDisplay?.();
                            }
                        }
                        // Dismiss shadow is applied from SharedTransitionHelper.interactiveStart
                        // (it runs after UIKit has reparented the presented view into the
                        // transition's containerView).
                    }
                }
                if (this._gesturePhase !== 'active')
                    return;
                if (morph) {
                    const presentedView = this.presented?.view;
                    if (presentedView) {
                        const minScale = morphOptions?.minScale ?? 0.2;
                        // Interpolate from identity (t=0) toward the source frame
                        // (t=1) as the drag progresses. `t` accelerates the morph so
                        // the destination noticeably shrinks within typical drag
                        // distances rather than staying near full size.
                        const t = Math.min(dist / (viewH * 0.5), 1);
                        const target = this._morphTarget;
                        let scale;
                        let tx;
                        let ty;
                        if (target) {
                            const targetScale = Math.max(target.scale, minScale);
                            scale = 1 + (targetScale - 1) * t;
                            // Blend finger-follow (1-t weight) with target-attract
                            // (t weight) so the view feels grabbed but gravitates
                            // toward the source as the user commits.
                            tx = dx * (1 - t) + target.tx * t;
                            ty = dy * (1 - t) + target.ty * t;
                        }
                        else {
                            scale = Math.max(minScale, 1 - t * (1 - minScale));
                            tx = dx;
                            ty = dy;
                        }
                        presentedView.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(tx, ty), CGAffineTransformMakeScale(scale, scale));
                    }
                }
                if (percent < 1 && this.interactiveController) {
                    this.interactiveController.updateInteractiveTransition(percent);
                }
                // Mirror the destination's current visual state onto the sibling
                // shadow layer. Done for both morph (direct transform) and non-morph
                // (UIViewPropertyAnimator-driven) — sync reads the presentation
                // layer so it works for both.
                syncInteractiveDismissShadow(this.presented?.view);
                break;
            case GestureStateTypes.cancelled:
            case GestureStateTypes.ended: {
                const phase = this._gesturePhase;
                this._gesturePhase = 'idle';
                // Restore the inner scrollview's scrollEnabled regardless of
                // whether the gesture engaged or was ignored.
                if (this._innerScroll && this._scrollWasEnabled !== undefined) {
                    this._innerScroll.scrollEnabled = this._scrollWasEnabled;
                    this._scrollWasEnabled = undefined;
                }
                this._innerScroll = null;
                if (phase !== 'active') {
                    // Either the gesture never crossed the engagement threshold or
                    // we explicitly ignored it (a scroll). Nothing to wind down.
                    return;
                }
                const finishThreshold = isNumber(state.interactive?.dismiss?.finishThreshold) ? state.interactive.dismiss.finishThreshold : 0.5;
                const shouldFinish = percent > finishThreshold;
                if (this.interactiveController) {
                    if (shouldFinish) {
                        this._teardownGesture();
                        this.interactiveController.finishInteractiveTransition();
                    }
                    else {
                        SharedTransition.updateState(this.id, {
                            interactiveCancelled: true,
                        });
                        this.interactiveController.cancelInteractiveTransition();
                    }
                    // Always restore the modal's layer state we touched to render
                    // the dismiss shadow — on cancel (view is being kept) AND on
                    // finish (the same NS view instance may be reused on the next
                    // presentation, so leaked layer state stacks across dismissals).
                    removeInteractiveDismissShadow(this.presented?.view);
                }
                else if (morph) {
                    // Fallback: UIKit didn't engage. Reset the morph transform so the
                    // destination doesn't stay stuck.
                    const presentedView = this.presented?.view;
                    if (presentedView) {
                        iOSUtils.animateWithSpring({
                            animations: () => {
                                presentedView.transform = CGAffineTransformIdentity;
                            },
                        });
                    }
                }
                break;
            }
        }
    }
    _teardownGesture() {
        if (this._interactiveGestureTeardown) {
            this._interactiveGestureTeardown();
            this._interactiveGestureTeardown = null;
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
                SharedTransitionHelper.interactiveStart(state, this.interactiveState, "page");
            }
        }
    };
    PercentInteractiveController.prototype.updateInteractiveTransition = function (percentComplete) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            SharedTransitionHelper.interactiveUpdate(state, this.interactiveState, "page", percentComplete);
        }
    };
    PercentInteractiveController.prototype.cancelInteractiveTransition = function () {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            SharedTransitionHelper.interactiveCancel(state, this.interactiveState, "page");
        }
    };
    PercentInteractiveController.prototype.finishInteractiveTransition = function () {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref( //  - 'idle'    : no active touch.
        //  - 'pending' : touched and might be panning, but we haven't seen enough
        //                motion to know whether it's a dismiss or a scroll.
        //  - 'active'  : confirmed dismiss intent — UIKit interactive transition
        //                is engaged and the morph transform tracks the finger.
        //  - 'ignored' : determined the gesture is a scroll (or upward at the top
        //                of a non-scrolling area); we let the gesture run out
        //                without engaging UIKit.
        );
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            SharedTransitionHelper.interactiveFinish(state, this.interactiveState, "page");
        }
    };
    PercentInteractiveController.ObjCProtocols = [UIViewControllerInteractiveTransitioning];
    return PercentInteractiveController;
}(UIPercentDrivenInteractiveTransition));
var PageTransitionController = (function (_super) {
    __extends(PageTransitionController, _super);
    function PageTransitionController() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    PageTransitionController.initWithOwner = function (owner) {
        var ctrl = PageTransitionController.new();
        ctrl.owner = owner;
        return ctrl;
    };
    PageTransitionController.prototype.transitionDuration = function (transitionContext) {
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
    PageTransitionController.prototype.animateTransition = function (transitionContext) {
        var owner = this.owner.deref();
        if (owner) {
            var state = SharedTransition.getState(owner.id);
            if (!state) {
                return;
            }
            SharedTransitionHelper.animate(state, transitionContext, "page");
        }
    };
    PageTransitionController.ObjCProtocols = [UIViewControllerAnimatedTransitioning];
    return PageTransitionController;
}(NSObject));
//# sourceMappingURL=page-transition.ios.js.map