import { CssProperty, CssAnimationProperty, ShorthandProperty, InheritedCssProperty } from '../core/properties';
import { unsetValue } from '../core/properties/property-shared';
import { Style } from './style';
import { Color } from '../../color';
import { Font, parseFont, FontStyle, FontWeight, FontVariationSettings } from './font';
import { Background } from './background';
import { Trace } from '../../trace';
import { CoreTypes } from '../../core-types';
import { Length, FixedLength, PercentLength } from './length-shared';
import { parseBackground } from '../../css/parser';
import { LinearGradient } from './linear-gradient';
import { parseCSSShadow } from './css-shadow';
import { transformConverter } from './css-transform';
import { ClipPathFunction } from './clip-path-function';
import { parseCSSCommaSeparatedListOfValues, splitOnTopLevelSpacesAndCommas } from './css-utils';
function isNonNegativeFiniteNumber(value) {
    return isFinite(value) && !isNaN(value) && value >= 0;
}
function parseClipPath(value) {
    const funcStartIndex = value.indexOf('(');
    const funcEndIndex = value.lastIndexOf(')');
    if (funcStartIndex > -1 && funcEndIndex > -1) {
        const functionName = value.substring(0, funcStartIndex).trim();
        switch (functionName) {
            case 'rect':
            case 'circle':
            case 'ellipse':
            case 'polygon':
            case 'inset': {
                return new ClipPathFunction(functionName, value.substring(funcStartIndex + 1, funcEndIndex));
            }
            default:
                throw new Error(`Clip-path function ${functionName} is not valid.`);
        }
    }
    else {
        if (value === 'none') {
            return null;
        }
        // Only shape functions and none are supported for now
        throw new Error(`Clip-path value ${value} is not valid.`);
    }
}
function parseShorthandPositioning(value) {
    return positioningFromParts(value.split(/[ ,]+/), value);
}
function positioningFromParts(arr, value) {
    let top;
    let right;
    let bottom;
    let left;
    if (arr.length === 1) {
        top = arr[0];
        right = arr[0];
        bottom = arr[0];
        left = arr[0];
    }
    else if (arr.length === 2) {
        top = arr[0];
        bottom = arr[0];
        right = arr[1];
        left = arr[1];
    }
    else if (arr.length === 3) {
        top = arr[0];
        right = arr[1];
        left = arr[1];
        bottom = arr[2];
    }
    else if (arr.length === 4) {
        top = arr[0];
        right = arr[1];
        bottom = arr[2];
        left = arr[3];
    }
    else {
        throw new Error('Expected 1, 2, 3 or 4 parameters. Actual: ' + value);
    }
    return {
        top: top,
        right: right,
        bottom: bottom,
        left: left,
    };
}
function parseShorthandGap(value) {
    const arr = value.split(/[ ,]+/);
    let row;
    let col;
    if (arr.length === 1) {
        row = arr[0];
        col = arr[0];
    }
    else if (arr.length === 2) {
        row = arr[0];
        col = arr[1];
    }
    else {
        throw new Error('Expected 1 or 2 parameters. Actual: ' + value);
    }
    return {
        row,
        col,
    };
}
function parseBorderColorPositioning(value) {
    // Colors can be functions with spaces and commas in their arguments
    // (`rgb(0, 0, 0)`, `color-mix(in srgb, red 35%, blue)`), so only
    // top-level separators delimit the sides.
    return positioningFromParts(splitOnTopLevelSpacesAndCommas(value.trim()), value);
}
function convertToBackgrounds(value) {
    if (typeof value === 'string') {
        const backgrounds = parseBackground(value).value;
        let backgroundColor = unsetValue;
        if (backgrounds.color) {
            backgroundColor = backgrounds.color instanceof Color ? backgrounds.color : new Color(backgrounds.color);
        }
        let backgroundImage;
        if (typeof backgrounds.image === 'object' && backgrounds.image) {
            backgroundImage = LinearGradient.parse(backgrounds.image);
        }
        else {
            backgroundImage = backgrounds.image || unsetValue;
        }
        const backgroundRepeat = backgrounds.repeat || unsetValue;
        const backgroundPosition = backgrounds.position ? backgrounds.position.text : unsetValue;
        return [
            [backgroundColorProperty, backgroundColor],
            [backgroundImageProperty, backgroundImage],
            [backgroundRepeatProperty, backgroundRepeat],
            [backgroundPositionProperty, backgroundPosition],
        ];
    }
    else {
        return [
            [backgroundColorProperty, unsetValue],
            [backgroundImageProperty, unsetValue],
            [backgroundRepeatProperty, unsetValue],
            [backgroundPositionProperty, unsetValue],
        ];
    }
}
function convertToMargins(value) {
    if (typeof value === 'string' && value !== 'auto') {
        const thickness = parseShorthandPositioning(value);
        return [
            [marginTopProperty, PercentLength.parse(thickness.top)],
            [marginRightProperty, PercentLength.parse(thickness.right)],
            [marginBottomProperty, PercentLength.parse(thickness.bottom)],
            [marginLeftProperty, PercentLength.parse(thickness.left)],
        ];
    }
    else {
        return [
            [marginTopProperty, value],
            [marginRightProperty, value],
            [marginBottomProperty, value],
            [marginLeftProperty, value],
        ];
    }
}
function convertToPaddings(value) {
    if (typeof value === 'string' && value !== 'auto') {
        const thickness = parseShorthandPositioning(value);
        return [
            [paddingTopProperty, Length.parse(thickness.top)],
            [paddingRightProperty, Length.parse(thickness.right)],
            [paddingBottomProperty, Length.parse(thickness.bottom)],
            [paddingLeftProperty, Length.parse(thickness.left)],
        ];
    }
    else {
        return [
            [paddingTopProperty, value],
            [paddingRightProperty, value],
            [paddingBottomProperty, value],
            [paddingLeftProperty, value],
        ];
    }
}
function convertToGaps(value) {
    let rowGap;
    let colGap;
    if (typeof value === 'string' && value !== 'auto') {
        if (value.length) {
            const gaps = parseShorthandGap(value);
            rowGap = Length.parse(gaps.row);
            colGap = Length.parse(gaps.col);
        }
        else {
            rowGap = 0;
            colGap = 0;
        }
    }
    else {
        rowGap = value;
        colGap = value;
    }
    return [
        [rowGapProperty, rowGap],
        [columnGapProperty, colGap],
    ];
}
function convertToTransform(value) {
    if (value === unsetValue) {
        value = 'none';
    }
    const { translate, rotate, scale } = transformConverter(value);
    return [
        [translateXProperty, translate.x],
        [translateYProperty, translate.y],
        [scaleXProperty, scale.x],
        [scaleYProperty, scale.y],
        [rotateProperty, rotate.z],
        [rotateXProperty, rotate.x],
        [rotateYProperty, rotate.y],
    ];
}
export const minWidthProperty = new CssProperty({
    name: 'minWidth',
    cssName: 'min-width',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectiveMinWidth = Length.toDevicePixels(newValue, 0);
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
minWidthProperty.register(Style);
export const minHeightProperty = new CssProperty({
    name: 'minHeight',
    cssName: 'min-height',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectiveMinHeight = Length.toDevicePixels(newValue, 0);
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
minHeightProperty.register(Style);
export const widthProperty = new CssAnimationProperty({
    name: 'width',
    cssName: 'width',
    defaultValue: 'auto',
    equalityComparer: Length.equals,
    // TODO: CSSAnimationProperty was needed for keyframe (copying other impls), but `affectsLayout` does not exist
    //       on the animation property, so fake it here. x_x
    valueChanged: (target, oldValue, newValue) => {
        if (__APPLE__) {
            const view = target.viewRef.get();
            if (view) {
                view.requestLayout();
            }
        }
    },
    valueConverter: PercentLength.parse,
});
widthProperty.register(Style);
export const heightProperty = new CssAnimationProperty({
    name: 'height',
    cssName: 'height',
    defaultValue: 'auto',
    equalityComparer: Length.equals,
    // TODO: CSSAnimationProperty was needed for keyframe (copying other impls), but `affectsLayout` does not exist
    //       on the animation property, so fake it here. -_-
    valueChanged: (target, oldValue, newValue) => {
        if (__APPLE__) {
            const view = target.viewRef.get();
            if (view) {
                view.requestLayout();
            }
        }
    },
    valueConverter: PercentLength.parse,
});
heightProperty.register(Style);
export const maxWidthProperty = new CssProperty({
    name: 'maxWidth',
    cssName: 'max-width',
    // 'auto' means unconstrained (no maximum).
    defaultValue: 'auto',
    affectsLayout: global.isIOS,
    equalityComparer: Length.equals,
    // The effective pixel value is resolved at measure time in
    // View._updateEffectiveLayoutValues (percent needs the parent size), so we
    // only need to trigger a relayout here. On iOS that is done via affectsLayout;
    // on Android the native setNative handler applies it and re-measures.
    valueConverter: PercentLength.parse,
});
maxWidthProperty.register(Style);
export const maxHeightProperty = new CssProperty({
    name: 'maxHeight',
    cssName: 'max-height',
    // 'auto' means unconstrained (no maximum).
    defaultValue: 'auto',
    affectsLayout: global.isIOS,
    equalityComparer: Length.equals,
    valueConverter: PercentLength.parse,
});
maxHeightProperty.register(Style);
const marginProperty = new ShorthandProperty({
    name: 'margin',
    cssName: 'margin',
    getter: function () {
        if (PercentLength.equals(this.marginTop, this.marginRight) && PercentLength.equals(this.marginTop, this.marginBottom) && PercentLength.equals(this.marginTop, this.marginLeft)) {
            return this.marginTop;
        }
        return `${PercentLength.convertToString(this.marginTop)} ${PercentLength.convertToString(this.marginRight)} ${PercentLength.convertToString(this.marginBottom)} ${PercentLength.convertToString(this.marginLeft)}`;
    },
    converter: convertToMargins,
});
marginProperty.register(Style);
export const marginLeftProperty = new CssProperty({
    name: 'marginLeft',
    cssName: 'margin-left',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueConverter: PercentLength.parse,
});
marginLeftProperty.register(Style);
export const marginRightProperty = new CssProperty({
    name: 'marginRight',
    cssName: 'margin-right',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueConverter: PercentLength.parse,
});
marginRightProperty.register(Style);
export const marginTopProperty = new CssProperty({
    name: 'marginTop',
    cssName: 'margin-top',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueConverter: PercentLength.parse,
});
marginTopProperty.register(Style);
export const marginBottomProperty = new CssProperty({
    name: 'marginBottom',
    cssName: 'margin-bottom',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueConverter: PercentLength.parse,
});
marginBottomProperty.register(Style);
export const paddingInternalProperty = new CssProperty({
    name: 'paddingInternal',
    cssName: '_paddingInternal',
});
paddingInternalProperty.register(Style);
const paddingSetNativeOverrides = new WeakMap();
/**
 * Whether a subclass overrides any of the per-side [padding*Property.setNative]
 * handlers `coreProto` defines. An override owns padding application - the
 * consolidated paddingInternal write must stand down, or it would apply padding
 * around handlers designed to intercept it.
 */
export function _hasPaddingSetNativeOverrides(view, coreProto) {
    const constructor = view.constructor;
    let overrides = paddingSetNativeOverrides.get(constructor);
    if (overrides === undefined) {
        overrides = [paddingTopProperty, paddingRightProperty, paddingBottomProperty, paddingLeftProperty].some((property) => view[property.setNative] !== coreProto[property.setNative]);
        paddingSetNativeOverrides.set(constructor, overrides);
    }
    return overrides;
}
const paddingProperty = new ShorthandProperty({
    name: 'padding',
    cssName: 'padding',
    getter: function () {
        if (Length.equals(this.paddingTop, this.paddingRight) && Length.equals(this.paddingTop, this.paddingBottom) && Length.equals(this.paddingTop, this.paddingLeft)) {
            return this.paddingTop;
        }
        return `${Length.convertToString(this.paddingTop)} ${Length.convertToString(this.paddingRight)} ${Length.convertToString(this.paddingBottom)} ${Length.convertToString(this.paddingLeft)}`;
    },
    converter: convertToPaddings,
});
paddingProperty.register(Style);
export const paddingLeftProperty = new CssProperty({
    name: 'paddingLeft',
    cssName: 'padding-left',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectivePaddingLeft = paddingLeftProperty.isSet(target) ? Length.toDevicePixels(newValue, 0) : null;
            target.paddingInternal = view.getEffectivePaddingShorthand();
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
paddingLeftProperty.register(Style);
export const paddingRightProperty = new CssProperty({
    name: 'paddingRight',
    cssName: 'padding-right',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectivePaddingRight = paddingRightProperty.isSet(target) ? Length.toDevicePixels(newValue, 0) : null;
            target.paddingInternal = view.getEffectivePaddingShorthand();
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
paddingRightProperty.register(Style);
export const paddingTopProperty = new CssProperty({
    name: 'paddingTop',
    cssName: 'padding-top',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectivePaddingTop = paddingTopProperty.isSet(target) ? Length.toDevicePixels(newValue, 0) : null;
            target.paddingInternal = view.getEffectivePaddingShorthand();
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
paddingTopProperty.register(Style);
export const paddingBottomProperty = new CssProperty({
    name: 'paddingBottom',
    cssName: 'padding-bottom',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectivePaddingBottom = paddingBottomProperty.isSet(target) ? Length.toDevicePixels(newValue, 0) : null;
            target.paddingInternal = view.getEffectivePaddingShorthand();
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
    valueConverter: Length.parse,
});
paddingBottomProperty.register(Style);
const gapProperty = new ShorthandProperty({
    name: 'gap',
    cssName: 'gap',
    getter: function () {
        if (Length.equals(this.rowGap, this.columnGap)) {
            return this.rowGap;
        }
        return `${Length.convertToString(this.rowGap)} ${PercentLength.convertToString(this.columnGap)}`;
    },
    converter: convertToGaps,
});
gapProperty.register(Style);
export const rowGapProperty = new CssProperty({
    name: 'rowGap',
    cssName: 'row-gap',
    defaultValue: 0,
    affectsLayout: global.isIOS,
    equalityComparer: Length.equals,
    valueConverter: Length.parse,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectiveRowGap = Length.toDevicePixels(newValue, 0);
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
});
rowGapProperty.register(Style);
export const columnGapProperty = new CssProperty({
    name: 'columnGap',
    cssName: 'column-gap',
    defaultValue: 0,
    affectsLayout: global.isIOS,
    equalityComparer: Length.equals,
    valueConverter: Length.parse,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.effectiveColumnGap = Length.toDevicePixels(newValue, 0);
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
});
columnGapProperty.register(Style);
export const horizontalAlignmentProperty = new CssProperty({
    name: 'horizontalAlignment',
    cssName: 'horizontal-align',
    defaultValue: CoreTypes.HorizontalAlignment.stretch,
    affectsLayout: __APPLE__,
    valueConverter: CoreTypes.HorizontalAlignment.parse,
});
horizontalAlignmentProperty.register(Style);
export const verticalAlignmentProperty = new CssProperty({
    name: 'verticalAlignment',
    cssName: 'vertical-align',
    defaultValue: CoreTypes.VerticalAlignmentText.stretch,
    affectsLayout: __APPLE__,
    valueConverter: CoreTypes.VerticalAlignmentText.parse,
});
verticalAlignmentProperty.register(Style);
export const rotateProperty = new CssAnimationProperty({
    name: 'rotate',
    cssName: 'rotate',
    defaultValue: 0,
    valueConverter: parseFloat,
});
rotateProperty.register(Style);
export const rotateXProperty = new CssAnimationProperty({
    name: 'rotateX',
    cssName: 'rotatex',
    defaultValue: 0,
    valueConverter: parseFloat,
});
rotateXProperty.register(Style);
export const rotateYProperty = new CssAnimationProperty({
    name: 'rotateY',
    cssName: 'rotatey',
    defaultValue: 0,
    valueConverter: parseFloat,
});
rotateYProperty.register(Style);
export const perspectiveProperty = new CssAnimationProperty({
    name: 'perspective',
    cssName: 'perspective',
    defaultValue: 1000,
    valueConverter: parseFloat,
});
perspectiveProperty.register(Style);
export const scaleXProperty = new CssAnimationProperty({
    name: 'scaleX',
    cssName: 'scaleX',
    defaultValue: 1,
    valueConverter: parseFloat,
});
scaleXProperty.register(Style);
export const scaleYProperty = new CssAnimationProperty({
    name: 'scaleY',
    cssName: 'scaleY',
    defaultValue: 1,
    valueConverter: parseFloat,
});
scaleYProperty.register(Style);
export const translateXProperty = new CssAnimationProperty({
    name: 'translateX',
    cssName: 'translateX',
    defaultValue: 0,
    equalityComparer: FixedLength.equals,
    valueConverter: FixedLength.parse,
});
translateXProperty.register(Style);
export const translateYProperty = new CssAnimationProperty({
    name: 'translateY',
    cssName: 'translateY',
    defaultValue: 0,
    equalityComparer: FixedLength.equals,
    valueConverter: FixedLength.parse,
});
translateYProperty.register(Style);
const transformProperty = new ShorthandProperty({
    name: 'transform',
    cssName: 'transform',
    getter: function () {
        const scaleX = this.scaleX;
        const scaleY = this.scaleY;
        const translateX = this.translateX;
        const translateY = this.translateY;
        const rotate = this.rotate;
        const rotateX = this.rotateX;
        const rotateY = this.rotateY;
        let result = '';
        if (translateX !== 0 || translateY !== 0) {
            result += `translate(${translateX}, ${translateY}) `;
        }
        if (scaleX !== 1 || scaleY !== 1) {
            result += `scale(${scaleX}, ${scaleY}) `;
        }
        if (rotateX !== 0 || rotateY !== 0 || rotate !== 0) {
            result += `rotate(${rotateX}, ${rotateY}, ${rotate}) `;
            result += `rotate (${rotate})`;
        }
        return result.trim();
    },
    converter: convertToTransform,
});
transformProperty.register(Style);
// Background properties.
const backgroundProperty = new ShorthandProperty({
    name: 'background',
    cssName: 'background',
    getter: function () {
        return `${this.backgroundColor} ${this.backgroundImage} ${this.backgroundRepeat} ${this.backgroundPosition}`;
    },
    converter: convertToBackgrounds,
});
backgroundProperty.register(Style);
export const backgroundInternalProperty = new CssProperty({
    name: 'backgroundInternal',
    cssName: '_backgroundInternal',
    defaultValue: Background.default,
});
backgroundInternalProperty.register(Style);
export const backgroundImageProperty = new CssProperty({
    name: 'backgroundImage',
    cssName: 'background-image',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withImage(newValue);
    },
    equalityComparer: (value1, value2) => {
        if (value1 instanceof LinearGradient && value2 instanceof LinearGradient) {
            return LinearGradient.equals(value1, value2);
        }
        else {
            return value1 === value2;
        }
    },
    valueConverter: (value) => {
        if (typeof value === 'string') {
            const parsed = parseBackground(value);
            if (parsed) {
                value = typeof parsed.value.image === 'object' ? LinearGradient.parse(parsed.value.image) : value;
            }
        }
        return value;
    },
});
backgroundImageProperty.register(Style);
export const backgroundColorProperty = new CssAnimationProperty({
    name: 'backgroundColor',
    cssName: 'background-color',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withColor(newValue);
    },
    equalityComparer: Color.equals,
    valueConverter: (value) => new Color(value),
});
backgroundColorProperty.register(Style);
export const backgroundRepeatProperty = new CssProperty({
    name: 'backgroundRepeat',
    cssName: 'background-repeat',
    valueConverter: CoreTypes.BackgroundRepeat.parse,
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withRepeat(newValue);
    },
});
backgroundRepeatProperty.register(Style);
export const backgroundSizeProperty = new CssProperty({
    name: 'backgroundSize',
    cssName: 'background-size',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withSize(newValue);
    },
});
backgroundSizeProperty.register(Style);
export const backgroundPositionProperty = new CssProperty({
    name: 'backgroundPosition',
    cssName: 'background-position',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withPosition(newValue);
    },
});
backgroundPositionProperty.register(Style);
// Border Color properties.
const borderColorProperty = new ShorthandProperty({
    name: 'borderColor',
    cssName: 'border-color',
    getter: function () {
        if (Color.equals(this.borderTopColor, this.borderRightColor) && Color.equals(this.borderTopColor, this.borderBottomColor) && Color.equals(this.borderTopColor, this.borderLeftColor)) {
            return this.borderTopColor;
        }
        else {
            return `${this.borderTopColor} ${this.borderRightColor} ${this.borderBottomColor} ${this.borderLeftColor}`;
        }
    },
    converter: function (value) {
        if (typeof value === 'string') {
            const colors = parseBorderColorPositioning(value);
            return [
                [borderTopColorProperty, new Color(colors.top)],
                [borderRightColorProperty, new Color(colors.right)],
                [borderBottomColorProperty, new Color(colors.bottom)],
                [borderLeftColorProperty, new Color(colors.left)],
            ];
        }
        else {
            return [
                [borderTopColorProperty, value],
                [borderRightColorProperty, value],
                [borderBottomColorProperty, value],
                [borderLeftColorProperty, value],
            ];
        }
    },
});
borderColorProperty.register(Style);
export const borderTopColorProperty = new CssProperty({
    name: 'borderTopColor',
    cssName: 'border-top-color',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withBorderTopColor(newValue);
    },
    equalityComparer: Color.equals,
    valueConverter: (value) => new Color(value),
});
borderTopColorProperty.register(Style);
export const borderRightColorProperty = new CssProperty({
    name: 'borderRightColor',
    cssName: 'border-right-color',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withBorderRightColor(newValue);
    },
    equalityComparer: Color.equals,
    valueConverter: (value) => new Color(value),
});
borderRightColorProperty.register(Style);
export const borderBottomColorProperty = new CssProperty({
    name: 'borderBottomColor',
    cssName: 'border-bottom-color',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withBorderBottomColor(newValue);
    },
    equalityComparer: Color.equals,
    valueConverter: (value) => new Color(value),
});
borderBottomColorProperty.register(Style);
export const borderLeftColorProperty = new CssProperty({
    name: 'borderLeftColor',
    cssName: 'border-left-color',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withBorderLeftColor(newValue);
    },
    equalityComparer: Color.equals,
    valueConverter: (value) => new Color(value),
});
borderLeftColorProperty.register(Style);
// Border Width properties.
const borderWidthProperty = new ShorthandProperty({
    name: 'borderWidth',
    cssName: 'border-width',
    getter: function () {
        if (Length.equals(this.borderTopWidth, this.borderRightWidth) && Length.equals(this.borderTopWidth, this.borderBottomWidth) && Length.equals(this.borderTopWidth, this.borderLeftWidth)) {
            return this.borderTopWidth;
        }
        else {
            return `${Length.convertToString(this.borderTopWidth)} ${Length.convertToString(this.borderRightWidth)} ${Length.convertToString(this.borderBottomWidth)} ${Length.convertToString(this.borderLeftWidth)}`;
        }
    },
    converter: function (value) {
        if (typeof value === 'string' && value !== 'auto') {
            const borderWidths = parseShorthandPositioning(value);
            return [
                [borderTopWidthProperty, Length.parse(borderWidths.top)],
                [borderRightWidthProperty, Length.parse(borderWidths.right)],
                [borderBottomWidthProperty, Length.parse(borderWidths.bottom)],
                [borderLeftWidthProperty, Length.parse(borderWidths.left)],
            ];
        }
        else {
            return [
                [borderTopWidthProperty, value],
                [borderRightWidthProperty, value],
                [borderBottomWidthProperty, value],
                [borderLeftWidthProperty, value],
            ];
        }
    },
});
borderWidthProperty.register(Style);
export const borderTopWidthProperty = new CssProperty({
    name: 'borderTopWidth',
    cssName: 'border-top-width',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-top-width should be Non-Negative Finite number. Value: ${value}`);
        }
        const view = target.viewRef.get();
        if (view) {
            view.effectiveBorderTopWidth = value;
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderTopWidth(value);
    },
    valueConverter: Length.parse,
});
borderTopWidthProperty.register(Style);
export const borderRightWidthProperty = new CssProperty({
    name: 'borderRightWidth',
    cssName: 'border-right-width',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-right-width should be Non-Negative Finite number. Value: ${value}`);
        }
        const view = target.viewRef.get();
        if (view) {
            view.effectiveBorderRightWidth = value;
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderRightWidth(value);
    },
    valueConverter: Length.parse,
});
borderRightWidthProperty.register(Style);
export const borderBottomWidthProperty = new CssProperty({
    name: 'borderBottomWidth',
    cssName: 'border-bottom-width',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-bottom-width should be Non-Negative Finite number. Value: ${value}`);
        }
        const view = target.viewRef.get();
        if (view) {
            view.effectiveBorderBottomWidth = value;
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderBottomWidth(value);
    },
    valueConverter: Length.parse,
});
borderBottomWidthProperty.register(Style);
export const borderLeftWidthProperty = new CssProperty({
    name: 'borderLeftWidth',
    cssName: 'border-left-width',
    defaultValue: CoreTypes.zeroLength,
    affectsLayout: __APPLE__,
    equalityComparer: Length.equals,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-left-width should be Non-Negative Finite number. Value: ${value}`);
        }
        const view = target.viewRef.get();
        if (view) {
            view.effectiveBorderLeftWidth = value;
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderLeftWidth(value);
    },
    valueConverter: Length.parse,
});
borderLeftWidthProperty.register(Style);
// Border Radius properties.
const borderRadiusProperty = new ShorthandProperty({
    name: 'borderRadius',
    cssName: 'border-radius',
    getter: function () {
        if (Length.equals(this.borderTopLeftRadius, this.borderTopRightRadius) && Length.equals(this.borderTopLeftRadius, this.borderBottomRightRadius) && Length.equals(this.borderTopLeftRadius, this.borderBottomLeftRadius)) {
            return this.borderTopLeftRadius;
        }
        return `${Length.convertToString(this.borderTopLeftRadius)} ${Length.convertToString(this.borderTopRightRadius)} ${Length.convertToString(this.borderBottomRightRadius)} ${Length.convertToString(this.borderBottomLeftRadius)}`;
    },
    converter: function (value) {
        if (typeof value === 'string') {
            const borderRadius = parseShorthandPositioning(value);
            return [
                [borderTopLeftRadiusProperty, Length.parse(borderRadius.top)],
                [borderTopRightRadiusProperty, Length.parse(borderRadius.right)],
                [borderBottomRightRadiusProperty, Length.parse(borderRadius.bottom)],
                [borderBottomLeftRadiusProperty, Length.parse(borderRadius.left)],
            ];
        }
        else {
            return [
                [borderTopLeftRadiusProperty, value],
                [borderTopRightRadiusProperty, value],
                [borderBottomRightRadiusProperty, value],
                [borderBottomLeftRadiusProperty, value],
            ];
        }
    },
});
borderRadiusProperty.register(Style);
export const borderTopLeftRadiusProperty = new CssProperty({
    name: 'borderTopLeftRadius',
    cssName: 'border-top-left-radius',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-top-left-radius should be Non-Negative Finite number. Value: ${value}`);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderTopLeftRadius(value);
    },
    valueConverter: Length.parse,
    equalityComparer: Length.equals,
});
borderTopLeftRadiusProperty.register(Style);
export const borderTopRightRadiusProperty = new CssProperty({
    name: 'borderTopRightRadius',
    cssName: 'border-top-right-radius',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-top-right-radius should be Non-Negative Finite number. Value: ${value}`);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderTopRightRadius(value);
    },
    valueConverter: Length.parse,
    equalityComparer: Length.equals,
});
borderTopRightRadiusProperty.register(Style);
export const borderBottomRightRadiusProperty = new CssProperty({
    name: 'borderBottomRightRadius',
    cssName: 'border-bottom-right-radius',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-bottom-right-radius should be Non-Negative Finite number. Value: ${value}`);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderBottomRightRadius(value);
    },
    valueConverter: Length.parse,
    equalityComparer: Length.equals,
});
borderBottomRightRadiusProperty.register(Style);
export const borderBottomLeftRadiusProperty = new CssProperty({
    name: 'borderBottomLeftRadius',
    cssName: 'border-bottom-left-radius',
    defaultValue: 0,
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        const value = Length.toDevicePixels(newValue, 0);
        if (!isNonNegativeFiniteNumber(value)) {
            throw new Error(`border-bottom-left-radius should be Non-Negative Finite number. Value: ${value}`);
        }
        target.backgroundInternal = target.backgroundInternal.withBorderBottomLeftRadius(value);
    },
    valueConverter: Length.parse,
    equalityComparer: Length.equals,
});
borderBottomLeftRadiusProperty.register(Style);
export const cornerShapeProperty = new CssProperty({
    name: 'cornerShape',
    cssName: 'corner-shape',
    defaultValue: CoreTypes.CornerShape.round,
    valueConverter: CoreTypes.CornerShape.parse,
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withCornerShape(newValue);
    },
});
cornerShapeProperty.register(Style);
const boxShadowProperty = new CssProperty({
    name: 'boxShadow',
    cssName: 'box-shadow',
    valueChanged: (target, _oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withBoxShadows(newValue?.length
            ? newValue.map((v) => {
                return {
                    inset: v.inset,
                    offsetX: Length.toDevicePixels(v.offsetX, 0),
                    offsetY: Length.toDevicePixels(v.offsetY, 0),
                    blurRadius: Length.toDevicePixels(v.blurRadius, 0),
                    spreadRadius: Length.toDevicePixels(v.spreadRadius, 0),
                    color: v.color,
                };
            })
            : null);
    },
    valueConverter: (value) => {
        const values = parseCSSCommaSeparatedListOfValues(value);
        const result = [];
        // The first layer specified is drawn as if it is closest to the user
        for (let i = values.length - 1; i >= 0; i--) {
            const shadowVal = parseCSSShadow(values[i]);
            if (shadowVal) {
                result.push(shadowVal);
            }
        }
        return result;
    },
});
boxShadowProperty.register(Style);
export const clipPathProperty = new CssProperty({
    name: 'clipPath',
    cssName: 'clip-path',
    valueChanged: (target, oldValue, newValue) => {
        target.backgroundInternal = target.backgroundInternal.withClipPath(newValue);
    },
    equalityComparer: (value1, value2) => {
        if (value1 instanceof ClipPathFunction && value2 instanceof ClipPathFunction) {
            return ClipPathFunction.equals(value1, value2);
        }
        return value1 === value2;
    },
    valueConverter(value) {
        if (typeof value === 'string') {
            return parseClipPath(value);
        }
        return value;
    },
});
clipPathProperty.register(Style);
export const directionProperty = new InheritedCssProperty({
    defaultValue: null,
    name: 'direction',
    cssName: 'direction',
    affectsLayout: __APPLE__,
});
directionProperty.register(Style);
export const zIndexProperty = new CssProperty({
    name: 'zIndex',
    cssName: 'z-index',
    valueConverter: (value) => {
        const newValue = parseFloat(value);
        if (isNaN(newValue)) {
            throw new Error(`Invalid value: ${newValue}`);
        }
        return newValue;
    },
});
zIndexProperty.register(Style);
export const opacityProperty = new CssAnimationProperty({
    name: 'opacity',
    cssName: 'opacity',
    defaultValue: 1,
    valueConverter: (value) => {
        const newValue = parseFloat(value);
        if (!isNonNegativeFiniteNumber(newValue) || newValue > 1) {
            throw new Error(`Opacity should be between [0, 1]. Value: ${newValue}`);
        }
        return newValue;
    },
});
opacityProperty.register(Style);
export const colorProperty = new InheritedCssProperty({
    name: 'color',
    cssName: 'color',
    equalityComparer: Color.equals,
    valueConverter: (v) => new Color(v),
});
colorProperty.register(Style);
export const fontInternalProperty = new CssProperty({
    name: 'fontInternal',
    cssName: '_fontInternal',
});
fontInternalProperty.register(Style);
export const fontFamilyProperty = new InheritedCssProperty({
    name: 'fontFamily',
    cssName: 'font-family',
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        const currentFont = target.fontInternal || Font.default;
        if (currentFont.fontFamily !== newValue) {
            const newFont = currentFont.withFontFamily(newValue);
            target.fontInternal = Font.equals(Font.default, newFont) ? unsetValue : newFont;
        }
    },
});
fontFamilyProperty.register(Style);
export const fontScaleInternalProperty = new InheritedCssProperty({
    name: 'fontScaleInternal',
    cssName: '_fontScaleInternal',
    defaultValue: 1.0,
    valueConverter: (v) => parseFloat(v),
});
fontScaleInternalProperty.register(Style);
export const fontSizeProperty = new InheritedCssProperty({
    name: 'fontSize',
    cssName: 'font-size',
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        if (target.viewRef['handleFontSize'] === true) {
            return;
        }
        const currentFont = target.fontInternal || Font.default;
        if (currentFont.fontSize !== newValue) {
            const newFont = currentFont.withFontSize(newValue);
            target.fontInternal = Font.equals(Font.default, newFont) ? unsetValue : newFont;
        }
    },
    valueConverter: (v) => parseFloat(v),
});
fontSizeProperty.register(Style);
export const fontStyleProperty = new InheritedCssProperty({
    name: 'fontStyle',
    cssName: 'font-style',
    affectsLayout: __APPLE__,
    defaultValue: FontStyle.NORMAL,
    valueConverter: FontStyle.parse,
    valueChanged: (target, oldValue, newValue) => {
        const currentFont = target.fontInternal || Font.default;
        if (currentFont.fontStyle !== newValue) {
            const newFont = currentFont.withFontStyle(newValue);
            target.fontInternal = Font.equals(Font.default, newFont) ? unsetValue : newFont;
        }
    },
});
fontStyleProperty.register(Style);
export const fontWeightProperty = new InheritedCssProperty({
    name: 'fontWeight',
    cssName: 'font-weight',
    affectsLayout: __APPLE__,
    defaultValue: FontWeight.NORMAL,
    valueConverter: FontWeight.parse,
    valueChanged: (target, oldValue, newValue) => {
        const currentFont = target.fontInternal || Font.default;
        if (currentFont.fontWeight !== newValue) {
            const newFont = currentFont.withFontWeight(newValue);
            target.fontInternal = Font.equals(Font.default, newFont) ? unsetValue : newFont;
        }
    },
});
fontWeightProperty.register(Style);
const fontProperty = new ShorthandProperty({
    name: 'font',
    cssName: 'font',
    getter: function () {
        return `${this.fontStyle} ${this.fontWeight} ${this.fontSize} ${this.fontFamily}`;
    },
    converter: function (value) {
        if (value === unsetValue) {
            return [
                [fontStyleProperty, unsetValue],
                [fontWeightProperty, unsetValue],
                [fontSizeProperty, unsetValue],
                [fontFamilyProperty, unsetValue],
            ];
        }
        else {
            const font = parseFont(value);
            const fontSize = parseFloat(font.fontSize);
            return [
                [fontStyleProperty, font.fontStyle],
                [fontWeightProperty, font.fontWeight],
                [fontSizeProperty, fontSize],
                [fontFamilyProperty, font.fontFamily],
            ];
        }
    },
});
fontProperty.register(Style);
export const fontVariationSettingsProperty = new InheritedCssProperty({
    name: 'fontVariationSettings',
    cssName: 'font-variation-settings',
    affectsLayout: __APPLE__,
    valueChanged: (target, oldValue, newValue) => {
        const currentFont = target.fontInternal || Font.default;
        if (currentFont.fontVariationSettings !== newValue) {
            const newFont = currentFont.withFontVariationSettings(newValue);
            target.fontInternal = Font.equals(Font.default, newFont) ? unsetValue : newFont;
        }
    },
    valueConverter: (value) => {
        return FontVariationSettings.parse(value);
    },
});
fontVariationSettingsProperty.register(Style);
export const visibilityProperty = new CssProperty({
    name: 'visibility',
    cssName: 'visibility',
    defaultValue: CoreTypes.Visibility.visible,
    affectsLayout: __APPLE__,
    valueConverter: CoreTypes.Visibility.parse,
    valueChanged: (target, oldValue, newValue) => {
        const view = target.viewRef.get();
        if (view) {
            view.isCollapsed = newValue === CoreTypes.Visibility.collapse;
        }
        else {
            Trace.write(`${newValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
        }
    },
});
visibilityProperty.register(Style);
export const androidElevationProperty = new CssProperty({
    name: 'androidElevation',
    cssName: 'android-elevation',
    valueConverter: parseFloat,
});
androidElevationProperty.register(Style);
export const androidDynamicElevationOffsetProperty = new CssProperty({
    name: 'androidDynamicElevationOffset',
    cssName: 'android-dynamic-elevation-offset',
    valueConverter: parseFloat,
});
androidDynamicElevationOffsetProperty.register(Style);
//# sourceMappingURL=style-properties.js.map