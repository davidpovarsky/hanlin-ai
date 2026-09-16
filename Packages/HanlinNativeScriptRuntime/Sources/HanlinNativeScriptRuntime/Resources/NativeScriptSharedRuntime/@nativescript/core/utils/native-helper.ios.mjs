import { platformCheck } from './platform-check';
import { getClass, isNullOrUndefined, numberHasDecimals, numberIs64Bit } from './types';
import { Color } from '../color';
import { Trace } from '../trace';
import { CORE_ANIMATION_DEFAULTS, getDurationWithDampingFromSpring } from './animation-helpers';
import { SDK_VERSION } from './constants';
export function dataDeserialize(nativeData) {
    if (isNullOrUndefined(nativeData)) {
        // some native values will already be js null values
        // calling types.getClass below on null/undefined will cause crash
        return null;
    }
    else {
        switch (getClass(nativeData)) {
            case 'NSNull':
                return null;
            case 'NSMutableDictionary':
            case 'NSDictionary': {
                const obj = {};
                const length = nativeData.count;
                const keysArray = nativeData.allKeys;
                for (let i = 0; i < length; i++) {
                    const nativeKey = keysArray.objectAtIndex(i);
                    obj[nativeKey] = dataDeserialize(nativeData.objectForKey(nativeKey));
                }
                return obj;
            }
            case 'NSMutableArray':
            case 'NSArray': {
                const array = [];
                const len = nativeData.count;
                for (let i = 0; i < len; i++) {
                    array[i] = dataDeserialize(nativeData.objectAtIndex(i));
                }
                return array;
            }
            default:
                return nativeData;
        }
    }
}
export function dataSerialize(data, wrapPrimitives = false) {
    switch (typeof data) {
        case 'string':
        case 'boolean': {
            return data;
        }
        case 'number': {
            const hasDecimals = numberHasDecimals(data);
            if (numberIs64Bit(data)) {
                if (hasDecimals) {
                    return NSNumber.alloc().initWithDouble(data);
                }
                else {
                    return NSNumber.alloc().initWithLongLong(data);
                }
            }
            else {
                if (hasDecimals) {
                    return NSNumber.alloc().initWithFloat(data);
                }
                else {
                    return data;
                }
            }
        }
        case 'object': {
            if (data instanceof Date) {
                return NSDate.dateWithTimeIntervalSince1970(data.getTime() / 1000);
            }
            if (!data) {
                return null;
            }
            if (Array.isArray(data)) {
                return NSArray.arrayWithArray(data.map((el) => dataSerialize(el, wrapPrimitives)).filter((el) => el !== null));
            }
            const node = Object.fromEntries(Object.entries(data)
                .map(([key, value]) => [key, dataSerialize(value, wrapPrimitives)])
                .filter(([, value]) => value !== null));
            // cast to any avoids signature overload on tsc build
            return NSDictionary.dictionaryWithDictionary(node);
        }
        default:
            return null;
    }
}
function getCurrentAppPath() {
    if (!global.__dirname) {
        global.__dirname = typeof __dirname !== 'undefined' ? __dirname : import.meta.dirname;
    }
    const currentDir = global.__dirname;
    const tnsModulesIndex = currentDir.indexOf('/tns_modules');
    // Module not hosted in ~/tns_modules when bundled. Use current dir.
    let appPath = currentDir;
    if (tnsModulesIndex !== -1) {
        // Strip part after tns_modules to obtain app root
        appPath = currentDir.substring(0, tnsModulesIndex);
    }
    return appPath;
}
function joinPaths(...paths) {
    if (!paths || paths.length === 0) {
        return '';
    }
    return NSString.stringWithString(NSString.pathWithComponents(paths)).stringByStandardizingPath;
}
const radToDeg = Math.PI / 180;
function isOrientationLandscape(orientation) {
    return orientation === 3 /* UIDeviceOrientation.LandscapeLeft */ /* 3 */ || orientation === 4 /* UIDeviceOrientation.LandscapeRight */ /* 4 */;
}
function openFileAtRootModule(filePath) {
    try {
        const appPath = getCurrentAppPath();
        const path = isRealDevice() ? filePath.replace('~', appPath) : filePath;
        const controller = UIDocumentInteractionController.interactionControllerWithURL(NSURL.fileURLWithPath(path));
        controller.delegate = createUIDocumentInteractionControllerDelegate();
        return controller.presentPreviewAnimated(true);
    }
    catch (e) {
        Trace.write('Error in openFile', Trace.categories.Error, Trace.messageType.error);
    }
    return false;
}
// TODO: remove for NativeScript 9.0
export function getter(_this, property) {
    console.log('utils.ios.getter() is deprecated; use the respective native property instead');
    if (typeof property === 'function') {
        return property.call(_this);
    }
    else {
        return property;
    }
}
var collections;
(function (collections) {
    function jsArrayToNSArray(str) {
        return NSArray.arrayWithArray(str);
    }
    collections.jsArrayToNSArray = jsArrayToNSArray;
    function nsArrayToJSArray(a) {
        const arr = [];
        if (a !== undefined) {
            const count = a.count;
            for (let i = 0; i < count; i++) {
                arr.push(a.objectAtIndex(i));
            }
        }
        return arr;
    }
    collections.nsArrayToJSArray = nsArrayToJSArray;
})(collections || (collections = {}));
function getRootViewController() {
    const win = getWindow();
    let vc = win && win.rootViewController;
    while (vc && vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}
export function getWindow() {
    let window;
    if (SDK_VERSION >= 15 && typeof NativeScriptViewFactory !== 'undefined') {
        // UIWindowScene.keyWindow is only available 15+
        window = NativeScriptViewFactory.getKeyWindow();
    }
    if (window) {
        return window;
    }
    const app = UIApplication.sharedApplication;
    if (!app) {
        return;
    }
    return app.keyWindow || (app.windows && app.windows.count > 0 && app.windows.objectAtIndex(0));
}
function getMainScreen() {
    const window = getWindow();
    return window ? window.screen : UIScreen.mainScreen;
}
function setWindowBackgroundColor(value) {
    const win = getWindow();
    if (win) {
        const bgColor = new Color(value);
        win.backgroundColor = bgColor.ios;
        const rootVc = getRootViewController();
        if (rootVc?.view) {
            rootVc.view.backgroundColor = bgColor.ios;
        }
    }
}
function isLandscape() {
    console.log('utils.ios.isLandscape() is deprecated; use application.orientation instead');
    const deviceOrientation = UIDevice.currentDevice.orientation;
    const statusBarOrientation = UIApplication.sharedApplication.statusBarOrientation;
    const isDeviceOrientationLandscape = isOrientationLandscape(deviceOrientation);
    const isStatusBarOrientationLandscape = isOrientationLandscape(statusBarOrientation);
    return isDeviceOrientationLandscape || isStatusBarOrientationLandscape;
}
/**
 * @deprecated use Utils.SDK_VERSION instead which is a float of the {major}.{minor} verison
 */
const MajorVersion = NSString.stringWithString(UIDevice.currentDevice.systemVersion).intValue;
export function openFile(filePath) {
    console.log('utils.ios.openFile() is deprecated; use utils.openFile() instead');
    return openFileAtRootModule(filePath);
}
function getVisibleViewController(rootViewController) {
    let viewController = rootViewController;
    while (viewController && viewController.presentedViewController) {
        viewController = viewController.presentedViewController;
    }
    return viewController;
}
function applyRotateTransform(transform, x, y, z) {
    if (x) {
        transform = CATransform3DRotate(transform, x * radToDeg, 1, 0, 0);
    }
    if (y) {
        transform = CATransform3DRotate(transform, y * radToDeg, 0, 1, 0);
    }
    if (z) {
        transform = CATransform3DRotate(transform, z * radToDeg, 0, 0, 1);
    }
    return transform;
}
function createUIDocumentInteractionControllerDelegate() {
    var UIDocumentInteractionControllerDelegateImpl = (function (_super) {
        __extends(UIDocumentInteractionControllerDelegateImpl, _super);
        function UIDocumentInteractionControllerDelegateImpl() {
            return _super !== null && _super.apply(this, arguments) || this;
        }
        UIDocumentInteractionControllerDelegateImpl.prototype.getViewController = function () {
            return getWindow().rootViewController;
        };
        UIDocumentInteractionControllerDelegateImpl.prototype.documentInteractionControllerViewControllerForPreview = function (controller) {
            return this.getViewController();
        };
        UIDocumentInteractionControllerDelegateImpl.prototype.documentInteractionControllerViewForPreview = function (controller) {
            return this.getViewController().view;
        };
        UIDocumentInteractionControllerDelegateImpl.prototype.documentInteractionControllerRectForPreview = function (controller) {
            return this.getViewController().view.frame;
        };
        UIDocumentInteractionControllerDelegateImpl.ObjCProtocols = [UIDocumentInteractionControllerDelegate];
        return UIDocumentInteractionControllerDelegateImpl;
    }(NSObject));
    return new UIDocumentInteractionControllerDelegateImpl();
}
export function isRealDevice() {
    try {
        if (NSProcessInfo.processInfo.environment.valueForKey('SIMULATOR_DEVICE_NAME')) {
            return false;
        }
        return true;
    }
    catch (e) {
        return true;
    }
}
function printCGRect(rect) {
    if (rect) {
        return `CGRect(${rect.origin.x} ${rect.origin.y} ${rect.size.width} ${rect.size.height})`;
    }
}
function snapshotView(view, scale) {
    if (view instanceof UIImageView) {
        return view.image;
    }
    // console.log('snapshotView view.frame:', printRect(view.frame));
    const originalOpacity = view.layer.opacity;
    const needsBump = originalOpacity <= 0;
    if (needsBump) {
        // Wrap in a CATransaction with actions disabled so the implicit `opacity`
        // animation isn't kicked off when we temporarily restore visibility for
        // the render. Restoring synchronously (instead of via setTimeout) avoids a
        // race where the deferred restore would clobber a caller's later opacity
        // change — most importantly the shared-transition cleanup that needs the
        // final opacity to stick after the snapshot is taken.
        CATransaction.begin();
        CATransaction.setDisableActions(true);
        view.layer.opacity = 1;
    }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(view.frame.size.width, view.frame.size.height), false, scale);
    view.layer.renderInContext(UIGraphicsGetCurrentContext());
    const image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (needsBump) {
        view.layer.opacity = originalOpacity;
        CATransaction.commit();
    }
    return image;
}
function copyLayerProperties(view, toView, customProperties) {
    const viewPropertiesToMatch = customProperties?.view || ['backgroundColor'];
    const layerPropertiesToMatch = customProperties?.layer || ['cornerRadius', 'borderWidth', 'borderColor'];
    viewPropertiesToMatch.forEach((property) => {
        if (view[property] !== toView[property]) {
            // console.log('|    -- matching view property:', property);
            view[property] = toView[property];
        }
    });
    layerPropertiesToMatch.forEach((property) => {
        if (view.layer[property] !== toView.layer[property]) {
            // console.log('|    -- matching layer property:', property);
            view.layer[property] = toView.layer[property];
        }
    });
}
function animateWithSpring(options) {
    // for convenience, default spring settings are provided
    const opt = {
        ...CORE_ANIMATION_DEFAULTS.spring,
        delay: 0,
        animateOptions: null,
        animations: null,
        completion: null,
        ...(options || {}),
    };
    const { duration, damping } = getDurationWithDampingFromSpring(opt);
    if (duration === 0) {
        UIView.animateWithDurationAnimationsCompletion(0, opt.animations, opt.completion);
        return;
    }
    UIView.animateWithDurationDelayUsingSpringWithDampingInitialSpringVelocityOptionsAnimationsCompletion(duration, opt.delay, damping, opt.velocity, opt.animateOptions, opt.animations, opt.completion);
}
// these don't exist on iOS. Stub them to empty functions.
export const ad = platformCheck('Utils.ad');
export const android = platformCheck('Utils.android');
export const ios = {
    collections,
    createUIDocumentInteractionControllerDelegate,
    getCurrentAppPath,
    getRootViewController,
    getVisibleViewController,
    getWindow,
    getMainScreen,
    setWindowBackgroundColor,
    isLandscape,
    applyRotateTransform,
    snapshotView,
    joinPaths,
    printCGRect,
    copyLayerProperties,
    animateWithSpring,
    MajorVersion,
};
/**
 * @deprecated Use `Utils.ios` instead.
 */
export const iOSNativeHelper = ios;
//# sourceMappingURL=native-helper.ios.js.map