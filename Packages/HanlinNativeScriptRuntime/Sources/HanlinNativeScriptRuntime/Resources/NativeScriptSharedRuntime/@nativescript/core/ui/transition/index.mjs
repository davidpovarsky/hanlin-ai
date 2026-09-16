import { CORE_ANIMATION_DEFAULTS } from '../../utils/animation-helpers';
let transitionId = 0;
export class Transition {
    constructor(duration = 350, nativeCurve = 0 /* UIViewAnimationCurve.EaseInOut */) {
        this._duration = duration ? duration / 1000 : CORE_ANIMATION_DEFAULTS.duration;
        this._curve = nativeCurve;
        transitionId++;
        this.id = transitionId;
    }
    getDuration() {
        return this._duration;
    }
    setDuration(value) {
        this._duration = value;
    }
    getCurve() {
        return this._curve;
    }
    animateIOSTransition(transitionContext, fromViewCtrl, toViewCtrl, operation) {
        throw new Error('Abstract method call');
    }
    createAndroidAnimator(transitionType) {
        throw new Error('Abstract method call');
    }
    toString() {
        return `Transition@${this.id}`;
    }
}
Transition.AndroidTransitionType = {};
//# sourceMappingURL=index.ios.js.map