let _wrappedIndex = 0;
/**
 * Helper class that is used to fire property change even when real object is the same.
 * By default property change will not be fired for a same object.
 * By wrapping object into a WrappedValue instance `same object restriction` will be passed.
 */
export class WrappedValue {
    /**
     * Creates an instance of WrappedValue object.
     * @param wrapped - the real value which should be wrapped.
     */
    constructor(
    /**
     * Property which holds the real value.
     */
    wrapped) {
        this.wrapped = wrapped;
    }
    /**
     * Gets the real value of previously wrappedValue.
     * @param value - Value that should be unwraped. If there is no wrappedValue property of the value object then value will be returned.
     */
    static unwrap(value) {
        return value instanceof WrappedValue ? value.wrapped : value;
    }
    /**
     * Returns an instance of WrappedValue. The actual instance is get from a WrappedValues pool.
     * @param value - Value that should be wrapped.
     */
    static wrap(value) {
        const w = _wrappedValues[_wrappedIndex++ % 5];
        w.wrapped = value;
        return w;
    }
}
const _wrappedValues = [new WrappedValue(null), new WrappedValue(null), new WrappedValue(null), new WrappedValue(null), new WrappedValue(null)];
const _globalEventHandlers = {};
// Tracks how many listeners are registered through the deprecated static
// event-handling APIs so that `notify` can skip the global-handler lookups
// entirely in the common case where none are used. The count may overshoot
// when a `once` global listener is spliced during dispatch — that only causes
// harmless extra lookups, never skipped notifications.
let _globalEventHandlersCount = 0;
/**
 * Observable is used when you want to be notified when a change occurs. Use on/off methods to add/remove listener.
 * Please note that should you be using the `new Observable({})` constructor, it is **obsolete** since v3.0,
 * and you have to migrate to the "data/observable" `fromObject({})` or the `fromObjectRecursive({})` functions.
 */
