import { request as httpRequest } from '../../http/http-request';
import * as common from './image-cache-common';
import { Trace } from '../../trace';
import { GC } from '../../utils';
var MemoryWarningHandler = (function (_super) {
    __extends(MemoryWarningHandler, _super);
    function MemoryWarningHandler() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    MemoryWarningHandler.new = function () {
        return _super.new.call(this);
    };
    MemoryWarningHandler.prototype.initWithCache = function (cache) {
        this._cache = cache;
        NSNotificationCenter.defaultCenter.addObserverSelectorNameObject(this, "clearCache", "UIApplicationDidReceiveMemoryWarningNotification", null);
        if (Trace.isEnabled()) {
            Trace.write("[MemoryWarningHandler] Added low memory observer.", Trace.categories.Debug);
        }
        return this;
    };
    MemoryWarningHandler.prototype.dealloc = function () {
        NSNotificationCenter.defaultCenter.removeObserverNameObject(this, "UIApplicationDidReceiveMemoryWarningNotification", null);
        if (Trace.isEnabled()) {
            Trace.write("[MemoryWarningHandler] Removed low memory observer.", Trace.categories.Debug);
        }
        _super.prototype.dealloc.call(this);
    };
    MemoryWarningHandler.prototype.clearCache = function () {
        if (Trace.isEnabled()) {
            Trace.write("[MemoryWarningHandler] Clearing Image Cache.", Trace.categories.Debug);
        }
        this._cache.removeAllObjects();
        GC();
    };
    MemoryWarningHandler.ObjCExposedMethods = {
        clearCache: { returns: interop.types.void, params: [] },
    };
    return MemoryWarningHandler;
}(NSObject));
export class Cache extends common.Cache {
    constructor() {
        super();
        this._cache = new NSCache();
        this._memoryWarningHandler = MemoryWarningHandler.new().initWithCache(this._cache);
    }
    _downloadCore(request) {
        httpRequest({ url: request.url, method: 'GET' }).then((response) => {
            try {
                const image = UIImage.alloc().initWithData(response.content.raw);
                if (image) {
                    this._onDownloadCompleted(request.key, image);
                }
                else {
                    this._onDownloadError(request.key, new Error('No result for provided url'));
                }
            }
            catch (err) {
                this._onDownloadError(request.key, err);
            }
        }, (err) => {
            this._onDownloadError(request.key, err);
        });
    }
    get(key) {
        return this._cache.objectForKey(key);
    }
    set(key, image) {
        this._cache.setObjectForKey(image, key);
    }
    remove(key) {
        this._cache.removeObjectForKey(key);
    }
    clear() {
        this._cache.removeAllObjects();
        GC();
    }
}
//# sourceMappingURL=index.ios.js.map