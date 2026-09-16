import { WrappedValue } from '../../../data/observable';
import { Trace } from '../../../trace';
import { profile } from '../../../profiling';
import { unsetValue, isResetValue } from './property-shared';
import { calc } from '../../../../../@csstools/css-calc/index.mjs';
// Backwards compatibility
export { unsetValue } from './property-shared';
const cssPropertyNames = [];
const cssShorthandConverters = new Map();
const cssShorthandLonghands = new Map();
const HAS_OWN = Object.prototype.hasOwnProperty;
const symbolPropertyMap = {};
const cssSymbolPropertyMap = {};
// Hoisted regex/constants for hot paths to avoid re-allocation
const CSS_VARIABLE_NAME_RE = /^--[^,\s]+?$/;
const DIP_RE = /([0-9]+(\.[0-9]+)?)dip\b/g;
const UNSET_RE = /unset/g;
const INFINITY_RE = /infinity/g;
const inheritableProperties = new Array();
const inheritableCssProperties = new Array();
function print(map) {
    const symbols = Object.getOwnPropertySymbols(map);
    for (const symbol of symbols) {
        const prop = map[symbol];
        if (!prop.registered) {
            console.log(`Property ${prop.name} not Registered!!!!!`);
        }
    }
}
export function _printUnregisteredProperties() {
    print(symbolPropertyMap);
    print(cssSymbolPropertyMap);
}
export function _getProperties() {
    return getPropertiesFromMap(symbolPropertyMap);
}
export function _getStyleProperties() {
    return getPropertiesFromMap(cssSymbolPropertyMap);
}
/**
 * Placeholder cascaded for each longhand of a shorthand that cannot be split while
 * parsing - a single `var()` may substitute several longhands at once, so the
 * shorthand is only parsed once its expression is resolved per view.
 * @see https://drafts.csswg.org/css-variables/#variables-in-shorthands
 */
export class CssPendingSubstitution {
    constructor(shorthand, value) {
        this.shorthand = shorthand;
        this.value = value;
    }
    toString() {
        return this.value;
    }
}
export function _isCssPendingSubstitution(value) {
    return value instanceof CssPendingSubstitution;
}
/**
 * The longhands a shorthand expands into, probed from its converter on first use -
 * the longhand properties a converter closes over are not initialized yet while
 * the shorthand itself is being registered.
 */
function getCssShorthandLonghands(cssName) {
    const known = cssShorthandLonghands.get(cssName);
    if (known) {
        return known;
    }
    const converter = cssShorthandConverters.get(cssName);
    if (!converter) {
        return undefined;
    }
    try {
        const probed = converter(unsetValue);
        if (!probed?.length) {
            return undefined;
        }
        const longhands = [];
        for (let i = 0, length = probed.length; i < length; i++) {
            longhands.push(probed[i][0].cssLocalName);
        }
        cssShorthandLonghands.set(cssName, longhands);
        return longhands;
    }
    catch (e) {
        Trace.write(`Could not determine the longhands of shorthand [${cssName}]. ${e}`, Trace.categories.Style, Trace.messageType.warn);
        return undefined;
    }
}
/**
 * One pending-substitution value per longhand of the shorthand, or `undefined`
 * when the longhands cannot be determined.
 */
export function _pendingCssShorthandSubstitution(cssName, value) {
    const longhands = getCssShorthandLonghands(cssName);
    if (!longhands) {
        return undefined;
    }
    const pending = new CssPendingSubstitution(cssName, value);
    const declarations = [];
    for (let i = 0, length = longhands.length; i < length; i++) {
        declarations.push([longhands[i], pending]);
    }
    return declarations;
}
/**
 * Expand a shorthand declaration into its longhand declarations, or `undefined`
 * when the property is not a shorthand, the value still has to be evaluated per
 * view (`var()`/`calc()`), or it does not parse.
 */
