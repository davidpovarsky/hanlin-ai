import { parse as convertToCSSWhatSelector } from 'css-what';
import '../../globals';
import { _expandCssShorthand, _pendingCssShorthandSubstitution, isCssVariable } from '../core/properties';
import { isNullOrUndefined } from '../../utils/types';
import { cleanupImportantFlags } from './css-utils';
import { checkIfMediaQueryMatches } from '../../media-query-list';
var Combinator;
(function (Combinator) {
    Combinator["descendant"] = " ";
    Combinator["child"] = ">";
    Combinator["adjacent"] = "+";
    Combinator["sibling"] = "~";
    // Not supported
    Combinator["parent"] = "<";
    Combinator["column-combinator"] = "||";
})(Combinator || (Combinator = {}));
var AttributeSelectorOperator;
(function (AttributeSelectorOperator) {
    AttributeSelectorOperator["exists"] = "";
    AttributeSelectorOperator["equals"] = "=";
    AttributeSelectorOperator["start"] = "^=";
    AttributeSelectorOperator["end"] = "$=";
    AttributeSelectorOperator["any"] = "*=";
    AttributeSelectorOperator["element"] = "~=";
    AttributeSelectorOperator["hyphen"] = "|=";
})(AttributeSelectorOperator || (AttributeSelectorOperator = {}));
var Match;
(function (Match) {
    /**
     * Depends on attributes or pseudoclasses state;
     */
    Match.Dynamic = true;
    /**
     * Depends only on the tree structure.
     */
    Match.Static = false;
})(Match || (Match = {}));
function eachNodePreviousGeneralSibling(node, callback) {
    if (!node.parent || !node.parent.getChildIndex || !node.parent.getChildAt || !node.parent.getChildrenCount) {
        return;
    }
    const nodeIndex = node.parent.getChildIndex(node);
    if (nodeIndex === 0) {
        return;
    }
    const count = node.parent.getChildrenCount();
    let retVal = true;
    for (let i = nodeIndex - 1; i >= 0 && retVal; i--) {
        const sibling = node.parent.getChildAt(i);
        retVal = callback(sibling);
    }
}
function getNodePreviousDirectSibling(node) {
    if (!node.parent || !node.parent.getChildIndex || !node.parent.getChildAt) {
        return null;
    }
    const nodeIndex = node.parent.getChildIndex(node);
    if (nodeIndex === 0) {
        return null;
    }
    return node.parent.getChildAt(nodeIndex - 1);
}
/**
 * `<attribute>Change` is only raised by properties defined as prototype accessors;
 * a plain instance value (e.g. Angular's `_ngcontent-*` markers) never notifies,
 * so subscribing to its change event would be pure overhead.
 */
