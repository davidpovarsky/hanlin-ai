import { IOSHelper } from '../ui/core/view/view-helper';
import { SDK_VERSION } from '../utils/constants';
import { CoreTypes } from '../core-types';
import { Trace } from '../trace';
import { NativeWindow } from './native-window-common';
/**
 * iOS implementation of NativeWindow.
 * Wraps a UIWindow and, when the app is scene-based, the UIWindowScene hosting it.
 */
export class IOSNativeWindow extends NativeWindow {
    constructor(scene, window, id, isPrimary = false, role = 'application') {
        super(id, isPrimary, role);
        /**
         * @internal – set while a scene session destruction request is in flight, so the
         * following scene disconnect is read as a close rather than a detach.
         */
        this._closeRequested = false;
        this._hasSessionIdentity = !!id;
        this._scene = scene;
        this._window = window;
    }
    /**
     * @internal – bind a new scene/window pair to this window session after a detach.
     */
    _reattach(scene, uiWindow) {
        this._scene = scene;
        this._window = uiWindow;
        this._setState('attached');
    }
    get ios() {
        return {
            scene: this._scene,
            uiWindow: this._window,
        };
    }
    /**
     * Platform-specific: set the view as root content of this UIWindow.
     */
    _setNativeContent(view) {
        const controller = this._getViewController(view);
        this._setViewControllerView(view);
        if (this.role === 'embedded') {
            // The host app owns this UIWindow: its rootViewController and key/visible state
            // are not ours to change, so the content is handed over as a view controller.
            NativeScriptEmbedder.sharedInstance().delegate?.presentNativeScriptApp(controller);
        }
        else {
            const haveController = this._window.rootViewController !== null;
            this._window.rootViewController = controller;
            if (!haveController) {
                this._window.makeKeyAndVisible();
            }
        }
        // Listen for trait collection changes per-window
        view.on(IOSHelper.traitCollectionColorAppearanceChangedEvent, () => {
            const userInterfaceStyle = controller.traitCollection.userInterfaceStyle;
            this._setSystemAppearance(this._getSystemAppearanceValue(userInterfaceStyle));
        });
        view.on(IOSHelper.traitCollectionLayoutDirectionChangedEvent, () => {
            const layoutDirection = controller.traitCollection.layoutDirection;
            this._setLayoutDirection(this._getLayoutDirectionValue(layoutDirection));
        });
    }
    /**
     * Close this window/scene.
     */
    close() {
        if (this.isPrimary) {
            console.log('NativeWindow: Cannot close the primary window.');
            return;
        }
        const session = this._scene?.session;
        if (!session) {
            console.log('NativeWindow: Scene has no session to destroy.');
            return;
        }
        const app = UIApplication.sharedApplication;
        if (app.requestSceneSessionDestructionOptionsErrorHandler) {
            this._closeRequested = true;
            app.requestSceneSessionDestructionOptionsErrorHandler(session, null, (error) => {
                if (error) {
                    this._closeRequested = false;
                    console.log('NativeWindow: Error destroying scene session:', error.localizedDescription);
                }
            });
        }
        else {
            console.log('NativeWindow: Scene destruction API not available on this iOS version.');
        }
    }
    // --- Platform getters ---
    _getOrientation() {
        if (__VISIONOS__) {
            return this._getOrientationValue(NativeScriptEmbedder.sharedInstance().windowScene?.interfaceOrientation);
        }
        if (this._scene) {
            return this._getOrientationValue(this._scene.interfaceOrientation);
        }
        return this._getOrientationValue(UIApplication.sharedApplication.statusBarOrientation);
    }
    _getSystemAppearance() {
        if (!__VISIONOS__ && SDK_VERSION <= 11) {
            return null;
        }
        const rootVC = this._window?.rootViewController;
        if (!rootVC) {
            return null;
        }
        return this._getSystemAppearanceValue(rootVC.traitCollection.userInterfaceStyle);
    }
    _getLayoutDirection() {
        const rootVC = this._window?.rootViewController;
        if (!rootVC) {
            return null;
        }
        return this._getLayoutDirectionValue(rootVC.traitCollection.layoutDirection);
    }
    // --- Value converters ---
    _getOrientationValue(orientation) {
        switch (orientation) {
            case 3 /* UIInterfaceOrientation.LandscapeRight */:
            case 4 /* UIInterfaceOrientation.LandscapeLeft */:
                return 'landscape';
            case 2 /* UIInterfaceOrientation.PortraitUpsideDown */:
            case 1 /* UIInterfaceOrientation.Portrait */:
                return 'portrait';
            case 0 /* UIInterfaceOrientation.Unknown */:
            default:
                return 'unknown';
        }
    }
    _getSystemAppearanceValue(userInterfaceStyle) {
        switch (userInterfaceStyle) {
            case 2 /* UIUserInterfaceStyle.Dark */:
                return 'dark';
            case 1 /* UIUserInterfaceStyle.Light */:
            case 0 /* UIUserInterfaceStyle.Unspecified */:
            default:
                return 'light';
        }
    }
    _getLayoutDirectionValue(layoutDirection) {
        switch (layoutDirection) {
            case 1 /* UITraitEnvironmentLayoutDirection.RightToLeft */:
                return CoreTypes.LayoutDirection.rtl;
            case 0 /* UITraitEnvironmentLayoutDirection.LeftToRight */:
            default:
                return CoreTypes.LayoutDirection.ltr;
        }
    }
    // --- ViewController helpers ---
    _getViewController(rootView) {
        let viewController = rootView.viewController || rootView.ios;
        if (!(viewController instanceof UIViewController)) {
            viewController = IOSHelper.UILayoutViewController.initWithOwner(new WeakRef(rootView));
            rootView.viewController = viewController;
        }
        return viewController;
    }
    _setViewControllerView(view) {
        const viewController = view.viewController || view.ios;
        const nativeView = view.ios || view.nativeViewProtected;
        if (!nativeView || !viewController) {
            throw new Error('Root should be either UIViewController or UIView');
        }
        if (viewController instanceof IOSHelper.UILayoutViewController) {
            viewController.view.addSubview(nativeView);
        }
    }
    _onReleaseRootView(rootView) {
        rootView.off(IOSHelper.traitCollectionColorAppearanceChangedEvent);
        rootView.off(IOSHelper.traitCollectionLayoutDirectionChangedEvent);
        // An embedded window belongs to the host app, so its rootViewController is not ours
        // to clear — `_setNativeContent` never set it in the first place.
        if (this.role !== 'embedded' && this._window?.rootViewController) {
            // The controller's view is moving into another window's hierarchy; leaving it
            // installed here has UIKit holding a controller it no longer hosts.
            this._window.rootViewController = null;
        }
    }
    _onDestroy() {
        // The trait collection listeners live on the root view, so they have to go
        // before the base drops the reference to it.
        if (this._rootView) {
            this._rootView.off(IOSHelper.traitCollectionColorAppearanceChangedEvent);
            this._rootView.off(IOSHelper.traitCollectionLayoutDirectionChangedEvent);
        }
        super._onDestroy();
        this._scene = null;
        this._window = null;
    }
    /**
     * The window identity of a scene: the session persistent identifier, which iOS keeps
     * across a disconnect and hands back when it reconnects the same session.
     *
     * Returns `undefined` when the scene carries no session identity — such a window gets
     * a minted id and will not be recognised on reconnect.
     */
    static getSceneId(scene) {
        const persistentIdentifier = scene?.session?.persistentIdentifier;
        if (persistentIdentifier) {
            return `${persistentIdentifier}`;
        }
        Trace.write('NativeWindow: scene has no session persistentIdentifier; window identity will not survive a reconnect.', Trace.categories.NativeLifecycle, Trace.messageType.error);
        return undefined;
    }
}
//# sourceMappingURL=native-window.ios.js.map