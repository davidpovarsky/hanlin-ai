const epsilon = 1e-5;
export function areClose(value1, value2) {
    return Math.abs(value1 - value2) < epsilon;
}
export function greaterThanOrClose(value1, value2) {
    return value1 > value2 || areClose(value1, value2);
}
export function greaterThan(value1, value2) {
    return value1 > value2 && !areClose(value1, value2);
}
export function lessThan(value1, value2) {
    return value1 < value2 && !areClose(value1, value2);
}
export function isZero(value) {
    return Math.abs(value) < epsilon;
}
export function greaterThanZero(value) {
    return value > 0;
}
export function notNegative(value) {
    return value >= 0;
}
export const radiansToDegrees = (a) => a * (180 / Math.PI);
export const degreesToRadians = (a) => a * (Math.PI / 180);
/**
 * Map value changes across a set of criteria
 * @param val value to map
 * @param in_min minimum
 * @param in_max maximum
 * @param out_min starting value
 * @param out_max ending value
 * @returns
 */
export function valueMap(val, in_min, in_max, out_min, out_max) {
    return ((val - in_min) * (out_max - out_min)) / (in_max - in_min) + out_min;
}
//# sourceMappingURL=number-utils.js.map