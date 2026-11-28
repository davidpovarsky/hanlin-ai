import { Observable } from '../data/observable';
import { Screen } from '../platform/screen';
import { getApplicationProperties, toggleApplicationEventListeners } from '../application/helpers-common';
import { matchQuery, MediaQueryType } from '../css-mediaquery';
import { Trace } from '../trace';
const mediaQueryLists = [];
// In browser, developers cannot create MediaQueryList instances without calling matchMedia
let isMediaInitializationEnabled = false;
function onDeviceChange(args) {
    for (const mql of mediaQueryLists) {
        const matches = checkIfMediaQueryMatches(mql.media);
        if (mql.matches !== matches) {
            mql._matches = matches;
            mql.notify({
                eventName: MediaQueryListImpl.changeEvent,
                object: mql,
                matches: mql.matches,
                media: mql.media,
            });
        }
    }
}
function checkIfMediaQueryMatches(mediaQueryString) {
    const { widthPixels, heightPixels } = Screen.mainScreen;
    let matches;
    try {
        const appProperties = getApplicationProperties();
        matches = matchQuery(mediaQueryString, {
            type: MediaQueryType.screen,
            width: widthPixels,
            height: heightPixels,
            'device-width': widthPixels,
            'device-height': heightPixels,
            orientation: appProperties.orientation,
            'prefers-color-scheme': appProperties.systemAppearance,
        });
    }
    catch (err) {
        matches = false;
        Trace.write(err, Trace.categories.MediaQuery, Trace.messageType.error);
    }
    return matches;
}
function matchMedia(mediaQueryString) {
    isMediaInitializationEnabled = true;
    const mediaQueryList = new MediaQueryListImpl();
    isMediaInitializationEnabled = false;
    mediaQueryList._media = mediaQueryString;
    mediaQueryList._matches = checkIfMediaQueryMatches(mediaQueryString);
    return mediaQueryList;
}
class MediaQueryListImpl extends Observable {
    constructor() {
        super();
        if (!isMediaInitializationEnabled) {
            throw new TypeError('Illegal constructor');
        }
        Object.defineProperties(this, {
            _media: {
                writable: true,
            },
            _matches: {
                writable: true,
            },
            _onChange: {
                writable: true,
                value: null,
            },
            mediaQueryChangeListeners: {
                value: new Map(),
            },
            _throwInvocationError: {
                value: null,
            },
        });
    }
    get media() {
        this._throwInvocationError?.();
        return this._media;
    }
    get matches() {
        this._throwInvocationError?.();
        return this._matches;
    }
    // @ts-ignore
    addEventListener(eventName, callback, thisArg, once) {
        this._throwInvocationError?.();
        const hasChangeListeners = this.hasListeners(MediaQueryListImpl.changeEvent);
        // Call super method first since it throws in the case of bad parameters
        super.addEventListener(eventName, callback, thisArg, once);
        if (eventName === MediaQueryListImpl.changeEvent && !hasChangeListeners) {
            mediaQueryLists.push(this);
            if (mediaQueryLists.length === 1) {
                toggleApplicationEventListeners(true, onDeviceChange);
            }
        }
    }
    // @ts-ignore
    removeEventListener(eventName, callback, thisArg) {
        this._throwInvocationError?.();
        // Call super method first since it throws in the case of bad parameters
        super.removeEventListener(eventName, callback, thisArg);
        if (eventName === MediaQueryListImpl.changeEvent) {
            const hasChangeListeners = this.hasListeners(MediaQueryListImpl.changeEvent);
            if (!hasChangeListeners) {
                const index = mediaQueryLists.indexOf(this);
                if (index >= 0) {
                    mediaQueryLists.splice(index, 1);
                    if (!mediaQueryLists.length) {
                        toggleApplicationEventListeners(false, onDeviceChange);
                    }
                }
            }
        }
    }
    addListener(callback) {
        this._throwInvocationError?.();
        // This kind of implementation helps maintain listener registration order
        // regardless of using the deprecated methods or property onchange
        const wrapperCallback = (data) => {
            callback.call(this, {
                matches: this.matches,
                media: this.media,
            });
        };
        // Call this method first since it throws in the case of bad parameters
        this.addEventListener(MediaQueryListImpl.changeEvent, wrapperCallback);
        this.mediaQueryChangeListeners.set(callback, wrapperCallback);
    }
    removeListener(callback) {
        this._throwInvocationError?.();
        if (this.mediaQueryChangeListeners.has(callback)) {
            // Call this method first since it throws in the case of bad parameters
            this.removeEventListener(MediaQueryListImpl.changeEvent, this.mediaQueryChangeListeners.get(callback));
            this.mediaQueryChangeListeners.delete(callback);
        }
    }
    get onchange() {
        this._throwInvocationError?.();
        return this._onChange;
    }
    set onchange(callback) {
        this._throwInvocationError?.();
        // Remove old listener if any
        if (this._onChange) {
            this.removeListener(this._onChange);
        }
        if (callback) {
            this.addListener(callback);
        }
        this._onChange = callback;
    }
    _throwInvocationError() {
        throw new TypeError('Illegal invocation');
    }
}
MediaQueryListImpl.changeEvent = 'change';
export { matchMedia, MediaQueryListImpl as MediaQueryList, checkIfMediaQueryMatches };
//# sourceMappingURL=index.js.map