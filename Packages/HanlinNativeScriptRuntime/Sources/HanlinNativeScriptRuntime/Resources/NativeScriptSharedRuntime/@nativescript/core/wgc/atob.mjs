const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __IOS__ = globalThis.__IOS__ !== undefined ? globalThis.__IOS__ : true;
export function atob(data) {
    if (__ANDROID__) {
        return org.nativescript.winter_tc.Utils.atob(data);
    }
    if (__IOS__) {
        return NSString.atob(data);
    }
}
//# sourceMappingURL=atob.js.map