const notifyingAttributes = new WeakMap();
function attributeNotifiesChanges(node, attribute) {
    const prototype = Object.getPrototypeOf(node);
    if (!prototype) {
        return false;
    }
    let cache = notifyingAttributes.get(prototype);
    if (cache) {
        const cached = cache.get(attribute);
        if (cached !== undefined) {
            return cached;
        }
    }
    else {
        cache = new Map();
        notifyingAttributes.set(prototype, cache);
    }
    let notifies = false;
    for (let current = prototype; current; current = Object.getPrototypeOf(current)) {
        const descriptor = Object.getOwnPropertyDescriptor(current, attribute);
        if (descriptor) {
            notifies = !!descriptor.set;
            break;
        }
    }
    cache.set(attribute, notifies);
    return notifies;
}
function SelectorProperties(specificity, rarity, dynamic = false) {
    return (cls) => {
        cls.prototype.specificity = specificity;
        cls.prototype.rarity = rarity;
        cls.prototype.combinator = undefined;
        cls.prototype.dynamic = dynamic;
        cls.prototype.hasAdjacentCombinator = false;
        cls.prototype.hasSiblingCombinator = false;
        cls.prototype.tier = 0 /* SelectorTier.Application */;
        return cls;
    };
}
function FunctionalPseudoClassProperties(specificity, rarity, pseudoSelectorListType) {
    return (cls) => {
        cls.prototype.specificity = specificity;
        cls.prototype.rarity = rarity;
        cls.prototype.combinator = undefined;
        cls.prototype.dynamic = false;
        cls.prototype.hasAdjacentCombinator = false;
        cls.prototype.hasSiblingCombinator = false;
        cls.prototype.pseudoSelectorListType = pseudoSelectorListType;
        return cls;
    };
}
export class SelectorBase {
}
let SelectorCore = class SelectorCore extends SelectorBase {
    lookupSort(sorter, base) {
        sorter.sortAsUniversal(base || this);
    }
};
SelectorCore = __decorate([
    SelectorProperties(0 /* Specificity.Universal */, 0 /* Rarity.Universal */, Match.Static)
], SelectorCore);
export { SelectorCore };
export class SimpleSelector extends SelectorCore {
    accumulateChanges(node, map) {
        if (!this.dynamic) {
            return this.match(node);
        }
        else if (this.mayMatch(node)) {
            this.trackChanges(node, map);
            return true;
        }
        return false;
    }
    mayMatch(node) {
        return this.match(node);
    }
    trackChanges(node, map) {
        // No-op, silence the tslint 'block is empty'.
        // Some derived classes (dynamic) will actually fill the map with stuff here, some (static) won't do anything.
    }
}
function wrap(text) {
    return text ? ` ${text} ` : '';
}
let InvalidSelector = class InvalidSelector extends SimpleSelector {
    constructor(e) {
        super();
        this.e = e;
    }
    toString() {
        return `<${this.e}>`;
    }
    match(node) {
        return false;
    }
    lookupSort(sorter, base) {
        // No-op, silence the tslint 'block is empty'.
        // It feels like tslint has problems with simple polymorphism...
        // This selector is invalid and will never match so we won't bother sorting it to further appear in queries.
    }
};
InvalidSelector = __decorate([
    SelectorProperties(0 /* Specificity.Invalid */, 4 /* Rarity.Invalid */, Match.Static),
    __metadata("design:paramtypes", [Error])
], InvalidSelector);
export { InvalidSelector };
let UniversalSelector = class UniversalSelector extends SimpleSelector {
    toString() {
        return `*${wrap(this.combinator)}`;
    }
    match(node) {
        return true;
    }
};
UniversalSelector = __decorate([
    SelectorProperties(0 /* Specificity.Universal */, 0 /* Rarity.Universal */, Match.Static)
], UniversalSelector);
export { UniversalSelector };
let IdSelector = class IdSelector extends SimpleSelector {
    constructor(id) {
        super();
        this.id = id;
    }
    toString() {
        return `#${this.id}${wrap(this.combinator)}`;
    }
    match(node) {
        return node.id === this.id;
    }
    lookupSort(sorter, base) {
        sorter.sortById(this.id, base || this);
    }
};
IdSelector = __decorate([
    SelectorProperties(100 /* Specificity.Id */, 3 /* Rarity.Id */, Match.Static),
    __metadata("design:paramtypes", [String])
], IdSelector);
export { IdSelector };
let TypeSelector = class TypeSelector extends SimpleSelector {
    constructor(cssType) {
        super();
        this.cssType = cssType;
    }
    toString() {
        return `${this.cssType}${wrap(this.combinator)}`;
    }
    match(node) {
        return node.cssType === this.cssType;
    }
    lookupSort(sorter, base) {
        sorter.sortByType(this.cssType, base || this);
    }
};
TypeSelector = __decorate([
    SelectorProperties(1 /* Specificity.Type */, 1 /* Rarity.Type */, Match.Static),
    __metadata("design:paramtypes", [String])
], TypeSelector);
export { TypeSelector };
let ClassSelector = class ClassSelector extends SimpleSelector {
    constructor(cssClass) {
        super();
        this.cssClass = cssClass;
    }
    toString() {
        return `.${this.cssClass}${wrap(this.combinator)}`;
    }
    match(node) {
        return node.cssClasses && node.cssClasses.has(this.cssClass);
    }
    lookupSort(sorter, base) {
        sorter.sortByClass(this.cssClass, base || this);
    }
};
ClassSelector = __decorate([
    SelectorProperties(10 /* Specificity.Class */, 2 /* Rarity.Class */, Match.Static),
    __metadata("design:paramtypes", [String])
], ClassSelector);
export { ClassSelector };
let AttributeSelector = class AttributeSelector extends SimpleSelector {
    constructor(attribute, test, value, ignoreCase) {
        super();
        this.attribute = attribute;
        this.test = test;
        this.value = value;
        this.ignoreCase = ignoreCase;
        // Normalize once at construction instead of on every match
        if (ignoreCase && value) {
            this.value = value.toLowerCase();
        }
    }
    toString() {
        return `[${this.attribute}${wrap(AttributeSelectorOperator[this.test] ?? this.test)}${this.value || ''}]${wrap(this.combinator)}`;
    }
    match(node) {
        let attr = node[this.attribute];
        if (this.test === 'exists') {
            return !isNullOrUndefined(attr);
        }
        if (!this.value) {
            return false;
        }
        // Now, convert value to string
        attr += '';
        if (this.ignoreCase) {
            attr = attr.toLowerCase();
        }
        // =
        if (this.test === 'equals') {
            return attr === this.value;
        }
        // ^=
        if (this.test === 'start') {
            return attr.startsWith(this.value);
        }
        // $=
        if (this.test === 'end') {
            return attr.endsWith(this.value);
        }
        // *=
        if (this.test === 'any') {
            return attr.indexOf(this.value) !== -1;
        }
        // ~=
        if (this.test === 'element') {
            const words = attr.split(' ');
            return words && words.indexOf(this.value) !== -1;
        }
        // |=
        if (this.test === 'hyphen') {
            return attr === this.value || attr.startsWith(this.value + '-');
        }
        return false;
    }
    mayMatch(node) {
        // Registered properties live on the prototype and anything already assigned is
        // an own value; an attribute on neither can never start matching without the
        // css state being invalidated anyway.
        return this.attribute in node;
    }
    trackChanges(node, map) {
        if (attributeNotifiesChanges(node, this.attribute)) {
            map.addAttribute(node, this.attribute);
        }
    }
};
AttributeSelector = __decorate([
    SelectorProperties(10 /* Specificity.Attribute */, 0 /* Rarity.Attribute */, Match.Dynamic),
    __metadata("design:paramtypes", [String, String, String, Boolean])
], AttributeSelector);
export { AttributeSelector };
let PseudoClassSelector = class PseudoClassSelector extends SimpleSelector {
    constructor(cssPseudoClass) {
        super();
        this.cssPseudoClass = cssPseudoClass;
    }
    toString() {
        return `:${this.cssPseudoClass}${wrap(this.combinator)}`;
    }
    match(node) {
        return node.cssPseudoClasses && node.cssPseudoClasses.has(this.cssPseudoClass);
    }
    mayMatch(node) {
        return true;
    }
    trackChanges(node, map) {
        map.addPseudoClass(node, this.cssPseudoClass);
    }
};
PseudoClassSelector = __decorate([
    SelectorProperties(10 /* Specificity.PseudoClass */, 0 /* Rarity.PseudoClass */, Match.Dynamic),
    __metadata("design:paramtypes", [String])
], PseudoClassSelector);
export { PseudoClassSelector };
export class FunctionalPseudoClassSelector extends PseudoClassSelector {
    constructor(cssPseudoClass, dataType) {
        super(cssPseudoClass);
        const selectors = [];
        const needsHighestSpecificity = this.specificity === -1 /* Specificity.SelectorListHighest */;
        let specificity = 0;
        if (Array.isArray(dataType)) {
            for (const asts of dataType) {
                const selector = createSelectorFromAst(asts);
                if (selector instanceof InvalidSelector) {
                    // Only forgiving selector list can ignore invalid selectors
                    if (this.selectorListType !== 1 /* PseudoClassSelectorList.Forgiving */) {
                        selectors.splice(0);
                        specificity = 0;
                        break;
                    }
                    continue;
                }
                // The specificity of some pseudo-classes is replaced by the specificity of the most specific selector in its comma-separated argument of selectors
                if (needsHighestSpecificity && selector.specificity > specificity) {
                    specificity = selector.specificity;
                }
                selectors.push(selector);
            }
        }
        this.selectors = selectors;
        this.specificity = specificity;
        // Functional pseudo-classes become dynamic based on selectors in selector list
        this.dynamic = this.selectors.some((sel) => sel.dynamic);
        this.hasAdjacentCombinator = this.selectors.some((sel) => sel.hasAdjacentCombinator);
        this.hasSiblingCombinator = this.selectors.some((sel) => sel.hasSiblingCombinator);
    }
    toString() {
        return `:${this.cssPseudoClass}(${this.selectors.join(', ')})${wrap(this.combinator)}`;
    }
    match(node) {
        return false;
    }
    mayMatch(node) {
        return true;
    }
    trackChanges(node, map) {
        this.selectors.forEach((sel) => sel.trackChanges(node, map));
    }
}
let NotFunctionalPseudoClassSelector = class NotFunctionalPseudoClassSelector extends FunctionalPseudoClassSelector {
    match(node) {
        return !this.selectors.some((sel) => sel.match(node));
    }
};
NotFunctionalPseudoClassSelector = __decorate([
    FunctionalPseudoClassProperties(-1 /* Specificity.SelectorListHighest */, 0 /* Rarity.PseudoClass */, 0 /* PseudoClassSelectorList.Regular */)
], NotFunctionalPseudoClassSelector);
export { NotFunctionalPseudoClassSelector };
let IsFunctionalPseudoClassSelector = class IsFunctionalPseudoClassSelector extends FunctionalPseudoClassSelector {
    match(node) {
        return this.selectors.some((sel) => sel.match(node));
    }
    lookupSort(sorter, base) {
        // A faster lookup can be performed when selector list contains just a single selector
        if (this.selectors.length === 1) {
            this.selectors[0].lookupSort(sorter, base || this);
        }
        else {
            super.lookupSort(sorter, base || this);
        }
    }
};
IsFunctionalPseudoClassSelector = __decorate([
    FunctionalPseudoClassProperties(-1 /* Specificity.SelectorListHighest */, 0 /* Rarity.PseudoClass */, 1 /* PseudoClassSelectorList.Forgiving */)
], IsFunctionalPseudoClassSelector);
export { IsFunctionalPseudoClassSelector };
let WhereFunctionalPseudoClassSelector = class WhereFunctionalPseudoClassSelector extends FunctionalPseudoClassSelector {
    match(node) {
        return this.selectors.some((sel) => sel.match(node));
    }
    lookupSort(sorter, base) {
        // A faster lookup can be performed when selector list contains just a single selector
        if (this.selectors.length === 1) {
            this.selectors[0].lookupSort(sorter, base || this);
        }
        else {
            super.lookupSort(sorter, base || this);
        }
    }
};
WhereFunctionalPseudoClassSelector = __decorate([
    FunctionalPseudoClassProperties(0 /* Specificity.Zero */, 0 /* Rarity.PseudoClass */, 1 /* PseudoClassSelectorList.Forgiving */)
], WhereFunctionalPseudoClassSelector);
export { WhereFunctionalPseudoClassSelector };
export class SimpleSelectorSequence extends SimpleSelector {
    constructor(selectors) {
        super();
        this.selectors = selectors;
        this.specificity = selectors.reduce((sum, sel) => sel.specificity + sum, 0);
        this.head = selectors.reduce((prev, curr) => (!prev || curr.rarity > prev.rarity ? curr : prev), null);
        this.dynamic = selectors.some((sel) => sel.dynamic);
        this.hasAdjacentCombinator = selectors.some((sel) => sel.hasAdjacentCombinator);
        this.hasSiblingCombinator = selectors.some((sel) => sel.hasSiblingCombinator);
    }
    toString() {
        return `${this.selectors.join('')}${wrap(this.combinator)}`;
    }
    match(node) {
        const selectors = this.selectors;
        for (let i = 0, length = selectors.length; i < length; i++) {
            if (!selectors[i].match(node)) {
                return false;
            }
        }
        return true;
    }
    mayMatch(node) {
        const selectors = this.selectors;
        for (let i = 0, length = selectors.length; i < length; i++) {
            if (!selectors[i].mayMatch(node)) {
                return false;
            }
        }
        return true;
    }
    trackChanges(node, map) {
        const selectors = this.selectors;
        for (let i = 0, length = selectors.length; i < length; i++) {
            selectors[i].trackChanges(node, map);
        }
    }
    lookupSort(sorter, base) {
        this.head.lookupSort(sorter, base || this);
    }
}
export class ComplexSelector extends SelectorCore {
    constructor(selectors) {
        super();
        this.selectors = selectors;
        let siblingsToGroup;
        let currentGroup;
        const groups = [];
        this.specificity = 0;
        this.dynamic = false;
        this.hasAdjacentCombinator = false;
        this.hasSiblingCombinator = false;
        for (let i = selectors.length - 1; i >= 0; i--) {
            const sel = selectors[i];
            switch (sel.combinator) {
                case undefined:
                case Combinator.descendant:
                    siblingsToGroup = [];
                    currentGroup = [siblingsToGroup];
                    groups.push(currentGroup);
                    break;
                case Combinator.child:
                    siblingsToGroup = [];
                    currentGroup.push(siblingsToGroup);
                    break;
                case Combinator.adjacent:
                    this.hasAdjacentCombinator = true;
                    break;
                case Combinator.sibling:
                    this.hasSiblingCombinator = true;
                    break;
                default:
                    throw new Error(`Unsupported combinator "${sel.combinator}" for selector ${sel}.`);
            }
            this.specificity += sel.specificity;
            if (sel.dynamic) {
                this.dynamic = true;
            }
            if (sel.hasAdjacentCombinator) {
                this.hasAdjacentCombinator = true;
            }
            if (sel.hasSiblingCombinator) {
                this.hasSiblingCombinator = true;
            }
            siblingsToGroup.push(sel);
        }
        this.groups = groups.map((g) => new Selector.ChildGroup(g.map((selectors) => (selectors.length > 1 ? new Selector.SiblingGroup(selectors) : selectors[0]))));
        this.last = selectors[selectors.length - 1];
    }
    toString() {
        return this.selectors.join('');
    }
    match(node) {
        const groups = this.groups;
        for (let i = 0, length = groups.length; i < length; i++) {
            const group = groups[i];
            if (i === 0) {
                node = group.getMatchingNode(node, true);
                if (!node) {
                    return false;
                }
            }
            else {
                let ancestor = node;
                let matched = false;
                while ((ancestor = ancestor.parent ?? ancestor._modalParent)) {
                    if ((node = group.getMatchingNode(ancestor, true))) {
                        matched = true;
                        break;
                    }
                }
                if (!matched) {
                    return false;
                }
            }
        }
        return true;
    }
    mayMatch(node) {
        return false;
    }
    trackChanges(node, map) {
        const selectors = this.selectors;
        for (let i = 0, length = selectors.length; i < length; i++) {
            selectors[i].trackChanges(node, map);
        }
    }
    lookupSort(sorter, base) {
        this.last.lookupSort(sorter, base || this);
    }
    accumulateChanges(node, map) {
        if (!this.dynamic) {
            return this.match(node);
        }
        const bounds = [];
        const mayMatch = this.groups.every((group, i) => {
            if (i === 0) {
                const nextNode = group.getMatchingNode(node, false);
                bounds.push({ left: node, right: node });
                node = nextNode;
                return !!node;
            }
            else {
                let ancestor = node;
                while ((ancestor = ancestor.parent)) {
                    const nextNode = group.getMatchingNode(ancestor, false);
                    if (nextNode) {
                        bounds.push({ left: ancestor, right: null });
                        node = nextNode;
                        return true;
                    }
                }
                return false;
            }
        });
        // Calculating the right bounds for each selectors won't save much
        if (!mayMatch) {
            return false;
        }
        if (!map) {
            return mayMatch;
        }
        for (let i = 0; i < this.groups.length; i++) {
            const group = this.groups[i];
            if (!group.dynamic) {
                continue;
            }
            const bound = bounds[i];
            let node = bound.left;
            do {
                if (group.mayMatch(node)) {
                    group.trackChanges(node, map);
                }
            } while (node !== bound.right && (node = node.parent));
        }
        return mayMatch;
    }
}
export var Selector;
(function (Selector) {
    // Non-spec. Selector sequences are grouped by ancestor then by child combinators for easier backtracking.
    class ChildGroup extends SelectorBase {
        constructor(selectors) {
            super();
            this.selectors = selectors;
            this.dynamic = selectors.some((sel) => sel.dynamic);
        }
        getMatchingNode(node, strict) {
            const selectors = this.selectors;
            for (let i = 0, length = selectors.length; i < length; i++) {
                if (i !== 0) {
                    node = node.parent;
                }
                if (!node) {
                    return null;
                }
                const sel = selectors[i];
                if (!(strict ? sel.match(node) : sel.mayMatch(node))) {
                    return null;
                }
            }
            return node;
        }
        match(node) {
            return this.getMatchingNode(node, true) != null;
        }
        mayMatch(node) {
            return this.getMatchingNode(node, false) != null;
        }
        trackChanges(node, map) {
            this.selectors.forEach((sel, i) => {
                if (i === 0) {
                    node && sel.trackChanges(node, map);
                }
                else {
                    node = node.parent;
                    if (node && sel.mayMatch(node)) {
                        sel.trackChanges(node, map);
                    }
                }
            });
        }
    }
    Selector.ChildGroup = ChildGroup;
    class SiblingGroup extends SelectorBase {
        constructor(selectors) {
            super();
            this.selectors = selectors;
            this.dynamic = selectors.some((sel) => sel.dynamic);
        }
        match(node) {
            return this.selectors.every((sel, i) => {
                if (i === 0) {
                    return node && sel.match(node);
                }
                if (sel.combinator === Combinator.adjacent) {
                    node = getNodePreviousDirectSibling(node);
                    return node && sel.match(node);
                }
                // Sibling combinator
                let isMatching = false;
                eachNodePreviousGeneralSibling(node, (sibling) => {
                    isMatching = sel.match(sibling);
                    return !isMatching;
                });
                return isMatching;
            });
        }
        mayMatch(node) {
            return this.selectors.every((sel, i) => {
                if (i === 0) {
                    return node && sel.mayMatch(node);
                }
                if (sel.combinator === Combinator.adjacent) {
                    node = getNodePreviousDirectSibling(node);
                    return node && sel.mayMatch(node);
                }
                // Sibling combinator
                let isMatching = false;
                eachNodePreviousGeneralSibling(node, (sibling) => {
                    isMatching = sel.mayMatch(sibling);
                    return !isMatching;
                });
                return isMatching;
            });
        }
        trackChanges(node, map) {
            this.selectors.forEach((sel, i) => {
                if (i === 0) {
                    if (node) {
                        sel.trackChanges(node, map);
                    }
                }
                else {
                    if (sel.combinator === Combinator.adjacent) {
                        node = getNodePreviousDirectSibling(node);
                        if (node && sel.mayMatch(node)) {
                            sel.trackChanges(node, map);
                        }
                    }
                    else {
                        // Sibling combinator
                        let matchingSibling;
                        eachNodePreviousGeneralSibling(node, (sibling) => {
                            const isMatching = sel.mayMatch(sibling);
                            if (isMatching) {
                                matchingSibling = sibling;
                            }
                            return !isMatching;
                        });
                        if (matchingSibling) {
                            sel.trackChanges(matchingSibling, map);
                        }
                    }
                }
            });
        }
    }
    Selector.SiblingGroup = SiblingGroup;
})(Selector || (Selector = {}));
export class RuleSet {
    constructor(selectors, declarations) {
        this.selectors = selectors;
        this.declarations = declarations;
        this.selectors.forEach((sel) => (sel.ruleset = this));
    }
    toString() {
        let desc = `${this.selectors.join(', ')} {${this.declarations.map((d, i) => `${i === 0 ? ' ' : ''}${d.property}: ${d.value}`).join('; ')} }`;
        if (this.mediaQueryString) {
            desc = `@media ${this.mediaQueryString} { ${desc} }`;
        }
        return desc;
    }
    lookupSort(sorter) {
        this.selectors.forEach((sel) => sel.lookupSort(sorter));
    }
}
export function fromAstNode(astRule) {
    const declarations = [];
    const nodes = astRule.declarations;
    for (let i = 0, length = nodes.length; i < length; i++) {
        const node = nodes[i];
        if (isDeclaration(node)) {
            appendDeclaration(declarations, node);
        }
    }
    const selectors = astRule.selectors.map(createSelector);
    return new RuleSet(selectors, declarations);
}
function appendDeclaration(declarations, decl) {
    const property = isCssVariable(decl.property) ? decl.property : decl.property.toLowerCase();
    const value = cleanupImportantFlags(decl.value, decl.property);
    // The cascade is defined on longhands: a shorthand declares each of its
    // longhands in its place, so it is expanded here to keep source order meaningful.
    const expanded = _expandCssShorthand(property, value);
    if (expanded) {
        for (let i = 0, length = expanded.length; i < length; i++) {
            declarations.push({ property: expanded[i][0], value: expanded[i][1] });
        }
        return;
    }
    // A var()/calc() shorthand cannot be expanded yet - cascade one
    // pending-substitution value per longhand instead.
    const pending = _pendingCssShorthandSubstitution(property, value);
    if (pending) {
        for (let i = 0, length = pending.length; i < length; i++) {
            declarations.push({ property: pending[i][0], value: pending[i][1] });
        }
        return;
    }
    declarations.push({ property, value });
}
function createSimpleSelectorFromAst(ast) {
    if (ast.type === 'attribute') {
        if (ast.name === 'class') {
            return new ClassSelector(ast.value);
        }
        if (ast.name === 'id') {
            return new IdSelector(ast.value);
        }
        return new AttributeSelector(ast.name, ast.action, ast.value, !!ast.ignoreCase);
    }
    if (ast.type === 'tag') {
        return new TypeSelector(ast.name.replace('-', '').toLowerCase());
    }
    if (ast.type === 'pseudo') {
        if (ast.name === 'is') {
            return new IsFunctionalPseudoClassSelector(ast.name, ast.data);
        }
        if (ast.name === 'where') {
            return new WhereFunctionalPseudoClassSelector(ast.name, ast.data);
        }
        if (ast.name === 'not') {
            return new NotFunctionalPseudoClassSelector(ast.name, ast.data);
        }
        return new PseudoClassSelector(ast.name);
    }
    if (ast.type === 'universal') {
        return new UniversalSelector();
    }
    return new InvalidSelector(new Error(ast.type));
}
function createSimpleSelectorSequenceFromAst(asts) {
    if (asts.length === 0) {
        return new InvalidSelector(new Error('Empty simple selector sequence.'));
    }
    if (asts.length === 1) {
        return createSimpleSelectorFromAst(asts[0]);
    }
    const sequenceSelectors = [];
    for (const ast of asts) {
        const selector = createSimpleSelectorFromAst(ast);
        if (selector instanceof InvalidSelector) {
            return selector;
        }
        sequenceSelectors.push(selector);
    }
    return new SimpleSelectorSequence(sequenceSelectors);
}
function createSelectorFromAst(asts) {
    let result;
    if (asts.length === 0) {
        return new InvalidSelector(new Error('Empty selector.'));
    }
    if (asts.length === 1) {
        return createSimpleSelectorFromAst(asts[0]);
    }
    const simpleSelectorSequences = [];
    let sequenceAsts = [];
    let combinatorCount = 0;
    for (const ast of asts) {
        const combinator = Combinator[ast.type];
        // Combinator means the end of a sequence
        if (combinator != null) {
            const selector = createSimpleSelectorSequenceFromAst(sequenceAsts);
            if (selector instanceof InvalidSelector) {
                return selector;
            }
            selector.combinator = combinator;
            simpleSelectorSequences.push(selector);
            combinatorCount++;
            // Cleanup stored selectors for the new sequence to take place
            sequenceAsts = [];
        }
        else {
            sequenceAsts.push(ast);
        }
    }
    if (combinatorCount > 0) {
        // Create a sequence using the remaining selectors after the last combinator
        if (sequenceAsts.length) {
            const selector = createSimpleSelectorSequenceFromAst(sequenceAsts);
            if (selector instanceof InvalidSelector) {
                return selector;
            }
            simpleSelectorSequences.push(selector);
        }
        return new ComplexSelector(simpleSelectorSequences);
    }
    return createSimpleSelectorSequenceFromAst(sequenceAsts);
}
export function createSelector(sel) {
    try {
        const result = convertToCSSWhatSelector(sel);
        if (!result?.length) {
            return new InvalidSelector(new Error('Empty selector'));
        }
        return createSelectorFromAst(result[0]);
    }
    catch (e) {
        return new InvalidSelector(e);
    }
}
function isDeclaration(node) {
    return node.type === 'declaration';
}
export function matchMediaQueryString(mediaQueryString, cachedQueries) {
    if (!mediaQueryString) {
        return false;
    }
    if (typeof mediaQueryString === 'string') {
        // Query has already been validated
        if (cachedQueries.includes(mediaQueryString)) {
            return true;
        }
        const result = checkIfMediaQueryMatches(mediaQueryString);
        if (result) {
            cachedQueries.push(mediaQueryString);
            return result;
        }
        return false;
    }
    for (let i = 0, length = mediaQueryString.length; i < length; i++) {
        const mq = mediaQueryString[i];
        // Query has already been validated
        if (cachedQueries.includes(mq)) {
            continue;
        }
        if (!checkIfMediaQueryMatches(mq)) {
            return false;
        }
        cachedQueries.push(mq);
    }
    return true;
}
function appendSelectorCandidates(candidates, selectors) {
    if (selectors) {
        for (let i = 0, length = selectors.length; i < length; i++) {
            candidates.push(selectors[i]);
        }
    }
}
export class SelectorScope {
    constructor() {
        this.id = {};
        this.class = {};
        this.type = {};
        this.universal = [];
        this.position = 0;
        this.tier = 0 /* SelectorTier.Application */;
        /**
         * True when any selector in the scope contains an adjacent sibling ('+') combinator.
         */
        this.hasAdjacentCombinatorSelectors = false;
        /**
         * True when any selector in the scope contains a general sibling ('~') combinator.
         */
        this.hasSiblingCombinatorSelectors = false;
    }
    getSelectorCandidates(node, candidates = []) {
        const { cssClasses, id, cssType } = node;
        appendSelectorCandidates(candidates, this.universal);
        if (id) {
            appendSelectorCandidates(candidates, this.id[id]);
        }
        if (cssType) {
            appendSelectorCandidates(candidates, this.type[cssType]);
        }
        if (cssClasses && cssClasses.size) {
            const classSelectors = this.class;
            for (const cssClass of cssClasses) {
                appendSelectorCandidates(candidates, classSelectors[cssClass]);
            }
        }
        return candidates;
    }
    sortById(id, sel) {
        this.addToMap(this.id, id, sel);
    }
    sortByClass(cssClass, sel) {
        this.addToMap(this.class, cssClass, sel);
    }
    sortByType(cssType, sel) {
        this.addToMap(this.type, cssType, sel);
    }
    sortAsUniversal(sel) {
        this.universal.push(this.makeDocSelector(sel));
    }
    addToMap(map, head, sel) {
        if (!map[head]) {
            map[head] = [];
        }
        map[head].push(this.makeDocSelector(sel));
    }
    makeDocSelector(sel) {
        if (sel.hasAdjacentCombinator) {
            this.hasAdjacentCombinatorSelectors = true;
        }
        if (sel.hasSiblingCombinator) {
            this.hasSiblingCombinatorSelectors = true;
        }
        sel.pos = this.position++;
        sel.tier = this.tier;
        return sel;
    }
}
export class MediaQuerySelectorScope extends SelectorScope {
    constructor(mediaQueryString, tier) {
        super();
        this._mediaQueryString = mediaQueryString;
        this.tier = tier;
    }
    get mediaQueryString() {
        return this._mediaQueryString;
    }
}
export class StyleSheetSelectorScope extends SelectorScope {
    constructor(rulesets, tier = 0 /* SelectorTier.Application */) {
        super();
        this.tier = tier;
        this.lookupRulesets(rulesets);
    }
    /**
     * Index rulesets added after this scope was built; the rules already indexed
     * keep their positions.
     */
    appendRulesets(rulesets, from) {
        this.lookupRulesets(rulesets, from);
    }
    createMediaQuerySelectorScope(mediaQueryString) {
        const selectorScope = new MediaQuerySelectorScope(mediaQueryString, this.tier);
        selectorScope.position = this.position;
        if (this.mediaQuerySelectorScopes) {
            this.mediaQuerySelectorScopes.push(selectorScope);
        }
        else {
            this.mediaQuerySelectorScopes = [selectorScope];
        }
        return selectorScope;
    }
    lookupRulesets(rulesets, from = 0) {
        let lastMediaSelectorScope;
        for (let i = from, length = rulesets.length; i < length; i++) {
            const ruleset = rulesets[i];
            if (lastMediaSelectorScope && lastMediaSelectorScope.mediaQueryString !== ruleset.mediaQueryString) {
                // Once done with current media query scope, update stylesheet scope position
                this.position = lastMediaSelectorScope.position;
                lastMediaSelectorScope = null;
            }
            if (ruleset.mediaQueryString) {
                // Create media query selector scope and register selector lookups there
                if (!lastMediaSelectorScope) {
                    lastMediaSelectorScope = this.createMediaQuerySelectorScope(ruleset.mediaQueryString);
                }
                ruleset.lookupSort(lastMediaSelectorScope);
            }
            else {
                ruleset.lookupSort(this);
            }
        }
        // If reference of last media selector scope is still kept, update stylesheet scope position
        if (lastMediaSelectorScope) {
            this.position = lastMediaSelectorScope.position;
            lastMediaSelectorScope = null;
        }
        // Media query scopes are queried through this scope, so their combinator flags roll up
        if (this.mediaQuerySelectorScopes) {
            for (const selectorScope of this.mediaQuerySelectorScopes) {
                if (selectorScope.hasAdjacentCombinatorSelectors) {
                    this.hasAdjacentCombinatorSelectors = true;
                }
                if (selectorScope.hasSiblingCombinatorSelectors) {
                    this.hasSiblingCombinatorSelectors = true;
                }
            }
        }
    }
    /**
     * Append every selector that could match the node, matching media query scopes
     * included, for `matchSelectorCandidates` to resolve.
     */
    collectCandidates(node, candidates = []) {
        this.getSelectorCandidates(node, candidates);
        // Validate media queries and include their selectors if needed
        if (this.mediaQuerySelectorScopes) {
            // Cache media query results to avoid validations of other identical queries
            const validatedMediaQueries = [];
            for (let i = 0, length = this.mediaQuerySelectorScopes.length; i < length; i++) {
                const selectorScope = this.mediaQuerySelectorScopes[i];
                const isMatchingAllQueries = matchMediaQueryString(selectorScope.mediaQueryString, validatedMediaQueries);
                if (isMatchingAllQueries) {
                    selectorScope.getSelectorCandidates(node, candidates);
                }
            }
        }
        return candidates;
    }
    query(node) {
        return matchSelectorCandidates(node, this.collectCandidates(node));
    }
}
/** Cascade order: specificity, then source order - (tier, position) across stylesheets. */
function compareSelectors(a, b) {
    return a.specificity - b.specificity || a.tier - b.tier || a.pos - b.pos;
}
/**
 * Resolve collected candidates against a node, compacting the array in place.
 * `scopedTags` filters out rules registered on behalf of a stylesheet this scope
 * never loaded; pass it only when such rules exist - it costs a lookup per candidate.
 */
