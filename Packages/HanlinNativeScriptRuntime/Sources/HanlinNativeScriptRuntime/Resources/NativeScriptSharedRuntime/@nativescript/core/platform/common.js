const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __IOS__ = globalThis.__IOS__ !== undefined ? globalThis.__IOS__ : true;
const __VISIONOS__ = globalThis.__VISIONOS__ !== undefined ? globalThis.__VISIONOS__ : false;
const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
/*
 * Enum holding platform names.
 */
export const platformNames = {
    android: 'Android',
    ios: 'iOS',
    visionos: 'visionOS',
    apple: 'apple',
};
export const isAndroid = !!__ANDROID__;
export const isIOS = !!__IOS__ || !!__VISIONOS__;
export const isVisionOS = !!__VISIONOS__;
export const isApple = !!__APPLE__;
//# sourceMappingURL=common.js.map