export class Observable {
    constructor() {
        this._observers = {};
    }
    /**
     * Gets the value of the specified property.
     */
    get(name) {
        return this[name];
    }
    /**
     * Updates the specified property with the provided value.
     */
    set(name, value) {
        // TODO: Parameter validation
        const oldValue = this[name];
        if (this[name] === value) {
            return;
        }
        const newValue = WrappedValue.unwrap(value);
        this[name] = newValue;
        this.notifyPropertyChange(name, newValue, oldValue);
    }
    /**
     * Updates the specified property with the provided value and raises a property change event and a specific change event based on the property name.
     */
    setProperty(name, value) {
        const oldValue = this[name];
        if (this[name] === value) {
            return;
        }
        this[name] = value;
        this.notifyPropertyChange(name, value, oldValue);
        const specificPropertyChangeEventName = name + 'Change';
        if (this.hasListeners(specificPropertyChangeEventName)) {
            const eventData = this._createPropertyChangeData(name, value, oldValue);
            eventData.eventName = specificPropertyChangeEventName;
            this.notify(eventData);
        }
    }
    /**
     * Adds a listener for the specified event name.
     *
     * @param eventName The name of the event.
     * @param callback The event listener to add. Will be called when an event of
     * the given name is raised.
     * @param thisArg An optional parameter which, when set, will be bound as the
     * `this` context when the callback is called. Falsy values will be not be
     * bound.
     */
    on(eventName, callback, thisArg) {
        this.addEventListener(eventName, callback, thisArg);
    }
    /**
     * Adds a listener for the specified event name, which, once fired, will
     * remove itself.
     *
     * @param eventName The name of the event.
     * @param callback The event listener to add. Will be called when an event of
     * the given name is raised.
     * @param thisArg An optional parameter which, when set, will be bound as the
     * `this` context when the callback is called. Falsy values will be not be
     * bound.
     */
    once(eventName, callback, thisArg) {
        this.addEventListener(eventName, callback, thisArg, true);
    }
    /**
     * Removes the listener(s) for the specified event name.
     *
     * @param eventName The name of the event.
     * @param callback An optional specific event listener to remove (if omitted,
     * all event listeners by this name will be removed).
     * @param thisArg An optional parameter which, when set, will be used to
     * refine search of the correct event listener to be removed.
     */
    off(eventName, callback, thisArg) {
        this.removeEventListener(eventName, callback, thisArg);
    }
    /**
     * Adds a listener for the specified event name.
     * @param eventName Name of the event to attach to.
     * @param callback A function to be called when some of the specified event(s) is raised.
     * @param thisArg An optional parameter which when set will be used as "this" in callback method call.
     * @param once An optional parameter which when set will cause the event listener to fire once.
     */
    addEventListener(eventName, callback, thisArg, once) {
        once = once || undefined;
        thisArg = thisArg || undefined;
        if (typeof eventName !== 'string') {
            throw new TypeError('Event name must be a string.');
        }
        if (typeof callback !== 'function') {
            throw new TypeError('Callback, if provided, must be a function.');
        }
        const list = this._getEventList(eventName, true);
        if (Observable._indexOfListener(list, callback, thisArg) !== -1) {
            // Already added.
            return;
        }
        list.push({
            callback,
            thisArg,
            once,
        });
    }
    /**
     * Removes listener(s) for the specified event name.
     * @param eventName Name of the event to attach to.
     * @param callback An optional parameter pointing to a specific listener. If not defined, all listeners for the event names will be removed.
     * @param thisArg An optional parameter which when set will be used to refine search of the correct callback which will be removed as event listener.
     */
    removeEventListener(eventName, callback, thisArg) {
        thisArg = thisArg || undefined;
        if (typeof eventName !== 'string') {
            throw new TypeError('Events name(s) must be string.');
        }
        if (callback && typeof callback !== 'function') {
            throw new TypeError('callback must be function.');
        }
        const entries = this._observers[eventName];
        if (!entries) {
            return;
        }
        Observable.innerRemoveEventListener(entries, callback, thisArg);
        if (!entries.length) {
            // Clear all entries of this type
            delete this._observers[eventName];
        }
    }
    /**
     * Removes every listener registered on this instance.
     * @internal
     */
    _clearEventListeners() {
        for (const eventName in this._observers) {
            delete this._observers[eventName];
        }
    }
    /**
     * Please avoid using the static event-handling APIs as they will be removed
     * in future.
     * @deprecated
     */
    static on(eventName, callback, thisArg, once) {
        this.addEventListener(eventName, callback, thisArg, once);
    }
    /**
     * Please avoid using the static event-handling APIs as they will be removed
     * in future.
     * @deprecated
     */
    static once(eventName, callback, thisArg) {
        this.addEventListener(eventName, callback, thisArg, true);
    }
    /**
     * Please avoid using the static event-handling APIs as they will be removed
     * in future.
     * @deprecated
     */
    static off(eventName, callback, thisArg) {
        this.removeEventListener(eventName, callback, thisArg);
    }
    static innerRemoveEventListener(entries, callback, thisArg) {
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            // If we have a `thisArg`, refine on both `callback` and `thisArg`.
            if (thisArg && (entry.callback !== callback || entry.thisArg !== thisArg)) {
                continue;
            }
            // If we don't have a `thisArg`, refine only on `callback`.
            if (callback && entry.callback !== callback) {
                continue;
            }
            // If we have neither `thisArg` nor `callback`, just remove all events
            // of this type regardless.
            entry._isRemoved = true;
            entries.splice(i, 1);
            i--;
        }
    }
    /**
     * Please avoid using the static event-handling APIs as they will be removed
     * in future.
     * @deprecated
     */
    static removeEventListener(eventName, callback, thisArg) {
        thisArg = thisArg || undefined;
        if (typeof eventName !== 'string') {
            throw new TypeError('Event name must be a string.');
        }
        if (callback && typeof callback !== 'function') {
            throw new TypeError('Callback, if provided, must be function.');
        }
        const eventClass = this.name === 'Observable' ? '*' : this.name;
        const entries = _globalEventHandlers?.[eventClass]?.[eventName];
        if (!entries) {
            return;
        }
        const countBeforeRemoval = entries.length;
        Observable.innerRemoveEventListener(entries, callback, thisArg);
        _globalEventHandlersCount -= countBeforeRemoval - entries.length;
        if (!entries.length) {
            // Clear all entries of this type
            delete _globalEventHandlers[eventClass][eventName];
        }
        // Clear the primary class grouping if no list are left
        const keys = Object.keys(_globalEventHandlers[eventClass]);
        if (keys.length === 0) {
            delete _globalEventHandlers[eventClass];
        }
    }
    /**
     * Please avoid using the static event-handling APIs as they will be removed
     * in future.
     * @deprecated
     */
    static addEventListener(eventName, callback, thisArg, once) {
        once = once || undefined;
        thisArg = thisArg || undefined;
        if (typeof eventName !== 'string') {
            throw new TypeError('Event name must be a string.');
        }
        if (typeof callback !== 'function') {
            throw new TypeError('Callback must be a function.');
        }
        const eventClass = this.name === 'Observable' ? '*' : this.name;
        if (!_globalEventHandlers[eventClass]) {
            _globalEventHandlers[eventClass] = {};
        }
        if (!_globalEventHandlers[eventClass][eventName]) {
            _globalEventHandlers[eventClass][eventName] = [];
        }
        if (Observable._indexOfListener(_globalEventHandlers[eventClass][eventName], callback, thisArg) !== -1) {
            // Already added.
            return;
        }
        _globalEventHandlers[eventClass][eventName].push({ callback, thisArg, once });
        _globalEventHandlersCount++;
    }
    _globalNotify(eventClass, eventType, data) {
        // Check for the Global handlers for JUST this class
        if (_globalEventHandlers[eventClass]) {
            const eventName = data.eventName + eventType;
            const entries = _globalEventHandlers[eventClass][eventName];
            if (entries) {
                Observable._fireEvent(entries, data);
            }
        }
        // Check for the Global handlers for ALL classes
        if (_globalEventHandlers['*']) {
            const eventName = data.eventName + eventType;
            const entries = _globalEventHandlers['*'][eventName];
            if (entries) {
                Observable._fireEvent(entries, data);
            }
        }
    }
    /**
     * Notify this Observable instance with some data. This causes all event
     * handlers on the Observable instance to be called, as well as any 'global'
     * event handlers set on the instance's class.
     *
     * @param data an object that satisfies the EventData interface, though with
     * an optional 'object' property. If left undefined, the 'object' property
     * will implicitly be set as this Observable instance.
     */
    notify(data) {
        data.object = data.object || this;
        const dataWithObject = data;
        // Fast path: no listeners registered through the deprecated static
        // event-handling APIs, so only instance observers need to be notified.
        if (_globalEventHandlersCount === 0) {
            const observers = this._observers[data.eventName];
            if (observers) {
                Observable._fireEvent(observers, dataWithObject);
            }
            return;
        }
        const eventClass = this.constructor.name;
        this._globalNotify(eventClass, 'First', dataWithObject);
        const observers = this._observers[data.eventName];
        if (observers) {
            Observable._fireEvent(observers, dataWithObject);
        }
        this._globalNotify(eventClass, '', dataWithObject);
    }
    static _fireEvent(observers, data) {
        const length = observers.length;
        if (!length) {
            return;
        }
        if (length === 1) {
            this._handleListenerEntry(observers[0], observers, data);
        }
        else {
            // This keeps a copy of observers list to ensure concurrency
            const observersCp = observers.slice();
            for (let i = 0; i < length; i++) {
                const entry = observersCp[i];
                this._handleListenerEntry(entry, observers, data);
            }
        }
    }
    static _handleListenerEntry(entry, observers, data) {
        if (!entry || entry._isRemoved) {
            return;
        }
        if (entry.once) {
            entry._isRemoved = true;
            const index = observers.indexOf(entry);
            if (index !== -1) {
                observers.splice(index, 1);
            }
        }
        const returnValue = entry.thisArg ? entry.callback.call(entry.thisArg, data) : entry.callback(data);
        // This ensures errors thrown inside asynchronous functions do not get swallowed
        if (returnValue instanceof Promise) {
            returnValue.catch((err) => {
                console.error(err);
            });
        }
    }
    /**
     * Notifies all the registered listeners for the property change event.
     */
    notifyPropertyChange(name, value, oldValue) {
        this.notify(this._createPropertyChangeData(name, value, oldValue));
    }
    /**
     * Checks whether a listener is registered for the specified event name.
     * @param eventName The name of the event to check for.
     */
    hasListeners(eventName) {
        return this._observers[eventName] !== undefined;
    }
    /**
     * This method is intended to be overriden by inheritors to provide additional implementation.
     */
    _createPropertyChangeData(propertyName, value, oldValue) {
        return {
            eventName: Observable.propertyChangeEvent,
            object: this,
            propertyName,
            value,
            oldValue,
        };
    }
    _emit(eventName) {
        this.notify({ eventName, object: this });
    }
    _getEventList(eventName, createIfNeeded) {
        if (!eventName) {
            throw new TypeError('eventName must be a valid string.');
        }
        let list = this._observers[eventName];
        if (!list && createIfNeeded) {
            list = [];
            this._observers[eventName] = list;
        }
        return list;
    }
    static _indexOfListener(list, callback, thisArg) {
        thisArg = thisArg || undefined;
        for (let i = 0, length = list.length; i < length; i++) {
            const entry = list[i];
            if (entry.callback === callback && entry.thisArg === thisArg) {
                return i;
            }
        }
        return -1;
    }
}
/**
 * String value used when hooking to propertyChange event.
 * @nsEvent  {PropertyChangeData} propertyChange
 */
