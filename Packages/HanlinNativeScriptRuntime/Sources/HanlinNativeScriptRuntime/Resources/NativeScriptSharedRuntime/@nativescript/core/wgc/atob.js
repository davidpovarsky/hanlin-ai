export function atob(data) {
    if (__ANDROID__) {
        return org.nativescript.winter_tc.Utils.atob(data);
    }
    if (__IOS__) {
        return NSString.atob(data);
    }
}
//# sourceMappingURL=atob.js.map