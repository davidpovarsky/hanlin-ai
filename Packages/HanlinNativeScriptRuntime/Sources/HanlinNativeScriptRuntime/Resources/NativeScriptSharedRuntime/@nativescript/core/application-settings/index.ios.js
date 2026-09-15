import * as Common from './application-settings-common';
import * as utils from '../utils';
const userDefaults = NSUserDefaults.standardUserDefaults;
export function hasKey(key) {
    if (!Common.checkKey(key)) {
        return;
    }
    return userDefaults.objectForKey(key) !== null;
}
// utils.ios.getters
export function getBoolean(key, defaultValue) {
    if (!Common.checkKey(key)) {
        return;
    }
    if (hasKey(key)) {
        return userDefaults.boolForKey(key);
    }
    return defaultValue;
}
export function getString(key, defaultValue) {
    if (!Common.checkKey(key)) {
        return;
    }
    if (hasKey(key)) {
        return userDefaults.stringForKey(key);
    }
    return defaultValue;
}
export function getNumber(key, defaultValue) {
    if (!Common.checkKey(key)) {
        return;
    }
    if (hasKey(key)) {
        return userDefaults.doubleForKey(key);
    }
    return defaultValue;
}
// setters
export function setBoolean(key, value) {
    if (!Common.checkKey(key)) {
        return;
    }
    if (!Common.ensureValidValue(value, 'boolean')) {
        return;
    }
    userDefaults.setBoolForKey(value, key);
}
export function setString(key, value) {
    if (!Common.checkKey(key)) {
        return;
    }
    if (!Common.ensureValidValue(value, 'string')) {
        return;
    }
    userDefaults.setObjectForKey(value, key);
}
export function setNumber(key, value) {
    if (!Common.checkKey(key)) {
        return;
    }
    if (!Common.ensureValidValue(value, 'number')) {
        return;
    }
    userDefaults.setDoubleForKey(value, key);
}
export function remove(key) {
    if (!Common.checkKey(key)) {
        return;
    }
    userDefaults.removeObjectForKey(key);
}
export function clear() {
    userDefaults.removePersistentDomainForName(NSBundle.mainBundle.bundleIdentifier);
}
export function flush() {
    return userDefaults.synchronize();
}
export function getAllKeys() {
    return utils.ios.collections.nsArrayToJSArray(userDefaults.dictionaryRepresentation().allKeys);
}
//# sourceMappingURL=index.ios.js.map