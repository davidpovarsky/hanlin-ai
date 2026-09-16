const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __IOS__ = globalThis.__IOS__ !== undefined ? globalThis.__IOS__ : true;
export function btoa(stringToEncode) {
    if (__ANDROID__) {
        return org.nativescript.winter_tc.Utils.btoa(stringToEncode);
    }
    if (__IOS__) {
        return NSString.btoa(stringToEncode);
    }
}
//# sourceMappingURL=btoa.js.map