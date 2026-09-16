const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
export const SDK_VERSION = parseFloat(UIDevice.currentDevice.systemVersion);
export function supportsGlass() {
    return __APPLE__ && SDK_VERSION >= 26;
}
//# sourceMappingURL=constants.ios.js.map