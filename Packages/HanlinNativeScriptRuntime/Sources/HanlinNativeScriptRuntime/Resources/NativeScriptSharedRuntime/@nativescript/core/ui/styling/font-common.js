import { makeValidator, makeParser } from '../core/properties';
import { Trace } from '../../trace';
export const FONTS_BASE_PATH = '/fonts';
export class Font {
    get isItalic() {
        return this.fontStyle === FontStyle.ITALIC;
    }
    get isBold() {
        return isFontWeightBold(this.fontWeight);
    }
    constructor(fontFamily, fontSize, fontStyle, fontWeight, fontScale, fontVariationSettings) {
        this.fontFamily = fontFamily;
        this.fontSize = fontSize;
        this.fontVariationSettings = fontVariationSettings;
        this.fontStyle = fontStyle ?? FontStyle.NORMAL;
        this.fontWeight = fontWeight ?? FontWeight.NORMAL;
        this.fontScale = fontScale ?? 1;
    }
    static equals(value1, value2) {
        // both values are falsy
        if (!value1 && !value2) {
            return true;
        }
        // only one is falsy
        if (!value1 || !value2) {
            return false;
        }
        return value1.fontFamily === value2.fontFamily && value1.fontSize === value2.fontSize && value1.fontStyle === value2.fontStyle && value1.fontWeight === value2.fontWeight && value1.fontScale === value2.fontScale && FontVariationSettings.toString(value1.fontVariationSettings) === FontVariationSettings.toString(value2.fontVariationSettings);
    }
}
Font.default = undefined;
export var FontStyle;
(function (FontStyle) {
    FontStyle.NORMAL = 'normal';
    FontStyle.ITALIC = 'italic';
    FontStyle.isValid = makeValidator(FontStyle.NORMAL, FontStyle.ITALIC);
    FontStyle.parse = makeParser(FontStyle.isValid);
})(FontStyle || (FontStyle = {}));
export var FontWeight;
(function (FontWeight) {
    FontWeight.THIN = '100';
    FontWeight.EXTRA_LIGHT = '200';
    FontWeight.LIGHT = '300';
    FontWeight.NORMAL = 'normal';
    FontWeight.MEDIUM = '500';
    FontWeight.SEMI_BOLD = '600';
    FontWeight.BOLD = 'bold';
    FontWeight.EXTRA_BOLD = '800';
    FontWeight.BLACK = '900';
    FontWeight.isValid = makeValidator(FontWeight.THIN, FontWeight.EXTRA_LIGHT, FontWeight.LIGHT, FontWeight.NORMAL, '400', FontWeight.MEDIUM, FontWeight.SEMI_BOLD, FontWeight.BOLD, '700', FontWeight.EXTRA_BOLD, FontWeight.BLACK);
    FontWeight.parse = makeParser(FontWeight.isValid);
})(FontWeight || (FontWeight = {}));
export var FontVariationSettings;
(function (FontVariationSettings) {
    function parse(fontVariationSettings) {
        if (!fontVariationSettings) {
            return null;
        }
        const excluded = ['normal', 'revert-layer'];
        const variationSettingsValue = fontVariationSettings.trim();
        if (excluded.indexOf(variationSettingsValue.toLowerCase()) !== -1) {
            return null;
        }
        const chunks = variationSettingsValue.split(',');
        if (chunks.length) {
            const parsed = [];
            for (const chunk of chunks) {
                const trimmedChunk = chunk.trim();
                const axisChunks = trimmedChunk.split(' ');
                if (axisChunks.length === 2) {
                    const axisName = axisChunks[0].trim();
                    const axisValue = parseFloat(axisChunks[1]);
                    // See https://drafts.csswg.org/css-fonts/#font-variation-settings-def.
                    // Axis name strings longer or shorter than four characters are invalid.
                    if (!isNaN(axisValue) && axisName.length === 6 && ((axisName.startsWith("'") && axisName.endsWith("'")) || (axisName.startsWith('"') && axisName.endsWith('"')))) {
                        // Remove quotes as they might cause problems when using name as an object key
                        const unquotedAxisName = axisName.substring(1, axisName.length - 1);
                        parsed.push({ axis: unquotedAxisName, value: axisValue });
                    }
                    else {
                        Trace.write('Invalid value (font-variation-settings): ' + variationSettingsValue, Trace.categories.Error, Trace.messageType.error);
                    }
                }
                else {
                    Trace.write('Invalid value (font-variation-settings): ' + variationSettingsValue, Trace.categories.Error, Trace.messageType.error);
                }
            }
            return parsed;
        }
        Trace.write('Invalid value (font-variation-settings): ' + variationSettingsValue, Trace.categories.Error, Trace.messageType.error);
    }
    FontVariationSettings.parse = parse;
    function toString(fontVariationSettings) {
        if (fontVariationSettings?.length) {
            return fontVariationSettings.map(({ axis, value }) => `'${axis}' ${value}`).join(', ');
        }
        return null;
    }
    FontVariationSettings.toString = toString;
})(FontVariationSettings || (FontVariationSettings = {}));
export function parseFontFamily(value) {
    if (!value) {
        return [];
    }
    return value
        .split(',')
        .map((v) => (v || '').trim().replace(/['"]+/g, ''))
        .filter((v) => !!v);
}
export function isFontWeightBold(fontWeight) {
    return fontWeight === FontWeight.SEMI_BOLD || fontWeight === FontWeight.BOLD || fontWeight === '700' || fontWeight === FontWeight.EXTRA_BOLD || fontWeight === FontWeight.BLACK;
}
export var genericFontFamilies;
(function (genericFontFamilies) {
    genericFontFamilies.serif = 'serif';
    genericFontFamilies.sansSerif = 'sans-serif';
    genericFontFamilies.monospace = 'monospace';
    genericFontFamilies.system = 'system';
})(genericFontFamilies || (genericFontFamilies = {}));
const styles = new Set([FontStyle.NORMAL, FontStyle.ITALIC]);
// http://www.w3schools.com/cssref/pr_font_weight.asp
//- normal(same as 400)
//- bold(same as 700)
//- 100(Thin) (API16 -thin)
//- 200(Extra Light / Ultra Light) (API16 -light)
//- 300(Light) (API16 -light)
//- 400(Normal)
//- 500(Medium) (API21 -medium)
//- 600(Semi Bold / Demi Bold) (API21 -medium)
//- 700(Bold) (API16 -bold)
//- 800(Extra Bold / Ultra Bold) (API16 -bold)
//- 900(Black / Heavy) (API21 -black)
const weights = new Set([FontWeight.THIN, FontWeight.EXTRA_LIGHT, FontWeight.LIGHT, FontWeight.NORMAL, '400', FontWeight.MEDIUM, FontWeight.SEMI_BOLD, FontWeight.BOLD, '700', FontWeight.EXTRA_BOLD, FontWeight.BLACK]);
export function parseFont(fontValue) {
    const result = {
        fontStyle: 'normal',
        fontVariant: 'normal',
        fontWeight: 'normal',
    };
    const parts = fontValue.split(/\s+/);
    let part;
    while ((part = parts.shift())) {
        if (part === 'normal') {
            // nothing to do here
        }
        else if (part === 'small-caps') {
            // The only supported font variant in shorthand font
            result.fontVariant = part;
        }
        else if (styles.has(part)) {
            result.fontStyle = part;
        }
        else if (weights.has(part)) {
            result.fontWeight = part;
        }
        else if (!result.fontSize) {
            const sizes = part.split('/');
            result.fontSize = sizes[0];
            result.lineHeight = sizes.length > 1 ? sizes[1] : undefined;
        }
        else {
            result.fontFamily = part;
            if (parts.length) {
                result.fontFamily += ' ' + parts.join(' ');
            }
            break;
        }
    }
    return result;
}
/**
 * Kind of hack.
 * Used to search font variation axis names, since iOS for some reason requires names
 * but tags are the standards.
 */
export function fuzzySearch(query, dataset) {
    const q = query ? query.trim().toLowerCase() : '';
    const result = [];
    if (!q.length) {
        return null;
    }
    dataset.forEach((item) => {
        const s = item.trim().toLowerCase();
        let n = -1;
        for (const char of q) {
            n = s.indexOf(char, n + 1);
            if (!~n) {
                return;
            }
        }
        result.push(item);
    });
    return result.length ? result : null;
}
//# sourceMappingURL=font-common.js.map