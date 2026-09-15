import { Font as FontBase, parseFontFamily, FontWeight, FontVariationSettings, fuzzySearch, FONTS_BASE_PATH } from './font-common';
import { Trace } from '../../trace';
import { File, Folder, knownFolders, path } from '../../file-system';
export { FontStyle, FontWeight, FontVariationSettings, parseFont } from './font-common';
const uiFontCache = new Map();
function computeFontCacheKey(fontDescriptor) {
    const { fontFamily, fontSize, fontWeight, fontVariationSettings, isBold, isItalic } = fontDescriptor;
    const sep = ':';
    return [fontFamily.join(sep), fontSize, fontWeight, String(FontVariationSettings.toString(fontVariationSettings)).replace(/'/g, '').replace(/[\s,]/g, '_'), isBold, isItalic].join(sep);
}
function getUIFontCached(fontDescriptor) {
    const cacheKey = computeFontCacheKey(fontDescriptor);
    if (uiFontCache.has(cacheKey)) {
        if (Trace.isEnabled()) {
            Trace.write(`UIFont reuse from cache: ${JSON.stringify(fontDescriptor)}, cache size: ${uiFontCache.size}`, Trace.categories.Style, Trace.messageType.info);
        }
        return uiFontCache.get(cacheKey);
    }
    let uiFont = NativeScriptUtils.createUIFont(fontDescriptor);
    if (fontDescriptor.fontVariationSettings?.length) {
        let font = CGFontCreateWithFontName(uiFont.fontName);
        const variationAxes = CGFontCopyVariationAxes(font);
        // This can be null if font doesn't support axes
        if (variationAxes?.count) {
            const variationSettings = NSMutableDictionary.new();
            const variationAxesCount = variationAxes.count;
            const variationAxesNames = [];
            for (let i = 0, length = variationAxes.count; i < length; i++) {
                variationAxesNames.push(String(variationAxes[i].objectForKey('kCGFontVariationAxisName')));
            }
            for (const variationSetting of fontDescriptor.fontVariationSettings) {
                const axisName = fuzzySearch(variationSetting.axis, variationAxesNames);
                if (axisName?.length) {
                    variationSettings.setValueForKey(variationSetting.value, axisName[0]);
                }
            }
            font = CGFontCreateCopyWithVariations(font, variationSettings);
            uiFont = CTFontCreateWithGraphicsFont(font, fontDescriptor.fontSize, null, null);
        }
    }
    uiFontCache.set(cacheKey, uiFont);
    if (Trace.isEnabled()) {
        Trace.write(`UIFont creation: ${JSON.stringify(fontDescriptor)}, cache size: ${uiFontCache.size}`, Trace.categories.Style, Trace.messageType.info);
    }
    return uiFont;
}
export class Font extends FontBase {
    constructor(family, size, style, weight, scale, variationSettings) {
        super(family, size, style, weight, scale, variationSettings);
    }
    withFontFamily(family) {
        return new Font(family, this.fontSize, this.fontStyle, this.fontWeight, this.fontScale, this.fontVariationSettings);
    }
    withFontStyle(style) {
        return new Font(this.fontFamily, this.fontSize, style, this.fontWeight, this.fontScale, this.fontVariationSettings);
    }
    withFontWeight(weight) {
        return new Font(this.fontFamily, this.fontSize, this.fontStyle, weight, this.fontScale, this.fontVariationSettings);
    }
    withFontSize(size) {
        return new Font(this.fontFamily, size, this.fontStyle, this.fontWeight, this.fontScale, this.fontVariationSettings);
    }
    withFontScale(scale) {
        return new Font(this.fontFamily, this.fontSize, this.fontStyle, this.fontWeight, scale, this.fontVariationSettings);
    }
    withFontVariationSettings(variationSettings) {
        return new Font(this.fontFamily, this.fontSize, this.fontStyle, this.fontWeight, this.fontScale, variationSettings);
    }
    getUIFont(defaultFont) {
        return getUIFontCached({
            fontFamily: parseFontFamily(this.fontFamily),
            // Apply a11y scale and calculate proper font size (avoid applying multiplier to native point size as it's messing calculations)
            fontSize: this.fontSize ? this.fontSize * this.fontScale : defaultFont.pointSize,
            fontWeight: getNativeFontWeight(this.fontWeight),
            fontVariationSettings: this.fontVariationSettings,
            isBold: this.isBold,
            isItalic: this.isItalic,
        });
    }
    getAndroidTypeface() {
        return undefined;
    }
}
Font.default = new Font(undefined, undefined);
function getNativeFontWeight(fontWeight) {
    const value = typeof fontWeight === 'number' ? fontWeight + '' : fontWeight;
    switch (value) {
        case FontWeight.THIN:
            return UIFontWeightUltraLight;
        case FontWeight.EXTRA_LIGHT:
            return UIFontWeightThin;
        case FontWeight.LIGHT:
            return UIFontWeightLight;
        case FontWeight.NORMAL:
        case '400':
        case undefined:
        case null:
            return UIFontWeightRegular;
        case FontWeight.MEDIUM:
            return UIFontWeightMedium;
        case FontWeight.SEMI_BOLD:
            return UIFontWeightSemibold;
        case FontWeight.BOLD:
        case '700':
            return UIFontWeightBold;
        case FontWeight.EXTRA_BOLD:
            return UIFontWeightHeavy;
        case FontWeight.BLACK:
            return UIFontWeightBlack;
        default:
            console.log(`Invalid font weight: "${fontWeight}"`);
    }
}
export var ios;
(function (ios) {
    function registerFont(fontFile) {
        let filePath = path.join(knownFolders.currentApp().path, FONTS_BASE_PATH, fontFile);
        if (!File.exists(filePath)) {
            filePath = path.join(knownFolders.currentApp().path, fontFile);
        }
        const fontData = NSFileManager.defaultManager.contentsAtPath(filePath);
        if (!fontData) {
            throw new Error('Could not load font from: ' + fontFile);
        }
        const provider = CGDataProviderCreateWithCFData(fontData);
        const font = CGFontCreateWithDataProvider(provider);
        if (!font) {
            throw new Error('Could not load font from: ' + fontFile);
        }
        const error = new interop.Reference();
        if (!CTFontManagerRegisterGraphicsFont(font, error)) {
            if (Trace.isEnabled()) {
                Trace.write('Error occur while registering font: ' + CFErrorCopyDescription(error.value), Trace.categories.Error, Trace.messageType.error);
            }
        }
    }
    ios.registerFont = registerFont;
})(ios || (ios = {}));
function registerFontsInFolder(fontsFolderPath) {
    const fontsFolder = Folder.fromPath(fontsFolderPath);
    fontsFolder.eachEntity((fileEntity) => {
        if (Folder.exists(path.join(fontsFolderPath, fileEntity.name))) {
            return true;
        }
        if (fileEntity instanceof File && (fileEntity.extension === 'ttf' || fileEntity.extension === 'otf')) {
            ios.registerFont(fileEntity.name);
        }
        return true;
    });
}
function registerCustomFonts() {
    const appDir = knownFolders.currentApp().path;
    const fontsDir = path.join(appDir, FONTS_BASE_PATH);
    if (Folder.exists(fontsDir)) {
        registerFontsInFolder(fontsDir);
    }
}
registerCustomFonts();
//# sourceMappingURL=font.ios.js.map