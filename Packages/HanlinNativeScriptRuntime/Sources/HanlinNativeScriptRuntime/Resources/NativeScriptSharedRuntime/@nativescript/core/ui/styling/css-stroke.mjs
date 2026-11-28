import { Color } from '../../color';
import { parseCSSShorthand } from './css-utils';
/**
 * Parse a string into StrokeCSSValues
 * https://developer.mozilla.org/en-US/docs/Web/CSS/-webkit-text-stroke
 * @param value
 */
export function parseCSSStroke(value) {
    const data = parseCSSShorthand(value);
    if (!data) {
        return null;
    }
    const [width] = data.values;
    return {
        width,
        color: data.color ? new Color(data.color) : undefined,
    };
}
//# sourceMappingURL=css-stroke.js.map