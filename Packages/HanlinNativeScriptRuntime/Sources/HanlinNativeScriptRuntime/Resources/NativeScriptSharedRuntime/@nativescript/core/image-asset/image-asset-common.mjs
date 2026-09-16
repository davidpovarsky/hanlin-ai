import { Observable } from '../data/observable';
import { Screen } from '../platform';
export class ImageAssetBase extends Observable {
    constructor() {
        super();
        this._options = { keepAspectRatio: true, autoScaleFactor: true };
    }
    get options() {
        return this._options;
    }
    set options(value) {
        this._options = normalizeImageAssetOptions(value);
    }
    get nativeImage() {
        return this._nativeImage;
    }
    set nativeImage(value) {
        this._nativeImage = value;
    }
    getImageAsync(callback) {
        //
    }
}
function toPositiveInt(value) {
    if (value == null) {
        return 0;
    }
    if (typeof value === 'number') {
        return value > 0 ? Math.floor(value) : 0;
    }
    if (typeof value === 'string') {
        const parsed = parseInt(value, 10);
        return isNaN(parsed) || parsed <= 0 ? 0 : parsed;
    }
    return 0;
}
function normalizeImageAssetOptions(options) {
    const normalized = options ? { ...options } : {};
    // Coerce potential string values to positive integers; fallback to 0
    // to trigger default sizing downstream
    normalized.width = toPositiveInt(options?.width);
    normalized.height = toPositiveInt(options?.height);
    if (typeof normalized.keepAspectRatio !== 'boolean') {
        normalized.keepAspectRatio = true;
    }
    if (typeof normalized.autoScaleFactor !== 'boolean') {
        normalized.autoScaleFactor = true;
    }
    return normalized;
}
export function getAspectSafeDimensions(sourceWidth, sourceHeight, reqWidth, reqHeight) {
    const widthCoef = sourceWidth / reqWidth;
    const heightCoef = sourceHeight / reqHeight;
    const aspectCoef = Math.min(widthCoef, heightCoef);
    return {
        width: Math.floor(sourceWidth / aspectCoef),
        height: Math.floor(sourceHeight / aspectCoef),
    };
}
export function getRequestedImageSize(src, options) {
    const normalized = normalizeImageAssetOptions(options);
    let reqWidth = normalized.width || Math.min(src.width, Screen.mainScreen.widthPixels);
    let reqHeight = normalized.height || Math.min(src.height, Screen.mainScreen.heightPixels);
    if (options && options.keepAspectRatio) {
        const safeAspectSize = getAspectSafeDimensions(src.width, src.height, reqWidth, reqHeight);
        reqWidth = safeAspectSize.width;
        reqHeight = safeAspectSize.height;
    }
    return {
        width: reqWidth,
        height: reqHeight,
    };
}
//# sourceMappingURL=image-asset-common.js.map