Observable.propertyChangeEvent = 'propertyChange';
class ObservableFromObject extends Observable {
    constructor() {
        super(...arguments);
        this._map = {};
    }
    get(name) {
        return this._map[name];
    }
    /**
     * Updates the specified property with the provided value.
     */
    set(name, value) {
        const currentValue = this._map[name];
        if (currentValue === value) {
            return;
        }
        const newValue = WrappedValue.unwrap(value);
        this._map[name] = newValue;
        this.notifyPropertyChange(name, newValue, currentValue);
    }
}
function defineNewProperty(target, propertyName) {
    Object.defineProperty(target, propertyName, {
        get: function () {
            return target._map[propertyName];
        },
        set: function (value) {
            target.set(propertyName, value);
        },
        enumerable: true,
        configurable: true,
    });
}
function addPropertiesFromObject(observable, source, recursive = false) {
    Object.keys(source).forEach((prop) => {
        let value = source[prop];
        if (recursive && !Array.isArray(value) && value && typeof value === 'object' && !(value instanceof Observable)) {
            value = fromObjectRecursive(value);
        }
        defineNewProperty(observable, prop);
        observable.set(prop, value);
    });
}
/**
 * Creates an Observable instance and sets its properties according to the supplied JavaScript object.
 * param obj - A JavaScript object used to initialize nativescript Observable instance.
 */
export function fromObject(source) {
    const observable = new ObservableFromObject();
    addPropertiesFromObject(observable, source, false);
    return observable;
}
/**
 * Creates an Observable instance and sets its properties according to the supplied JavaScript object.
 * This function will create new Observable for each nested object (expect arrays and functions) from supplied JavaScript object.
 * param obj - A JavaScript object used to initialize nativescript Observable instance.
 */
export function fromObjectRecursive(source) {
    const observable = new ObservableFromObject();
    addPropertiesFromObject(observable, source, true);
    return observable;
}
//# sourceMappingURL=index.js.map