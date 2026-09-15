// Shared Length, FixedLength, and PercentLength helpers for styling modules.
// Only put platform-agnostic logic here.
import { layout } from '../../utils/layout-helper';
import { isCssWideKeyword } from '../core/properties/property-shared';
function equalsCommon(a, b) {
    if (a == 'auto' || isCssWideKeyword(a)) {
        return b == 'auto' || isCssWideKeyword(b);
    }
    if (b == 'auto' || isCssWideKeyword(b)) {
        return false;
    }
    if (typeof a === 'number') {
        if (typeof b === 'number') {
            return a == b;
        }
        if (!b) {
            return false;
        }
        return b.unit == 'dip' && a == b.value;
    }
    if (typeof b === 'number') {
        return a ? a.unit == 'dip' && a.value == b : false;
    }
    if (!a || !b) {
        return false;
    }
    return a.value == b.value && a.unit == b.unit;
}
function convertToStringCommon(length) {
    if (length == 'auto' || isCssWideKeyword(length)) {
        return 'auto';
    }
    if (typeof length === 'number') {
        return length.toString();
    }
    let val = length.value;
    if (length.unit === '%') {
        val *= 100;
    }
    return val + length.unit;
}
function toDevicePixelsCommon(length, auto = Number.NaN, parentAvailableWidth = Number.NaN) {
    if (length == 'auto' || isCssWideKeyword(length)) {
        return auto;
    }
    if (typeof length === 'number') {
        return layout.round(layout.toDevicePixels(length));
    }
    if (!length) {
        return auto;
    }
    // @ts-ignore
    switch (length.unit) {
        case 'px':
            // @ts-ignore
            return layout.round(length.value);
        case '%':
            // @ts-ignore
            return layout.round(parentAvailableWidth * length.value);
        case 'dip':
        default:
            // @ts-ignore
            return layout.round(layout.toDevicePixels(length.value));
    }
}
export var PercentLength;
(function (PercentLength) {
    function parse(fromValue) {
        if (fromValue == 'auto') {
            return 'auto';
        }
        if (typeof fromValue === 'string') {
            let stringValue = fromValue.trim();
            const percentIndex = stringValue.indexOf('%');
            if (percentIndex !== -1) {
                let value;
                // if only % or % is not last we treat it as invalid value.
                if (percentIndex !== stringValue.length - 1 || percentIndex === 0) {
                    value = Number.NaN;
                }
                else {
                    // Normalize result to values between -1 and 1
                    value = parseFloat(stringValue.substring(0, stringValue.length - 1).trim()) / 100;
                }
                if (isNaN(value) || !isFinite(value)) {
                    throw new Error(`Invalid value: ${fromValue}`);
                }
                return { unit: '%', value };
            }
            else if (stringValue.indexOf('px') !== -1) {
                stringValue = stringValue.replace('px', '').trim();
                const value = parseFloat(stringValue);
                if (isNaN(value) || !isFinite(value)) {
                    throw new Error(`Invalid value: ${fromValue}`);
                }
                return { unit: 'px', value };
            }
            else {
                const value = parseFloat(stringValue);
                if (isNaN(value) || !isFinite(value)) {
                    throw new Error(`Invalid value: ${fromValue}`);
                }
                return value;
            }
        }
        else {
            return fromValue;
        }
    }
    PercentLength.parse = parse;
    PercentLength.equals = equalsCommon;
    /**
     * Converts PercentLengthType unit to device pixels.
     * @param length The PercentLengthType to convert.
     * @param auto Value to use for conversion of "auto". By default is Math.NaN.
     * @param parentAvailableWidth Value to use as base when converting percent unit. By default is Math.NaN.
     */
    PercentLength.toDevicePixels = toDevicePixelsCommon;
    PercentLength.convertToString = convertToStringCommon;
})(PercentLength || (PercentLength = {}));
export var FixedLength;
(function (FixedLength) {
    function parse(fromValue) {
        if (typeof fromValue === 'string') {
            let stringValue = fromValue.trim();
            if (stringValue.indexOf('px') !== -1) {
                stringValue = stringValue.replace('px', '').trim();
                const value = parseFloat(stringValue);
                if (isNaN(value) || !isFinite(value)) {
                    throw new Error(`Invalid value: ${stringValue}`);
                }
                return { unit: 'px', value };
            }
            else {
                const value = parseFloat(stringValue);
                if (isNaN(value) || !isFinite(value)) {
                    throw new Error(`Invalid value: ${stringValue}`);
                }
                return value;
            }
        }
        else {
            return fromValue;
        }
    }
    FixedLength.parse = parse;
    FixedLength.equals = equalsCommon;
    /**
     * Converts FixedLengthType unit to device pixels.
     * @param length The FixedLengthType to convert.
     */
    FixedLength.toDevicePixels = toDevicePixelsCommon;
    FixedLength.convertToString = convertToStringCommon;
})(FixedLength || (FixedLength = {}));
export var Length;
(function (Length) {
    function parse(fromValue) {
        if (fromValue == 'auto') {
            return 'auto';
        }
        return FixedLength.parse(fromValue);
    }
    Length.parse = parse;
    Length.equals = equalsCommon;
    /**
     * Converts LengthType unit to device pixels.
     * @param length The LengthType to convert.
     * @param auto Value to use for conversion of "auto". By default is Math.NaN.
     */
    Length.toDevicePixels = toDevicePixelsCommon;
    Length.convertToString = convertToStringCommon;
})(Length || (Length = {}));
//# sourceMappingURL=length-shared.js.map