export function checkKey(key) {
    if (typeof key !== 'string') {
        console.error("key: '" + key + "' must be a string");
        return false;
    }
    return true;
}
export function ensureValidValue(value, valueType) {
    if (typeof value !== valueType) {
        console.error("value: '" + value + "' must be a " + valueType);
        return false;
    }
    return true;
}
//# sourceMappingURL=application-settings-common.js.map