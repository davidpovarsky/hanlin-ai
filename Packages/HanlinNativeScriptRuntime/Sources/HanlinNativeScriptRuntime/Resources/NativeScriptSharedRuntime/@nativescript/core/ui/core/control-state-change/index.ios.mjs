var ObserverClass = (function (_super) {
    __extends(ObserverClass, _super);
    function ObserverClass() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    ObserverClass.initWithCallback = function (callback) {
        var observer = ObserverClass.alloc().init();
        observer.callback = callback;
        return observer;
    };
    ObserverClass.prototype.observeValueForKeyPathOfObjectChangeContext = function (path, object) {
        var callback = this.callback;
        if (callback) {
            callback(path, object[path]);
        }
    };
    return ObserverClass;
}(NSObject));
export class ControlStateChangeListener {
    constructor(control, states, callback) {
        this._observing = false;
        this._control = control;
        this._states = states;
        this._observer = ObserverClass.initWithCallback(callback);
    }
    start() {
        if (!this._observing) {
            this._observing = true;
            for (const state of this._states) {
                this._control.addObserverForKeyPathOptionsContext(this._observer, state, 1 /* NSKeyValueObservingOptions.New */, null);
            }
        }
    }
    stop() {
        if (this._observing) {
            for (const state of this._states) {
                this._control.removeObserverForKeyPath(this._observer, state);
            }
            this._observing = false;
        }
    }
}
//# sourceMappingURL=index.ios.js.map