export function btoa(stringToEncode) {
    if (__ANDROID__) {
        return org.nativescript.winter_tc.Utils.btoa(stringToEncode);
    }
    if (__IOS__) {
        return NSString.btoa(stringToEncode);
    }
}
//# sourceMappingURL=btoa.js.map