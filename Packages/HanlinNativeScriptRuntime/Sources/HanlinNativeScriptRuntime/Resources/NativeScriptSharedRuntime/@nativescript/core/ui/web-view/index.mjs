import { disableZoomProperty, WebViewBase } from './web-view-common';
import { Trace } from '../../trace';
import { knownFolders } from '../../file-system';
import { booleanConverter } from '../core/view-base';
export * from './web-view-common';
var WKNavigationDelegateImpl = (function (_super) {
    __extends(WKNavigationDelegateImpl, _super);
    function WKNavigationDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    WKNavigationDelegateImpl.initWithOwner = function (owner) {
        var handler = WKNavigationDelegateImpl.new();
        handler._owner = owner;
        return handler;
    };
    WKNavigationDelegateImpl.prototype.webViewDecidePolicyForNavigationActionDecisionHandler = function (webView, navigationAction, decisionHandler) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && navigationAction.request.URL) {
            var navType = "other";
            switch (navigationAction.navigationType) {
                case WKNavigationType.LinkActivated:
                    navType = "linkClicked";
                    break;
                case WKNavigationType.FormSubmitted:
                    navType = "formSubmitted";
                    break;
                case WKNavigationType.BackForward:
                    navType = "backForward";
                    break;
                case WKNavigationType.Reload:
                    navType = "reload";
                    break;
                case WKNavigationType.FormResubmitted:
                    navType = "formResubmitted";
                    break;
            }
            decisionHandler(WKNavigationActionPolicy.Allow);
            if (Trace.isEnabled()) {
                Trace.write("WKNavigationDelegateClass.webViewDecidePolicyForNavigationActionDecisionHandler(" + navigationAction.request.URL.absoluteString + ", " + navigationAction.navigationType + ")", Trace.categories.Debug);
            }
            owner._onLoadStarted(navigationAction.request.URL.absoluteString, navType);
        }
    };
    WKNavigationDelegateImpl.prototype.webViewDidStartProvisionalNavigation = function (webView, navigation) {
        if (Trace.isEnabled()) {
            Trace.write("WKNavigationDelegateClass.webViewDidStartProvisionalNavigation(" + webView.URL + ")", Trace.categories.Debug);
        }
    };
    WKNavigationDelegateImpl.prototype.webViewDidFinishNavigation = function (webView, navigation) {
        var _a;
        if (Trace.isEnabled()) {
            Trace.write("WKNavigationDelegateClass.webViewDidFinishNavigation(" + webView.URL + ")", Trace.categories.Debug);
        }
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var src = owner.src;
            if (webView.URL) {
                src = webView.URL.absoluteString;
            }
            owner._onLoadFinished(src);
        }
    };
    WKNavigationDelegateImpl.prototype.webViewDidFailNavigationWithError = function (webView, navigation, error) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var src = owner.src;
            if (webView.URL) {
                src = webView.URL.absoluteString;
            }
            if (Trace.isEnabled()) {
                Trace.write("WKNavigationDelegateClass.webViewDidFailNavigationWithError(" + error.localizedDescription + ")", Trace.categories.Debug);
            }
            owner._onLoadFinished(src, error.localizedDescription);
        }
    };
    WKNavigationDelegateImpl.prototype.webViewDidFailProvisionalNavigationWithError = function (webView, navigation, error) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner) {
            var src = owner.src;
            if (webView.URL) {
                src = webView.URL.absoluteString;
            }
            if (Trace.isEnabled()) {
                Trace.write("WKNavigationDelegateClass.webViewDidFailProvisionalNavigationWithError(" + error.localizedDescription + ")", Trace.categories.Debug);
            }
            owner._onLoadFinished(src, error.localizedDescription);
        }
    };
    WKNavigationDelegateImpl.ObjCProtocols = [WKNavigationDelegate];
    return WKNavigationDelegateImpl;
}(NSObject));
var WKUIDelegateImpl = (function (_super) {
    __extends(WKUIDelegateImpl, _super);
    function WKUIDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    WKUIDelegateImpl.initWithOwner = function (owner) {
        var handler = WKUIDelegateImpl.new();
        handler._owner = owner;
        return handler;
    };
    WKUIDelegateImpl.prototype.webViewCreateWebViewWithConfigurationForNavigationActionWindowFeatures = function (webView, configuration, navigationAction, windowFeatures) {
        if (navigationAction && (!navigationAction.targetFrame || (navigationAction.targetFrame && !navigationAction.targetFrame.mainFrame))) {
            webView.loadRequest(navigationAction.request);
        }
        return null;
    };
    WKUIDelegateImpl.ObjCProtocols = [WKUIDelegate];
    return WKUIDelegateImpl;
}(NSObject));
var UIScrollViewDelegateImpl = (function (_super) {
    __extends(UIScrollViewDelegateImpl, _super);
    function UIScrollViewDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UIScrollViewDelegateImpl_1 = UIScrollViewDelegateImpl;
    UIScrollViewDelegateImpl.initWithOwner = function (owner) {
        var handler = UIScrollViewDelegateImpl_1.new();
        handler._owner = owner;
        return handler;
    };
    UIScrollViewDelegateImpl.prototype._initCurrentValues = function (scrollView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner && (owner._minimumZoomScale === undefined || owner._maximumZoomScale === undefined || owner._zoomScale === undefined)) {
            owner._minimumZoomScale = scrollView.minimumZoomScale;
            owner._maximumZoomScale = scrollView.maximumZoomScale;
            owner._zoomScale = scrollView.zoomScale;
        }
    };
    UIScrollViewDelegateImpl.prototype._handleDisableZoom = function (scrollView) {
        var _a;
        var owner = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner.disableZoom) {
            this._initCurrentValues(scrollView);
            scrollView.maximumZoomScale = 1;
            scrollView.minimumZoomScale = 1;
            scrollView.zoomScale = 1;
        }
    };
    UIScrollViewDelegateImpl.prototype.scrollViewWillBeginZoomingWithView = function (scrollView, view) {
        this._handleDisableZoom(scrollView);
    };
    UIScrollViewDelegateImpl.prototype.scrollViewDidZoom = function (scrollView) {
        this._handleDisableZoom(scrollView);
    };
    var UIScrollViewDelegateImpl_1;
    UIScrollViewDelegateImpl = UIScrollViewDelegateImpl_1 = __decorate([
        ObjCClass(UIScrollViewDelegate)
    ], UIScrollViewDelegateImpl);
    return UIScrollViewDelegateImpl;
}(NSObject));
export class WebView extends WebViewBase {
    get iosAllowInlineMediaPlayback() {
        return this._iosAllowInlineMediaPlayback;
    }
    set iosAllowInlineMediaPlayback(value) {
        // Note: can be set on the view markup,
        // thus the converter usage (value could come in as string).
        // Property.setNative should not be used because
        // it should be set before nativeView is created
        this._iosAllowInlineMediaPlayback = booleanConverter(value);
    }
    createNativeView() {
        const jScript = "var meta = document.createElement('meta'); meta.setAttribute('name', 'viewport'); meta.setAttribute('content', 'initial-scale=1.0'); document.getElementsByTagName('head')[0].appendChild(meta);";
        const wkUScript = WKUserScript.alloc().initWithSourceInjectionTimeForMainFrameOnly(jScript, 1 /* WKUserScriptInjectionTime.AtDocumentEnd */, true);
        const wkUController = WKUserContentController.new();
        wkUController.addUserScript(wkUScript);
        const configuration = WKWebViewConfiguration.new();
        if (this.iosAllowInlineMediaPlayback) {
            configuration.allowsInlineMediaPlayback = true;
            configuration.allowsPictureInPictureMediaPlayback = true;
        }
        configuration.userContentController = wkUController;
        configuration.preferences.setValueForKey(true, 'allowFileAccessFromFileURLs');
        return new WKWebView({
            frame: CGRectZero,
            configuration: configuration,
        });
    }
    initNativeView() {
        super.initNativeView();
        this._delegate = WKNavigationDelegateImpl.initWithOwner(new WeakRef(this));
        this._scrollDelegate = UIScrollViewDelegateImpl.initWithOwner(new WeakRef(this));
        this._uiDelegate = WKUIDelegateImpl.initWithOwner(new WeakRef(this));
        this.nativeViewProtected.navigationDelegate = this._delegate;
        this.nativeViewProtected.scrollView.delegate = this._scrollDelegate;
        this.nativeViewProtected.UIDelegate = this._uiDelegate;
    }
    disposeNativeView() {
        this._delegate = null;
        this._scrollDelegate = null;
        this._uiDelegate = null;
        super.disposeNativeView();
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    stopLoading() {
        this.nativeViewProtected.stopLoading();
    }
    _loadUrl(src) {
        if (src.startsWith('file:///')) {
            const cachePath = src.substring(0, src.lastIndexOf('/'));
            this.nativeViewProtected.loadFileURLAllowingReadAccessToURL(NSURL.URLWithString(src), NSURL.URLWithString(cachePath));
        }
        else {
            this.nativeViewProtected.loadRequest(NSURLRequest.requestWithURL(NSURL.URLWithString(src)));
        }
    }
    _loadData(content) {
        this.nativeViewProtected.loadHTMLStringBaseURL(content, NSURL.alloc().initWithString(`file:///${knownFolders.currentApp().path}/`));
    }
    get canGoBack() {
        return this.nativeViewProtected.canGoBack;
    }
    get canGoForward() {
        return this.nativeViewProtected.canGoForward;
    }
    goBack() {
        this.nativeViewProtected.goBack();
    }
    goForward() {
        this.nativeViewProtected.goForward();
    }
    reload() {
        this.nativeViewProtected.reload();
    }
    [disableZoomProperty.setNative](value) {
        if (!value && typeof this._minimumZoomScale === 'number' && typeof this._maximumZoomScale === 'number' && typeof this._zoomScale === 'number') {
            if (this.nativeViewProtected?.scrollView) {
                this.nativeViewProtected.scrollView.minimumZoomScale = this._minimumZoomScale;
                this.nativeViewProtected.scrollView.maximumZoomScale = this._maximumZoomScale;
                this.nativeViewProtected.scrollView.zoomScale = this._zoomScale;
                this._minimumZoomScale = undefined;
                this._maximumZoomScale = undefined;
                this._zoomScale = undefined;
            }
        }
    }
}
//# sourceMappingURL=index.ios.js.map