export function _expandCssShorthand(cssName, value) {
    const converter = cssShorthandConverters.get(cssName);
    if (!converter) {
        return undefined;
    }
    if (typeof value === 'string' && (isCssVariableExpression(value) || isCssCalcExpression(value))) {
        return undefined;
    }
    try {
        const converted = converter(value);
        const expanded = [];
        for (let i = 0, length = converted.length; i < length; i++) {
            expanded.push([converted[i][0].cssLocalName, converted[i][1]]);
        }
        return expanded;
    }
    catch (e) {
        Trace.write(`Failed to expand shorthand [${cssName}] with value [${value}]. ${e}`, Trace.categories.Style, Trace.messageType.warn);
        return undefined;
    }
}
export function isCssVariable(property) {
    return CSS_VARIABLE_NAME_RE.test(property);
}
export function isCssCalcExpression(value) {
    return value.includes('calc(');
}
export function isCssVariableExpression(value) {
    return value.includes('var(--');
}
export function _evaluateCssVariableExpression(view, cssName, value) {
    if (typeof value !== 'string') {
        return value;
    }
    if (!isCssVariableExpression(value)) {
        // Value is not using css-variable(s)
        return value;
    }
    let output = value.trim();
    // Evaluate every (and nested) css-variables in the value.
    let lastValue;
    while (lastValue !== output) {
        lastValue = output;
        const idx = output.lastIndexOf('var(');
        if (idx === -1) {
            continue;
        }
        const endIdx = output.indexOf(')', idx);
        if (endIdx === -1) {
            continue;
        }
        const matched = output
            .substring(idx + 4, endIdx)
            .split(',')
            .map((v) => v.trim())
            .filter((v) => !!v);
        const cssVariableName = matched.shift();
        let cssVariableValue = view.style.getCssVariable(cssVariableName);
        if (cssVariableValue === null && matched.length) {
            cssVariableValue = _evaluateCssVariableExpression(view, cssName, matched.join(', ')).split(',')[0];
        }
        if (!cssVariableValue) {
            cssVariableValue = 'unset';
        }
        output = `${output.substring(0, idx)}${cssVariableValue}${output.substring(endIdx + 1)}`;
    }
    return output;
}
export function _evaluateCssCalcExpression(value) {
    if (typeof value !== 'string') {
        return value;
    }
    if (isCssCalcExpression(value)) {
        return calc(_replaceKeywordsWithValues(_replaceDip(value)));
    }
    else {
        return value;
    }
    return value;
}
function _replaceDip(value) {
    return value.replace(DIP_RE, '$1');
}
function _replaceKeywordsWithValues(value) {
    let cssValue = value;
    if (cssValue.includes('unset')) {
        cssValue = cssValue.replace(UNSET_RE, '0');
    }
    if (cssValue.includes('infinity')) {
        cssValue = cssValue.replace(INFINITY_RE, '999999');
    }
    return cssValue;
}
function getPropertiesFromMap(map) {
    const symbols = Object.getOwnPropertySymbols(map);
    const len = symbols.length;
    const props = new Array(len);
    for (let i = 0; i < len; i++) {
        props[i] = map[symbols[i]];
    }
    return props;
}
export class Property {
    constructor(options) {
        this.enumerable = true;
        this.configurable = true;
        const propertyName = options.name;
        this.name = propertyName;
        const key = Symbol(propertyName + ':propertyKey');
        this.key = key;
        const getDefault = Symbol(propertyName + ':getDefault');
        this.getDefault = getDefault;
        const setNative = Symbol(propertyName + ':setNative');
        this.setNative = setNative;
        const defaultValueKey = Symbol(propertyName + ':nativeDefaultValue');
        this.defaultValueKey = defaultValueKey;
        const defaultValue = options.defaultValue;
        this.defaultValue = defaultValue;
        const eventName = propertyName + 'Change';
        let equalityComparer = options.equalityComparer;
        let affectsLayout = options.affectsLayout;
        let valueChanged = options.valueChanged;
        let valueConverter = options.valueConverter;
        let overrideConverter = false;
        this.overrideHandlers = function (options) {
            if (typeof options.equalityComparer !== 'undefined') {
                equalityComparer = options.equalityComparer;
            }
            if (typeof options.affectsLayout !== 'undefined') {
                affectsLayout = options.affectsLayout;
            }
            if (typeof options.valueChanged !== 'undefined') {
                valueChanged = options.valueChanged;
            }
            if (typeof options.valueConverter !== 'undefined') {
                valueConverter = options.valueConverter;
                overrideConverter = true;
            }
        };
        const property = this;
        this.set = function (boxedValue) {
            const reset = isResetValue(boxedValue);
            let value;
            let wrapped;
            if (reset) {
                value = defaultValue;
            }
            else {
                wrapped = boxedValue && boxedValue.wrapped;
                value = wrapped ? WrappedValue.unwrap(boxedValue) : boxedValue;
                if (valueConverter && typeof value === 'string') {
                    value = overrideConverter ? valueConverter.call(this, value) : valueConverter(value);
                }
            }
            const oldValue = (key in this ? this[key] : defaultValue);
            const changed = equalityComparer ? !equalityComparer(oldValue, value) : oldValue !== value;
            if (wrapped || changed) {
                if (affectsLayout) {
                    this.requestLayout();
                }
                if (reset) {
                    delete this[key];
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (this[setNative]) {
                        if (this._suspendNativeUpdatesCount) {
                            if (this._suspendedUpdates) {
                                this._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else if (defaultValueKey in this) {
                            this[setNative](this[defaultValueKey]);
                            delete this[defaultValueKey];
                        }
                        else {
                            this[setNative](defaultValue);
                        }
                    }
                }
                else {
                    this[key] = value;
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (this[setNative]) {
                        if (this._suspendNativeUpdatesCount) {
                            if (this._suspendedUpdates) {
                                this._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else {
                            if (!(defaultValueKey in this)) {
                                this[defaultValueKey] = this[getDefault] ? this[getDefault]() : defaultValue;
                            }
                            this[setNative](value);
                        }
                    }
                }
                if (this.hasListeners(eventName)) {
                    this.notify({
                        object: this,
                        eventName,
                        propertyName,
                        value,
                        oldValue,
                    });
                }
                if (this.domNode) {
                    if (reset) {
                        this.domNode.attributeRemoved(propertyName);
                    }
                    else {
                        this.domNode.attributeModified(propertyName, value);
                    }
                }
            }
        };
        this.get = function () {
            return (key in this ? this[key] : defaultValue);
        };
        this.nativeValueChange = function (owner, value) {
            const oldValue = (key in owner ? owner[key] : defaultValue);
            const changed = equalityComparer ? !equalityComparer(oldValue, value) : oldValue !== value;
            if (changed) {
                owner[key] = value;
                if (valueChanged) {
                    valueChanged(owner, oldValue, value);
                }
                if (owner.nativeViewProtected && !(defaultValueKey in owner)) {
                    owner[defaultValueKey] = owner[getDefault] ? owner[getDefault]() : defaultValue;
                }
                if (owner.hasListeners(eventName)) {
                    owner.notify({
                        object: owner,
                        eventName,
                        propertyName,
                        value,
                        oldValue,
                    });
                }
                if (affectsLayout) {
                    owner.requestLayout();
                }
                if (owner.domNode) {
                    owner.domNode.attributeModified(propertyName, value);
                }
            }
        };
        symbolPropertyMap[key] = this;
    }
    register(cls) {
        if (this.registered) {
            throw new Error(`Property ${this.name} already registered.`);
        }
        this.registered = true;
        Object.defineProperty(cls.prototype, this.name, this);
    }
    isSet(instance) {
        return this.key in instance;
    }
}
Property.prototype.isStyleProperty = false;
export class CoercibleProperty extends Property {
    constructor(options) {
        super(options);
        const propertyName = options.name;
        const key = this.key;
        const getDefault = this.getDefault;
        const setNative = this.setNative;
        const defaultValueKey = this.defaultValueKey;
        const defaultValue = this.defaultValue;
        const coerceKey = Symbol(propertyName + ':coerceKey');
        const eventName = propertyName + 'Change';
        let affectsLayout = options.affectsLayout;
        let equalityComparer = options.equalityComparer;
        let valueChanged = options.valueChanged;
        let valueConverter = options.valueConverter;
        let coerceCallback = options.coerceValue;
        let overrideConverter = false;
        const property = this;
        this.overrideHandlers = function (options) {
            if (typeof options.equalityComparer !== 'undefined') {
                equalityComparer = options.equalityComparer;
            }
            if (typeof options.affectsLayout !== 'undefined') {
                affectsLayout = options.affectsLayout;
            }
            if (typeof options.valueChanged !== 'undefined') {
                valueChanged = options.valueChanged;
            }
            if (typeof options.valueConverter !== 'undefined') {
                valueConverter = options.valueConverter;
                overrideConverter = true;
            }
            if (typeof options.coerceValue !== 'undefined') {
                coerceCallback = options.coerceValue;
            }
        };
        this.coerce = function (target) {
            const originalValue = (coerceKey in target ? target[coerceKey] : defaultValue);
            // need that to make coercing but also fire change events
            target[propertyName] = originalValue;
        };
        this.set = function (boxedValue) {
            const reset = isResetValue(boxedValue);
            let value;
            let wrapped;
            if (reset) {
                value = defaultValue;
                delete this[coerceKey];
            }
            else {
                wrapped = boxedValue && boxedValue.wrapped;
                value = wrapped ? WrappedValue.unwrap(boxedValue) : boxedValue;
                if (valueConverter && typeof value === 'string') {
                    value = overrideConverter ? valueConverter.call(this, value) : valueConverter(value);
                }
                this[coerceKey] = value;
                value = coerceCallback(this, value);
            }
            const oldValue = key in this ? this[key] : defaultValue;
            const changed = equalityComparer ? !equalityComparer(oldValue, value) : oldValue !== value;
            if (wrapped || changed) {
                if (reset) {
                    delete this[key];
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (this[setNative]) {
                        if (this._suspendNativeUpdatesCount) {
                            if (this._suspendedUpdates) {
                                this._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else if (defaultValueKey in this) {
                            this[setNative](this[defaultValueKey]);
                            delete this[defaultValueKey];
                        }
                        else {
                            this[setNative](defaultValue);
                        }
                    }
                }
                else {
                    this[key] = value;
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (this[setNative]) {
                        if (this._suspendNativeUpdatesCount) {
                            if (this._suspendedUpdates) {
                                this._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else {
                            if (!(defaultValueKey in this)) {
                                this[defaultValueKey] = this[getDefault] ? this[getDefault]() : defaultValue;
                            }
                            this[setNative](value);
                        }
                    }
                }
                if (this.hasListeners(eventName)) {
                    this.notify({
                        object: this,
                        eventName,
                        propertyName,
                        value,
                        oldValue,
                    });
                }
                if (affectsLayout) {
                    this.requestLayout();
                }
                if (this.domNode) {
                    if (reset) {
                        this.domNode.attributeRemoved(propertyName);
                    }
                    else {
                        this.domNode.attributeModified(propertyName, value);
                    }
                }
            }
        };
    }
}
export class InheritedProperty extends Property {
    constructor(options) {
        super(options);
        const name = options.name;
        const key = this.key;
        const defaultValue = options.defaultValue;
        const sourceKey = Symbol(name + ':valueSourceKey');
        this.sourceKey = sourceKey;
        const setBase = this.set;
        const setFunc = (valueSource) => function (value) {
            const that = this;
            let unboxedValue;
            let newValueSource;
            if (isResetValue(value)) {
                const parent = that.parent;
                // If value is not initial or unset and view has a parent that has non-default value, use it as the reset value.
                if (value !== 'initial' && parent && parent[sourceKey] !== 0 /* ValueSource.Default */) {
                    unboxedValue = parent[name];
                    newValueSource = 1 /* ValueSource.Inherited */;
                }
                else {
                    unboxedValue = defaultValue;
                    newValueSource = 0 /* ValueSource.Default */;
                }
            }
            else {
                // else we are set through property set.
                unboxedValue = value;
                newValueSource = valueSource;
            }
            // take currentValue before calling base - base may change it.
            const currentValue = that[key];
            setBase.call(that, unboxedValue);
            const newValue = that[key];
            that[sourceKey] = newValueSource;
            if (currentValue !== newValue) {
                const reset = newValueSource === 0 /* ValueSource.Default */;
                that.eachChild((child) => {
                    const childValueSource = child[sourceKey] || 0 /* ValueSource.Default */;
                    if (reset) {
                        if (childValueSource === 1 /* ValueSource.Inherited */) {
                            setFunc.call(child, unsetValue);
                        }
                    }
                    else {
                        if (childValueSource <= 1 /* ValueSource.Inherited */) {
                            setInheritedValue.call(child, newValue);
                        }
                    }
                    return true;
                });
            }
        };
        const setInheritedValue = setFunc(1 /* ValueSource.Inherited */);
        this.setInheritedValue = setInheritedValue;
        this.set = setFunc(3 /* ValueSource.Local */);
        inheritableProperties.push(this);
    }
}
export class CssProperty {
    constructor(options) {
        const propertyName = options.name;
        this.name = propertyName;
        // Guard against undefined cssName
        if (options.cssName) {
            cssPropertyNames.push(options.cssName);
        }
        this.cssName = `css:${options.cssName}`;
        this.cssLocalName = options.cssName;
        const key = Symbol(propertyName + ':propertyKey');
        this.key = key;
        const sourceKey = Symbol(propertyName + ':valueSourceKey');
        this.sourceKey = sourceKey;
        const getDefault = Symbol(propertyName + ':getDefault');
        this.getDefault = getDefault;
        const setNative = Symbol(propertyName + ':setNative');
        this.setNative = setNative;
        const defaultValueKey = Symbol(propertyName + ':nativeDefaultValue');
        this.defaultValueKey = defaultValueKey;
        const defaultValue = options.defaultValue;
        this.defaultValue = defaultValue;
        const eventName = propertyName + 'Change';
        let affectsLayout = options.affectsLayout;
        let equalityComparer = options.equalityComparer;
        let valueChanged = options.valueChanged;
        let valueConverter = options.valueConverter;
        let overrideConverter = false;
        this.overrideHandlers = function (options) {
            if (typeof options.equalityComparer !== 'undefined') {
                equalityComparer = options.equalityComparer;
            }
            if (typeof options.affectsLayout !== 'undefined') {
                affectsLayout = options.affectsLayout;
            }
            if (typeof options.valueChanged !== 'undefined') {
                valueChanged = options.valueChanged;
            }
            if (typeof options.valueConverter !== 'undefined') {
                valueConverter = options.valueConverter;
                overrideConverter = true;
            }
        };
        const property = this;
        function setLocalValue(newValue) {
            const view = this.viewRef.get();
            if (!view) {
                Trace.write(`${newValue} not set to view because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
                return;
            }
            const reset = isResetValue(newValue) || newValue === '';
            let value;
            if (reset) {
                value = defaultValue;
                delete this[sourceKey];
            }
            else {
                this[sourceKey] = 3 /* ValueSource.Local */;
                value = valueConverter && typeof newValue === 'string' ? (overrideConverter ? valueConverter.call(this, newValue) : valueConverter(newValue)) : newValue;
            }
            const oldValue = (key in this ? this[key] : defaultValue);
            const changed = equalityComparer ? !equalityComparer(oldValue, value) : oldValue !== value;
            if (changed) {
                if (reset) {
                    delete this[key];
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (view[setNative]) {
                        if (view._suspendNativeUpdatesCount) {
                            if (view._suspendedUpdates) {
                                view._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else if (defaultValueKey in this) {
                            view[setNative](this[defaultValueKey]);
                            delete this[defaultValueKey];
                        }
                        else {
                            view[setNative](defaultValue);
                        }
                    }
                }
                else {
                    this[key] = value;
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (view[setNative]) {
                        if (view._suspendNativeUpdatesCount) {
                            if (view._suspendedUpdates) {
                                view._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else {
                            if (!(defaultValueKey in this)) {
                                this[defaultValueKey] = view[getDefault] ? view[getDefault]() : defaultValue;
                            }
                            view[setNative](value);
                        }
                    }
                }
                if (this.hasListeners(eventName)) {
                    this.notify({
                        object: this,
                        eventName,
                        propertyName,
                        value,
                        oldValue,
                    });
                }
                if (affectsLayout) {
                    view.requestLayout();
                }
            }
        }
        function setCssValue(newValue) {
            const view = this.viewRef.get();
            if (!view) {
                Trace.write(`${newValue} not set to view because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
                return;
            }
            const currentValueSource = this[sourceKey] || 0 /* ValueSource.Default */;
            // We have localValueSource - NOOP.
            if (currentValueSource === 3 /* ValueSource.Local */) {
                return;
            }
            const reset = isResetValue(newValue) || newValue === '';
            let value;
            if (reset) {
                value = defaultValue;
                delete this[sourceKey];
            }
            else {
                value = valueConverter && typeof newValue === 'string' ? (overrideConverter ? valueConverter.call(this, newValue) : valueConverter(newValue)) : newValue;
                this[sourceKey] = 2 /* ValueSource.Css */;
            }
            const oldValue = (key in this ? this[key] : defaultValue);
            const changed = equalityComparer ? !equalityComparer(oldValue, value) : oldValue !== value;
            if (changed) {
                if (reset) {
                    delete this[key];
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (view[setNative]) {
                        if (view._suspendNativeUpdatesCount) {
                            if (view._suspendedUpdates) {
                                view._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else if (defaultValueKey in this) {
                            view[setNative](this[defaultValueKey]);
                            delete this[defaultValueKey];
                        }
                        else {
                            view[setNative](defaultValue);
                        }
                    }
                }
                else {
                    this[key] = value;
                    if (valueChanged) {
                        valueChanged(this, oldValue, value);
                    }
                    if (view[setNative]) {
                        if (view._suspendNativeUpdatesCount) {
                            if (view._suspendedUpdates) {
                                view._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else {
                            if (!(defaultValueKey in this)) {
                                this[defaultValueKey] = view[getDefault] ? view[getDefault]() : defaultValue;
                            }
                            view[setNative](value);
                        }
                    }
                }
                if (this.hasListeners(eventName)) {
                    this.notify({
                        object: this,
                        eventName,
                        propertyName,
                        value,
                        oldValue,
                    });
                }
                if (affectsLayout) {
                    view.requestLayout();
                }
            }
        }
        function get() {
            return key in this ? this[key] : defaultValue;
        }
        this.cssValueDescriptor = {
            enumerable: true,
            configurable: true,
            get: get,
            set: setCssValue,
        };
        this.localValueDescriptor = {
            enumerable: true,
            configurable: true,
            get: get,
            set: setLocalValue,
        };
        cssSymbolPropertyMap[key] = this;
    }
    register(cls) {
        if (this.registered) {
            throw new Error(`Property ${this.name} already registered.`);
        }
        this.registered = true;
        Object.defineProperty(cls.prototype, this.name, this.localValueDescriptor);
        Object.defineProperty(cls.prototype, this.cssName, this.cssValueDescriptor);
        if (this.cssLocalName !== this.cssName) {
            Object.defineProperty(cls.prototype, this.cssLocalName, this.localValueDescriptor);
        }
    }
    isSet(instance) {
        return this.key in instance;
    }
}
CssProperty.prototype.isStyleProperty = true;
export class CssAnimationProperty {
    constructor(options) {
        const propertyName = options.name;
        this.name = propertyName;
        if (options.cssName) {
            cssPropertyNames.push(options.cssName);
        }
        CssAnimationProperty.properties[propertyName] = this;
        if (options.cssName && options.cssName !== propertyName) {
            CssAnimationProperty.properties[options.cssName] = this;
        }
        this._valueConverter = options.valueConverter;
        const cssLocalName = options.cssName || propertyName;
        this.cssLocalName = cssLocalName;
        const cssName = 'css:' + cssLocalName;
        this.cssName = cssName;
        const keyframeName = 'keyframe:' + propertyName;
        this.keyframe = keyframeName;
        const defaultName = 'default:' + propertyName;
        const defaultValueKey = Symbol(defaultName);
        this.defaultValueKey = defaultValueKey;
        this.defaultValue = options.defaultValue;
        const cssValue = Symbol(cssName);
        const styleValue = Symbol(`local:${propertyName}`);
        const keyframeValue = Symbol(keyframeName);
        const computedValue = Symbol('computed-value:' + propertyName);
        this.key = computedValue;
        const computedSource = Symbol('computed-source:' + propertyName);
        this.source = computedSource;
        this.getDefault = Symbol(propertyName + ':getDefault');
        const getDefault = this.getDefault;
        const setNative = (this.setNative = Symbol(propertyName + ':setNative'));
        const eventName = propertyName + 'Change';
        const property = this;
        function descriptor(symbol, propertySource, enumerable, configurable, getsComputed) {
            return {
                enumerable,
                configurable,
                get: getsComputed
                    ? function () {
                        return this[computedValue];
                    }
                    : function () {
                        return this[symbol];
                    },
                set(boxedValue) {
                    const view = this.viewRef.get();
                    if (!view) {
                        Trace.write(`${boxedValue} not set to view because ".viewRef" is cleared`, Trace.categories.Animation, Trace.messageType.warn);
                        return;
                    }
                    const oldValue = this[computedValue];
                    const oldSource = this[computedSource];
                    const wasSet = oldSource !== 0 /* ValueSource.Default */;
                    const reset = isResetValue(boxedValue) || boxedValue === '';
                    if (reset) {
                        this[symbol] = boxedValue;
                        if (this[computedSource] === propertySource) {
                            // Fallback to lower value source.
                            if (!isResetValue(this[styleValue])) {
                                this[computedSource] = 3 /* ValueSource.Local */;
                                this[computedValue] = this[styleValue];
                            }
                            else if (!isResetValue(this[cssValue])) {
                                this[computedSource] = 2 /* ValueSource.Css */;
                                this[computedValue] = this[cssValue];
                            }
                            else {
                                delete this[computedSource];
                                delete this[computedValue];
                            }
                        }
                    }
                    else {
                        if (options.valueConverter && typeof boxedValue === 'string') {
                            boxedValue = options.valueConverter.call(this, boxedValue);
                        }
                        this[symbol] = boxedValue;
                        if (this[computedSource] <= propertySource) {
                            this[computedSource] = propertySource;
                            this[computedValue] = boxedValue;
                        }
                    }
                    const value = this[computedValue];
                    const source = this[computedSource];
                    const isSet = source !== 0 /* ValueSource.Default */;
                    const computedValueChanged = oldValue !== value && (!options.equalityComparer || !options.equalityComparer(oldValue, value));
                    if (computedValueChanged && options.valueChanged) {
                        options.valueChanged(this, oldValue, value);
                    }
                    if (view[setNative] && (computedValueChanged || isSet !== wasSet)) {
                        if (view._suspendNativeUpdatesCount) {
                            if (view._suspendedUpdates) {
                                view._suspendedUpdates[propertyName] = property;
                            }
                        }
                        else {
                            if (isSet) {
                                if (!wasSet && !(defaultValueKey in this)) {
                                    this[defaultValueKey] = view[getDefault] ? view[getDefault]() : options.defaultValue;
                                }
                                view[setNative](value);
                            }
                            else if (wasSet) {
                                if (defaultValueKey in this) {
                                    view[setNative](this[defaultValueKey]);
                                }
                                else {
                                    view[setNative](options.defaultValue);
                                }
                            }
                        }
                    }
                    if (computedValueChanged && this.hasListeners(eventName)) {
                        this.notify({
                            object: this,
                            eventName,
                            propertyName,
                            value,
                            oldValue,
                        });
                    }
                },
            };
        }
        const defaultPropertyDescriptor = descriptor(defaultValueKey, 0 /* ValueSource.Default */, false, false, false);
        const cssPropertyDescriptor = descriptor(cssValue, 2 /* ValueSource.Css */, false, false, false);
        const stylePropertyDescriptor = descriptor(styleValue, 3 /* ValueSource.Local */, true, true, true);
        const keyframePropertyDescriptor = descriptor(keyframeValue, 4 /* ValueSource.Keyframe */, false, false, false);
        symbolPropertyMap[computedValue] = this;
        cssSymbolPropertyMap[computedValue] = this;
        this.register = (cls) => {
            cls.prototype[computedValue] = options.defaultValue;
            cls.prototype[computedSource] = 0 /* ValueSource.Default */;
            cls.prototype[cssValue] = unsetValue;
            cls.prototype[styleValue] = unsetValue;
            cls.prototype[keyframeValue] = unsetValue;
            Object.defineProperty(cls.prototype, defaultName, defaultPropertyDescriptor);
            Object.defineProperty(cls.prototype, cssName, cssPropertyDescriptor);
            Object.defineProperty(cls.prototype, propertyName, stylePropertyDescriptor);
            if (options.cssName && options.cssName !== options.name) {
                Object.defineProperty(cls.prototype, options.cssName, stylePropertyDescriptor);
            }
            Object.defineProperty(cls.prototype, keyframeName, keyframePropertyDescriptor);
        };
    }
    _initDefaultNativeValue(target) {
        const view = target.viewRef.get();
        if (!view) {
            Trace.write(`_initDefaultNativeValue not executed to view because ".viewRef" is cleared`, Trace.categories.Animation, Trace.messageType.warn);
            return;
        }
        const defaultValueKey = this.defaultValueKey;
        if (!(defaultValueKey in target)) {
            const getDefault = this.getDefault;
            target[defaultValueKey] = view[getDefault] ? view[getDefault]() : this.defaultValue;
        }
    }
    static _getByCssName(name) {
        return this.properties[name];
    }
    static _getPropertyNames() {
        return Object.keys(CssAnimationProperty.properties);
    }
    isSet(instance) {
        return instance[this.source] !== 0 /* ValueSource.Default */;
    }
}
CssAnimationProperty.properties = {};
CssAnimationProperty.prototype.isStyleProperty = true;
export class InheritedCssProperty extends CssProperty {
    constructor(options) {
        super(options);
        const propertyName = options.name;
        const key = this.key;
        const sourceKey = this.sourceKey;
        const getDefault = this.getDefault;
        const setNative = this.setNative;
        const defaultValueKey = this.defaultValueKey;
        const eventName = propertyName + 'Change';
        const defaultValue = options.defaultValue;
        let affectsLayout = options.affectsLayout;
        let equalityComparer = options.equalityComparer;
        let valueChanged = options.valueChanged;
        let valueConverter = options.valueConverter;
        let overrideConverter = false;
        const property = this;
        this.overrideHandlers = function (options) {
            if (typeof options.equalityComparer !== 'undefined') {
                equalityComparer = options.equalityComparer;
            }
            if (typeof options.affectsLayout !== 'undefined') {
                affectsLayout = options.affectsLayout;
            }
            if (typeof options.valueChanged !== 'undefined') {
                valueChanged = options.valueChanged;
            }
            if (typeof options.valueConverter !== 'undefined') {
                valueConverter = options.valueConverter;
                overrideConverter = true;
            }
        };
        const setFunc = (valueSource) => function (boxedValue) {
            const view = this.viewRef.get();
            if (!view) {
                Trace.write(`${boxedValue} not set to view's property because ".viewRef" is cleared`, Trace.categories.Style, Trace.messageType.warn);
                return;
            }
            const reset = isResetValue(boxedValue) || boxedValue === '';
            const currentValueSource = this[sourceKey] || 0 /* ValueSource.Default */;
            if (reset) {
                // If we want to reset cssValue and we have localValue - return;
                if (valueSource === 2 /* ValueSource.Css */ && currentValueSource === 3 /* ValueSource.Local */) {
                    return;
                }
            }
            else {
                if (currentValueSource > valueSource) {
                    return;
                }
            }
            const oldValue = key in this ? this[key] : defaultValue;
            let value;
            let unsetNativeValue = false;
            if (reset) {
                const parentStyle = view.parent ? view.parent.style : null;
                // If value is not initial or unset and view has a parent that has non-default value, use it as the reset value.
                if (boxedValue !== 'initial' && parentStyle && parentStyle[sourceKey] > 0 /* ValueSource.Default */) {
                    value = parentStyle[propertyName];
                    this[sourceKey] = 1 /* ValueSource.Inherited */;
                    this[key] = value;
                }
                else {
                    value = defaultValue;
                    delete this[sourceKey];
                    delete this[key];
                    unsetNativeValue = true;
                }
            }
            else {
                this[sourceKey] = valueSource;
                if (valueConverter && typeof boxedValue === 'string') {
                    value = overrideConverter ? valueConverter.call(this, boxedValue) : valueConverter(boxedValue);
                }
                else {
                    value = boxedValue;
                }
                this[key] = value;
            }
            const changed = equalityComparer ? !equalityComparer(oldValue, value) : oldValue !== value;
            if (changed) {
                if (valueChanged) {
                    valueChanged(this, oldValue, value);
                }
                if (view[setNative]) {
                    if (view._suspendNativeUpdatesCount) {
                        if (view._suspendedUpdates) {
                            view._suspendedUpdates[propertyName] = property;
                        }
                    }
                    else if (unsetNativeValue) {
                        if (defaultValueKey in this) {
                            view[setNative](this[defaultValueKey]);
                            delete this[defaultValueKey];
                        }
                        else {
                            view[setNative](defaultValue);
                        }
                    }
                    else {
                        if (!(defaultValueKey in this)) {
                            this[defaultValueKey] = view[getDefault] ? view[getDefault]() : defaultValue;
                        }
                        view[setNative](value);
                    }
                }
                if (this.hasListeners(eventName)) {
                    this.notify({
                        object: this,
                        eventName,
                        propertyName,
                        value,
                        oldValue,
                    });
                }
                if (affectsLayout) {
                    view.requestLayout();
                }
                view.eachChild((child) => {
                    const childStyle = child.style;
                    const childValueSource = childStyle[sourceKey] || 0 /* ValueSource.Default */;
                    if (reset) {
                        if (childValueSource === 1 /* ValueSource.Inherited */) {
                            setDefaultFunc.call(childStyle, unsetValue);
                        }
                    }
                    else {
                        if (childValueSource <= 1 /* ValueSource.Inherited */) {
                            setInheritedFunc.call(childStyle, value);
                        }
                    }
                    return true;
                });
            }
        };
        const setDefaultFunc = setFunc(0 /* ValueSource.Default */);
        const setInheritedFunc = setFunc(1 /* ValueSource.Inherited */);
        this.setInheritedValue = setInheritedFunc;
        this.cssValueDescriptor.set = setFunc(2 /* ValueSource.Css */);
        this.localValueDescriptor.set = setFunc(3 /* ValueSource.Local */);
        inheritableCssProperties.push(this);
    }
}
export class ShorthandProperty {
    constructor(options) {
        this.name = options.name;
        const key = Symbol(this.name + ':propertyKey');
        this.key = key;
        this.cssName = `css:${options.cssName}`;
        this.cssLocalName = `${options.cssName}`;
        cssShorthandConverters.set(options.cssName, options.converter);
        const converter = options.converter;
        function setLocalValue(value) {
            const view = this.viewRef.get();
            if (!view) {
                Trace.write(`setLocalValue not executed to view because ".viewRef" is cleared`, Trace.categories.Animation, Trace.messageType.warn);
                return;
            }
            view._batchUpdate(() => {
                for (const [p, v] of converter(value)) {
                    this[p.name] = v;
                }
            });
        }
        function setCssValue(value) {
            const view = this.viewRef.get();
            if (!view) {
                Trace.write(`setCssValue not executed to view because ".viewRef" is cleared`, Trace.categories.Animation, Trace.messageType.warn);
                return;
            }
            view._batchUpdate(() => {
                for (const [p, v] of converter(value)) {
                    this[p.cssName] = v;
                }
            });
        }
        this.cssValueDescriptor = {
            enumerable: true,
            configurable: true,
            get: options.getter,
            set: setCssValue,
        };
        this.localValueDescriptor = {
            enumerable: true,
            configurable: true,
            get: options.getter,
            set: setLocalValue,
        };
        cssSymbolPropertyMap[key] = this;
    }
    register(cls) {
        if (this.registered) {
            throw new Error(`Property ${this.name} already registered.`);
        }
        this.registered = true;
        Object.defineProperty(cls.prototype, this.name, this.localValueDescriptor);
        Object.defineProperty(cls.prototype, this.cssName, this.cssValueDescriptor);
        if (this.cssLocalName !== this.cssName) {
            Object.defineProperty(cls.prototype, this.cssLocalName, this.localValueDescriptor);
        }
        // Nothing is defined on `PropertyBag`: shorthands are expanded while parsing,
        // and the var()/calc() ones that do reach the bag must stay unconverted.
    }
}
export { makeValidator, makeParser } from '../../../core-types/validators';
function inheritablePropertyValuesOn(view) {
    const array = new Array();
    for (const prop of inheritableProperties) {
        const sourceKey = prop.sourceKey;
        const valueSource = view[sourceKey] || 0 /* ValueSource.Default */;
        if (valueSource !== 0 /* ValueSource.Default */) {
            // use prop.name as it will return value or default value.
            // prop.key will return undefined if property is set the same value as default one.
            array.push({ property: prop, value: view[prop.name] });
        }
    }
    return array;
}
function inheritableCssPropertyValuesOn(style) {
    const array = new Array();
    for (const prop of inheritableCssProperties) {
        const sourceKey = prop.sourceKey;
        const valueSource = style[sourceKey] || 0 /* ValueSource.Default */;
        if (valueSource !== 0 /* ValueSource.Default */) {
            // use prop.name as it will return value or default value.
            // prop.key will return undefined if property is set the same value as default one.
            array.push({ property: prop, value: style[prop.name] });
        }
    }
    return array;
}
export const initNativeView = profile('"properties".initNativeView', function initNativeView(view) {
    if (view._suspendedUpdates) {
        applyPendingNativeSetters(view);
    }
    else {
        applyAllNativeSetters(view);
    }
    // Would it be faster to delete all members of the old object?
    view._suspendedUpdates = {};
});
export function applyPendingNativeSetters(view) {
    // TODO: Check what happens if a view was suspended and its value was reset, or set back to default!
    const suspendedUpdates = view._suspendedUpdates;
    for (const propertyName in suspendedUpdates) {
        if (!HAS_OWN.call(suspendedUpdates, propertyName))
            continue;
        const property = suspendedUpdates[propertyName];
        const setNative = property.setNative;
        if (view[setNative]) {
            const { getDefault, isStyleProperty, defaultValueKey, defaultValue } = property;
            let value;
            if (isStyleProperty) {
                const style = view.style;
                if (property.isSet(view.style)) {
                    if (!(defaultValueKey in style)) {
                        style[defaultValueKey] = view[getDefault] ? view[getDefault]() : defaultValue;
                    }
                    value = view.style[propertyName];
                }
                else {
                    value = style[defaultValueKey];
                }
            }
            else {
                if (property.isSet(view)) {
                    if (!(defaultValueKey in view)) {
                        view[defaultValueKey] = view[getDefault] ? view[getDefault]() : defaultValue;
                    }
                    value = view[propertyName];
                }
                else {
                    value = view[defaultValueKey];
                }
            }
            // TODO: Only if value is different from the value before the scope was created.
            view[setNative](value);
        }
    }
}
export function applyAllNativeSetters(view) {
    let symbols = Object.getOwnPropertySymbols(view);
    for (const symbol of symbols) {
        const property = symbolPropertyMap[symbol];
        if (!property) {
            continue;
        }
        const setNative = property.setNative;
        const getDefault = property.getDefault;
        if (setNative in view) {
            const defaultValueKey = property.defaultValueKey;
            if (!(defaultValueKey in view)) {
                view[defaultValueKey] = view[getDefault] ? view[getDefault]() : property.defaultValue;
            }
            const value = view[symbol];
            view[setNative](value);
        }
    }
    const style = view.style;
    symbols = Object.getOwnPropertySymbols(style);
    for (const symbol of symbols) {
        const property = cssSymbolPropertyMap[symbol];
        if (!property) {
            continue;
        }
        if (view[property.setNative]) {
            const defaultValueKey = property.defaultValueKey;
            if (!(defaultValueKey in style)) {
                style[defaultValueKey] = view[property.getDefault] ? view[property.getDefault]() : property.defaultValue;
            }
            const value = style[symbol];
            view[property.setNative](value);
        }
    }
}
export function resetNativeView(view) {
    let symbols = Object.getOwnPropertySymbols(view);
    for (const symbol of symbols) {
        const property = symbolPropertyMap[symbol];
        if (!property) {
            continue;
        }
        if (view[property.setNative]) {
            if (property.defaultValueKey in view) {
                view[property.setNative](view[property.defaultValueKey]);
                delete view[property.defaultValueKey];
            }
            else {
                view[property.setNative](property.defaultValue);
            }
        }
    }
    const style = view.style;
    symbols = Object.getOwnPropertySymbols(style);
    for (const symbol of symbols) {
        const property = cssSymbolPropertyMap[symbol];
        if (!property) {
            continue;
        }
        if (view[property.setNative]) {
            if (property.defaultValueKey in style) {
                view[property.setNative](style[property.defaultValueKey]);
                delete style[property.defaultValueKey];
            }
            else {
                view[property.setNative](property.defaultValue);
            }
        }
    }
}
export function clearInheritedProperties(view) {
    for (const prop of inheritableProperties) {
        const sourceKey = prop.sourceKey;
        if (view[sourceKey] === 1 /* ValueSource.Inherited */) {
            prop.set.call(view, unsetValue);
        }
    }
    const style = view.style;
    for (const prop of inheritableCssProperties) {
        const sourceKey = prop.sourceKey;
        if (style[sourceKey] === 1 /* ValueSource.Inherited */) {
            prop.setInheritedValue.call(style, unsetValue);
        }
    }
}
export function resetCSSProperties(style) {
    const symbols = Object.getOwnPropertySymbols(style);
    for (const symbol of symbols) {
        let cssProperty;
        if ((cssProperty = cssSymbolPropertyMap[symbol])) {
            style[cssProperty.cssName] = unsetValue;
            if (cssProperty instanceof CssAnimationProperty) {
                style[cssProperty.keyframe] = unsetValue;
            }
        }
    }
}
export function propagateInheritableProperties(view, child) {
    const inheritablePropertyValues = inheritablePropertyValuesOn(view);
    for (const pair of inheritablePropertyValues) {
        const prop = pair.property;
        const sourceKey = prop.sourceKey;
        const currentValueSource = child[sourceKey] || 0 /* ValueSource.Default */;
        if (currentValueSource <= 1 /* ValueSource.Inherited */) {
            prop.setInheritedValue.call(child, pair.value);
        }
    }
}
export function propagateInheritableCssProperties(parentStyle, childStyle) {
    const inheritableCssPropertyValues = inheritableCssPropertyValuesOn(parentStyle);
    for (const pair of inheritableCssPropertyValues) {
        const prop = pair.property;
        const sourceKey = prop.sourceKey;
        const currentValueSource = childStyle[sourceKey] || 0 /* ValueSource.Default */;
        if (currentValueSource <= 1 /* ValueSource.Inherited */) {
            prop.setInheritedValue.call(childStyle, pair.value, 1 /* ValueSource.Inherited */);
        }
    }
}
export function getSetProperties(view) {
    const result = [];
    const ownProps = Object.getOwnPropertyNames(view);
    for (let i = 0; i < ownProps.length; i++) {
        const prop = ownProps[i];
        result.push([prop, view[prop]]);
    }
    const symbols = Object.getOwnPropertySymbols(view);
    for (const symbol of symbols) {
        const property = symbolPropertyMap[symbol];
        if (!property) {
            continue;
        }
        const value = view[property.key];
        result.push([property.name, value]);
    }
    return result;
}
export function getComputedCssValues(view) {
    const result = [];
    const style = view.style;
    for (const prop of cssPropertyNames) {
        if (prop !== undefined && prop !== null) {
            result.push([prop, style[prop]]);
        }
    }
    // Add these to enable box model in chrome-devtools styles tab
    result.push(['top', 'auto']);
    result.push(['left', 'auto']);
    result.push(['bottom', 'auto']);
    result.push(['right', 'auto']);
    return result;
}
//# sourceMappingURL=index.js.map