const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
import { View, CSSType } from '../core/view';
import { Property } from '../core/properties';
import { Color } from '../../color';
let SearchBarBase = class SearchBarBase extends View {
};
SearchBarBase.submitEvent = 'submit';
SearchBarBase.clearEvent = 'clear';
SearchBarBase = __decorate([
    CSSType('SearchBar')
], SearchBarBase);
export { SearchBarBase };
SearchBarBase.prototype.recycleNativeView = 'auto';
export const textProperty = new Property({
    name: 'text',
    defaultValue: '',
    affectsLayout: __APPLE__,
});
textProperty.register(SearchBarBase);
export const hintProperty = new Property({
    name: 'hint',
    defaultValue: '',
});
hintProperty.register(SearchBarBase);
export const textFieldHintColorProperty = new Property({
    name: 'textFieldHintColor',
    equalityComparer: Color.equals,
    valueConverter: (v) => new Color(v),
});
textFieldHintColorProperty.register(SearchBarBase);
export const textFieldBackgroundColorProperty = new Property({
    name: 'textFieldBackgroundColor',
    equalityComparer: Color.equals,
    valueConverter: (v) => new Color(v),
});
textFieldBackgroundColorProperty.register(SearchBarBase);
// --- Added property for clear button color ---
export const clearButtonColorProperty = new Property({
    name: 'clearButtonColor',
    equalityComparer: Color.equals,
    valueConverter: (v) => new Color(v),
});
clearButtonColorProperty.register(SearchBarBase);
//# sourceMappingURL=search-bar-common.js.map