import { getWindow } from '../../utils/native-helper';
class MainScreen {
    get screen() {
        if (!this._screen) {
            // NOTE: may not want to cache this value with SwiftUI app lifecycle based apps (using NativeScriptViewFactory) given the potential of multiple scenes
            const window = getWindow();
            this._screen = window ? window.screen : UIScreen.mainScreen;
        }
        return this._screen;
    }
    get widthPixels() {
        return this.widthDIPs * this.scale;
    }
    get heightPixels() {
        return this.heightDIPs * this.scale;
    }
    get scale() {
        return this.screen.scale;
    }
    get widthDIPs() {
        return this.screen.bounds.size.width;
    }
    get heightDIPs() {
        return this.screen.bounds.size.height;
    }
    _updateMetrics() {
        // UIScreen handles the update on iOS
    }
}
export class Screen {
}
Screen.mainScreen = new MainScreen();
// This retains compatibility with NS6
export const screen = Screen;
//# sourceMappingURL=index.ios.js.map