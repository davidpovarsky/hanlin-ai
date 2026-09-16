export class ClipPathFunction {
    constructor(shape, rule) {
        this._shape = shape;
        this._rule = rule;
    }
    get shape() {
        return this._shape;
    }
    get rule() {
        return this._rule;
    }
    static equals(value1, value2) {
        return value1.shape === value2.shape && value1.rule === value2.rule;
    }
    toJSON() {
        return {
            shape: this._shape,
            rule: this._rule,
        };
    }
    toString() {
        return `${this._shape}(${this._rule})`;
    }
}
//# sourceMappingURL=clip-path-function.js.map