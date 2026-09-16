import { Observable } from '../data/observable';
let _windowIdCounter = 0;
/**
 * Cross-platform base for any window surface.
 *
 * Carries identity, role, state, lifecycle events and the native accessors.
 * Surfaces that host a NativeScript view tree extend {@link NativeWindow} instead.
 */
export class WindowBase extends Observable {
    constructor(id, isPrimary = false, role = 'application') {
        super();
        this._state = 'attached';
        this._id = id || `window-${++_windowIdCounter}`;
        this._isPrimary = isPrimary;
        this._role = role;
    }
    get id() {
        return this._id;
    }
    get role() {
        return this._role;
    }
    get state() {
        return this._state;
    }
    get isPrimary() {
        return this._isPrimary;
    }
    /**
     * @internal - used by the Application to promote a window to primary.
     */
    _setIsPrimary(value) {
        this._isPrimary = value;
    }
    /**
     * @internal
     */
    _setState(value) {
        this._state = value;
    }
    get ios() {
        return undefined;
    }
    get android() {
        return undefined;
    }
    on(eventName, callback, thisArg) {
        super.on(eventName, callback, thisArg);
    }
    /**
     * @internal – emit a window lifecycle event.
     */
    _notifyEvent(eventName) {
        this.notify({
            eventName,
            window: this,
            object: this,
        });
    }
    /**
     * @internal – ends the window session for good.
     *
     * Listeners stay live through the whole teardown and are dropped last, so handlers
     * registered on this instance can still observe `close` yet never outlive the window.
     */
    _destroy() {
        this._setState('closed');
        this._onDestroy();
        this._clearEventListeners();
    }
    /**
     * Teardown hook for subclasses. Runs while the listeners are still registered.
     */
    _onDestroy() {
        // noop
    }
}
//# sourceMappingURL=window-base.js.map