import { Observable } from '../../data/observable';
import { Screen } from '../../platform';
import { isNumber } from '../../utils/types';
import { CORE_ANIMATION_DEFAULTS } from '../../utils/animation-helpers';
import { querySelectorAll } from '../core/view-base';
// always increment when adding new transitions to be able to track their state
export var SharedTransitionAnimationType;
(function (SharedTransitionAnimationType) {
    SharedTransitionAnimationType[SharedTransitionAnimationType["present"] = 0] = "present";
    SharedTransitionAnimationType[SharedTransitionAnimationType["dismiss"] = 1] = "dismiss";
})(SharedTransitionAnimationType || (SharedTransitionAnimationType = {}));
class SharedTransitionObservable extends Observable {
    // @ts-ignore
    on(eventNames, callback, thisArg) {
        super.on(eventNames, callback, thisArg);
    }
}
let sharedTransitionEvents;
let currentStack;
// Detached NS subtrees (e.g. a TabView's iosBottomAccessory) that aren't reachable
// from a page via the NS view tree, but whose tagged views should still participate
// in shared transitions. Registered by their owning component; queried alongside
// the source page in getSharedElements. Held weakly so an unregistered-but-forgotten
// root doesn't pin its subtree; dead refs are pruned on query.
let externalRoots;
/**
 * Shared Element Transitions (preview)
 * Allows you to auto animate between shared elements on two different screesn to create smooth navigational experiences.
 * View components can define sharedTransitionTag="name" alone with a transition through this API.
 */
export class SharedTransition {
    /**
     * Configure a custom transition with presentation/dismissal options.
     * @param transition The custom Transition instance.
     * @param options
     * @returns a configured SharedTransition instance for use with navigational APIs.
     */
    static custom(transition, options) {
        SharedTransition.updateState(transition.id, {
            ...(options || {}),
            instance: transition,
            activeType: SharedTransitionAnimationType.present,
        });
        const pageEnd = options?.pageEnd;
        if (isNumber(pageEnd?.duration)) {
            // Android uses milliseconds/iOS uses seconds
            // users pass in milliseconds
            transition.setDuration(__APPLE__ ? pageEnd?.duration / 1000 : pageEnd?.duration);
        }
        return { instance: transition };
    }
    /**
     * Listen to various shared element transition events.
     * @returns Observable
     */
    static events() {
        if (!sharedTransitionEvents) {
            sharedTransitionEvents = new SharedTransitionObservable();
        }
        return sharedTransitionEvents;
    }
    /**
     * Notify a Shared Transition event.
     * @param id transition instance id
     * @param eventName Shared Transition event name
     * @param type TransitionNavigationType
     * @param action SharedTransitionEventAction
     */
    static notifyEvent(eventName, data) {
        switch (eventName) {
            case SharedTransition.startedEvent:
            case SharedTransition.interactiveUpdateEvent:
                SharedTransition.inProgress = true;
                break;
            default:
                SharedTransition.inProgress = false;
                break;
        }
        SharedTransition.events().notify({
            eventName,
            data,
        });
    }
    /**
     * Update transition state.
     * @param id Transition instance id
     * @param state SharedTransitionState
     */
    static updateState(id, state) {
        if (!currentStack) {
            currentStack = [];
        }
        const existingTransition = SharedTransition.getState(id);
        if (existingTransition) {
            // updating existing
            for (const key in state) {
                existingTransition[key] = state[key];
                // console.log(' ... updating state: ', key, state[key])
            }
        }
        else {
            currentStack.push(state);
        }
    }
    /**
     * Get current state for any transition.
     * @param id Transition instance id
     */
    static getState(id) {
        return currentStack?.find((t) => t.instance?.id === id);
    }
    /**
     * Finish transition state.
     * @param id Transition instance id
     */
    static finishState(id) {
        const index = currentStack?.findIndex((t) => t.instance?.id === id);
        if (index > -1) {
            currentStack.splice(index, 1);
        }
    }
    /**
     * Register an NS view subtree that should be searched for sharedTransitionTag
     * elements in addition to the source page. Use this for views that are attached
     * to the native UI but aren't reachable from the page via the NS view tree —
     * for example, a TabView's `iosBottomAccessory`. The root and any of its
     * descendants with a `sharedTransitionTag` will then participate in transitions
     * originating from any page.
     *
     * Registration is idempotent. Pair with `unregisterExternalRoot` on teardown
     * to avoid leaking detached views into future transitions.
     */
    static registerExternalRoot(root) {
        if (!root)
            return;
        if (!externalRoots) {
            externalRoots = [];
        }
        if (!externalRoots.some((ref) => ref.deref() === root)) {
            externalRoots.push(new WeakRef(root));
        }
    }
    /**
     * Remove a previously registered external root. No-op if the root wasn't
     * registered.
     */
    static unregisterExternalRoot(root) {
        if (!root || !externalRoots)
            return;
        externalRoots = externalRoots.filter((ref) => {
            const view = ref.deref();
            return view && view !== root;
        });
    }
    /**
     * Gather view collections based on sharedTransitionTag details.
     * @param fromPage Page moving away from
     * @param toPage Page moving to
     * @returns Collections of views pertaining to shared elements or particular pages
     */
    static getSharedElements(fromPage, toPage) {
        // 1. Presented view: gather all sharedTransitionTag views
        const presentedSharedElements = querySelectorAll(toPage, 'sharedTransitionTag').filter((v) => !v.sharedTransitionIgnore && typeof v.sharedTransitionTag === 'string');
        // console.log('presented sharedTransitionTag total:', presentedSharedElements.length);
        const presentedTags = presentedSharedElements.map((v) => v.sharedTransitionTag);
        // 2. Presenting view: gather all sharedTransitionTag views — and also any
        // tagged views inside external roots (detached subtrees registered by
        // components like TabView's iosBottomAccessory). External roots persist
        // across page navigations, so their views only join the transition when
        // their tag *also* exists on the destination — they participate as
        // matched shared elements, never as orphans that would fade out.
        const presentingSharedElements = querySelectorAll(fromPage, 'sharedTransitionTag').filter((v) => !v.sharedTransitionIgnore && typeof v.sharedTransitionTag === 'string');
        if (externalRoots?.length) {
            externalRoots = externalRoots.filter((ref) => ref.deref());
            for (const ref of externalRoots) {
                const root = ref.deref();
                if (!root)
                    continue;
                const extra = querySelectorAll(root, 'sharedTransitionTag').filter((v) => !v.sharedTransitionIgnore && typeof v.sharedTransitionTag === 'string');
                for (const v of extra) {
                    if (!presentedTags.includes(v.sharedTransitionTag))
                        continue;
                    if (presentingSharedElements.includes(v))
                        continue;
                    presentingSharedElements.push(v);
                }
            }
        }
        // console.log(
        // 	'presenting sharedTransitionTags:',
        // 	presentingSharedElements.map((v) => v.sharedTransitionTag)
        // );
        // 3. only handle sharedTransitionTag on presenting which match presented
        return {
            sharedElements: presentingSharedElements.filter((v) => presentedTags.includes(v.sharedTransitionTag)),
            presented: presentedSharedElements,
            presenting: presentingSharedElements,
        };
    }
}
/**
 * When the transition starts.
 */