export function matchSelectorCandidates(node, candidates, scopedTags) {
    const selectorsMatch = new SelectorsMatch();
    let matched = 0;
    for (let i = 0, length = candidates.length; i < length; i++) {
        const selector = candidates[i];
        if (scopedTags) {
            const scopedTag = selector.ruleset?.scopedTag;
            if (scopedTag && !scopedTags.has(scopedTag)) {
                continue;
            }
        }
        if (selector.accumulateChanges(node, selectorsMatch)) {
            candidates[matched++] = selector;
        }
    }
    candidates.length = matched;
    selectorsMatch.selectors = candidates.sort(compareSelectors);
    return selectorsMatch;
}
/** Shared by matches that track nothing; a real map is materialized on first write. */
const emptyChangeMap = new Map();
export class SelectorsMatch {
    constructor() {
        this.changeMap = emptyChangeMap;
    }
    addAttribute(node, attribute) {
        const deps = this.properties(node);
        if (!deps.attributes) {
            deps.attributes = new Set();
        }
        deps.attributes.add(attribute);
    }
    addPseudoClass(node, pseudoClass) {
        const deps = this.properties(node);
        if (!deps.pseudoClasses) {
            deps.pseudoClasses = new Set();
        }
        deps.pseudoClasses.add(pseudoClass);
    }
    properties(node) {
        let changeMap = this.changeMap;
        if (changeMap === emptyChangeMap) {
            this.changeMap = changeMap = new Map();
        }
        let set = changeMap.get(node);
        if (!set) {
            changeMap.set(node, (set = {}));
        }
        return set;
    }
}
export const CSSHelper = {
    createSelector,
    SelectorCore,
    SimpleSelector,
    InvalidSelector,
    UniversalSelector,
    TypeSelector,
    ClassSelector,
    AttributeSelector,
    PseudoClassSelector,
    SimpleSelectorSequence,
    Selector,
    RuleSet,
    SelectorScope,
    MediaQuerySelectorScope,
    StyleSheetSelectorScope,
    fromAstNode,
    SelectorsMatch,
    matchSelectorCandidates,
};
//# sourceMappingURL=css-selector.js.map