import { Color } from '../../color';
import { parseCSSShorthand } from './css-utils';
/**
 * Parse a string into ShadowCSSValues
 * Supports any valid css box/text shadow combination.
 *
 * inspired by https://github.com/jxnblk/css-box-shadow/blob/master/index.js (MIT License)
 *
 * @param value
 */
export function parseCSSShadow(value) {
    const data = parseCSSShorthand(value);
    if (!data) {
        return null;
    }
    const [offsetX, offsetY, blurRadius, spreadRadius] = data.values;
    return {
        inset: data.inset,
        offsetX: offsetX,
        offsetY: offsetY,
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
        color: data.color ? new Color(data.color) : undefined,
    };
}
//# sourceMappingURL=css-shadow.js.map