SharedTransition.startedEvent = 'SharedTransitionStartedEvent';
/**
 * When the transition finishes.
 */
SharedTransition.finishedEvent = 'SharedTransitionFinishedEvent';
/**
 * When the interactive transition cancels.
 */
SharedTransition.interactiveCancelledEvent = 'SharedTransitionInteractiveCancelledEvent';
/**
 * When the interactive transition updates with the percent value.
 */
SharedTransition.interactiveUpdateEvent = 'SharedTransitionInteractiveUpdateEvent';
/**
 * Enable to see various console logging output of Shared Element Transition behavior.
 */
SharedTransition.DEBUG = false;
/**
 * Get dimensional rectangle (x,y,width,height) from properties with fallbacks for any undefined values.
 * @param props combination of properties conformed to SharedTransitionPageProperties
 * @param defaults fallback properties when props doesn't contain a value for it
 * @returns { x,y,width,height }
 */
export function getRectFromProps(props, defaults) {
    defaults = {
        x: 0,
        y: 0,
        width: getPlatformWidth(),
        height: getPlatformHeight(),
        ...(defaults || {}),
    };
    return {
        x: isNumber(props?.x) ? props?.x : defaults.x,
        y: isNumber(props?.y) ? props?.y : defaults.y,
        width: isNumber(props?.width) ? props?.width : defaults.width,
        height: isNumber(props?.height) ? props?.height : defaults.height,
    };
}
/**
 * Get spring properties with default fallbacks for any undefined values.
 * @param props various spring related properties conforming to SharedSpringProperties
 * @returns
 */
export function getSpringFromProps(props) {
    return {
        tension: isNumber(props?.tension) ? props?.tension : CORE_ANIMATION_DEFAULTS.spring.tension,
        friction: isNumber(props?.friction) ? props?.friction : CORE_ANIMATION_DEFAULTS.spring.friction,
        mass: isNumber(props?.mass) ? props?.mass : CORE_ANIMATION_DEFAULTS.spring.mass,
        velocity: isNumber(props?.velocity) ? props?.velocity : CORE_ANIMATION_DEFAULTS.spring.velocity,
        delay: isNumber(props?.delay) ? props?.delay : 0,
    };
}
/**
 * Page starting defaults for provided type.
 * @param type TransitionNavigationType
 * @returns { x,y,width,height }
 */
export function getPageStartDefaultsForType(type) {
    return {
        x: type === 'page' ? getPlatformWidth() : 0,
        y: type === 'page' ? 0 : getPlatformHeight(),
        width: getPlatformWidth(),
        height: getPlatformHeight(),
    };
}
function getPlatformWidth() {
    return __ANDROID__ ? Screen.mainScreen.widthPixels : Screen.mainScreen.widthDIPs;
}
function getPlatformHeight() {
    return __ANDROID__ ? Screen.mainScreen.heightPixels : Screen.mainScreen.heightDIPs;
}
//# sourceMappingURL=shared-transition.js.map