import { ActivityIndicatorBase, busyProperty, iosIndicatorViewStyleProperty } from './activity-indicator-common';
import { colorProperty } from '../styling/style-properties';
import { Color } from '../../color';
import { SDK_VERSION } from '../../utils/constants';
export * from './activity-indicator-common';
export class ActivityIndicator extends ActivityIndicatorBase {
    createNativeView() {
        const viewStyle = this._getNativeIndicatorViewStyle(this.iosIndicatorViewStyle);
        const view = UIActivityIndicatorView.alloc().initWithActivityIndicatorStyle(viewStyle);
        view.hidesWhenStopped = true;
        return view;
    }
    // @ts-ignore
    get ios() {
        return this.nativeViewProtected;
    }
    _getNativeIndicatorViewStyle(value) {
        let viewStyle;
        switch (value) {
            case 'large':
                viewStyle = SDK_VERSION > 12 ? 101 /* UIActivityIndicatorViewStyle.Large */ : 0 /* UIActivityIndicatorViewStyle.WhiteLarge */;
                break;
            default:
                viewStyle = SDK_VERSION > 12 ? 100 /* UIActivityIndicatorViewStyle.Medium */ : 2 /* UIActivityIndicatorViewStyle.Gray */;
                break;
        }
        return viewStyle;
    }
    [busyProperty.getDefault]() {
        return this.nativeViewProtected.animating;
    }
    [busyProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        if (value) {
            nativeView.startAnimating();
        }
        else {
            nativeView.stopAnimating();
        }
        if (nativeView.hidesWhenStopped) {
            this.requestLayout();
        }
    }
    [colorProperty.getDefault]() {
        return this.nativeViewProtected.color;
    }
    [colorProperty.setNative](value) {
        this.nativeViewProtected.color = value instanceof Color ? value.ios : value;
    }
    [iosIndicatorViewStyleProperty.setNative](value) {
        this.nativeViewProtected.activityIndicatorViewStyle = this._getNativeIndicatorViewStyle(value);
    }
}
//# sourceMappingURL=index.ios.js.map