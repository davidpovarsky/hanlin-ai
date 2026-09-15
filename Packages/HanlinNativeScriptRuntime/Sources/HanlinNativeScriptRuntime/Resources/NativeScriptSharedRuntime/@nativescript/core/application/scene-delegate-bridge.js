/**
 * Bridges scene delegate callbacks back onto the `UIApplicationDelegate` methods that UIKit
 * stops calling once an app adopts scenes, so handlers registered through
 * `Application.ios.addDelegateHandler()` keep firing.
 *
 * `addDelegateHandler` chains handlers onto the delegate *prototype*, so forwarding means
 * invoking that prototype method — there is no other entry point to the chain.
 */
function getLegacyMethod(delegate, methodName) {
    const method = delegate?.prototype?.[methodName];
    return typeof method === 'function' ? method : undefined;
}
/**
 * The delegate prototype methods are written to run against the live app delegate instance,
 * so they are called with it whenever the app has one.
 */
function getDelegateInstance(delegate, application) {
    return application?.delegate ?? delegate?.prototype;
}
/**
 * Rebuilds the options dictionary `applicationOpenURLOptions` expects from the scene-side
 * {@link UISceneOpenURLOptions}. Keys with no value are left out, matching what UIKit passes.
 */
export function buildOpenURLOptions(options) {
    const result = NSMutableDictionary.alloc().init();
    if (!options) {
        return result;
    }
    const set = (key, value) => {
        if (key != null && value != null) {
            result.setObjectForKey(value, key);
        }
    };
    set(UIApplicationOpenURLOptionsSourceApplicationKey, options.sourceApplication);
    set(UIApplicationOpenURLOptionsAnnotationKey, options.annotation);
    set(UIApplicationOpenURLOptionsOpenInPlaceKey, options.openInPlace);
    return result;
}
/**
 * Forwards a scene URL delivery to `applicationOpenURLOptions`.
 *
 * @returns whether a legacy handler was found and invoked.
 */
export function forwardOpenURLContexts(delegate, application, urlContexts) {
    const method = getLegacyMethod(delegate, 'applicationOpenURLOptions');
    if (!method) {
        return false;
    }
    const contexts = urlContexts?.allObjects;
    const count = contexts?.count ?? 0;
    if (!count) {
        return false;
    }
    const thisArg = getDelegateInstance(delegate, application);
    // The legacy callback carries a single URL, so a delivery of several contexts becomes
    // one legacy call per context rather than one call for the set.
    for (let i = 0; i < count; i++) {
        const context = contexts.objectAtIndex(i);
        if (!context) {
            continue;
        }
        method.call(thisArg, application, context.URL, buildOpenURLOptions(context.options));
    }
    return true;
}
/**
 * Forwards a scene activity continuation to `applicationContinueUserActivityRestorationHandler`.
 *
 * @returns whether a legacy handler was found and invoked.
 */
export function forwardContinueUserActivity(delegate, application, userActivity) {
    const method = getLegacyMethod(delegate, 'applicationContinueUserActivityRestorationHandler');
    if (!method || !userActivity) {
        return false;
    }
    // The scene callback has no restoration handler to bridge — UIKit restores the scene's
    // responders itself — but the legacy signature requires one to be callable.
    const restorationHandler = (_restorableObjects) => {
        /* no restorable objects to hand back in scene mode */
    };
    method.call(getDelegateInstance(delegate, application), application, userActivity, restorationHandler);
    return true;
}
/**
 * Hands a scene quick action to `applicationPerformActionForShortcutItemCompletionHandler`,
 * or reports it unhandled when no such handler is registered.
 *
 * Together with the repeat-call guard in {@link oneShotCompletion} this is what makes `deliver`
 * run exactly once: a legacy handler owns the result when there is one, and the fallback covers
 * the case where nothing else would ever report back to iOS.
 *
 * @returns whether a legacy handler was found and invoked.
 */
export function deliverShortcutItem(delegate, application, shortcutItem, deliver) {
    const method = getLegacyMethod(delegate, 'applicationPerformActionForShortcutItemCompletionHandler');
    if (!method) {
        deliver(false);
        return false;
    }
    method.call(getDelegateInstance(delegate, application), application, shortcutItem, deliver);
    return true;
}
/**
 * Wraps a native completion handler so only the first result reaches it. iOS treats a
 * completion handler invoked twice as a programming error, and the same handler is exposed
 * to both event listeners and legacy delegate handlers.
 */
export function oneShotCompletion(completionHandler) {
    let delivered = false;
    const deliver = ((handled) => {
        if (delivered) {
            return;
        }
        delivered = true;
        completionHandler?.(handled);
    });
    Object.defineProperty(deliver, 'delivered', {
        get: () => delivered,
    });
    return deliver;
}
//# sourceMappingURL=scene-delegate-bridge.js.map