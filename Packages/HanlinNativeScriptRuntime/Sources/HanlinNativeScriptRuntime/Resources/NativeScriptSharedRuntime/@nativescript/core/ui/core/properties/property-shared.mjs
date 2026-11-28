// Shared property types, interfaces, and value helpers for properties and view-base modules.
// Only put platform-agnostic logic here.
/**
 * Value specifying that Property should be set to its initial value.
 */
export const unsetValue = new Object();
export function isCssUnsetValue(value) {
    return value === 'unset' || value === 'revert';
}
// These run at the top of every property setter, so the common case of setting
// a non-string value (number, boolean, Color, object) must bail out after a
// single typeof check instead of comparing against each reset keyword.
export function isResetValue(value) {
    if (typeof value !== 'string') {
        return value === unsetValue;
    }
    return value === 'initial' || value === 'inherit' || value === 'unset' || value === 'revert';
}
export function isCssWideKeyword(value) {
    if (typeof value !== 'string') {
        return false;
    }
    return value === 'initial' || value === 'inherit' || value === 'unset' || value === 'revert';
}
//# sourceMappingURL=property-shared.js.map