/**
 * Parse a string into an array of tokens.
 */
export function parse(str) {
    return new Parser(str).parse();
}
class Parser {
    constructor(str) {
        this.str = str;
    }
    skip(match) {
        this.str = this.str.slice(match[0].length);
    }
    /** Comma tokens: "," */
    comma() {
        const m = /^, */.exec(this.str);
        if (!m)
            return;
        this.skip(m);
        return { type: 'comma', string: ',' };
    }
    /** Identifier tokens: word or dash sequences */
    ident() {
        const m = /^([\w-]+) */.exec(this.str);
        if (!m)
            return;
        this.skip(m);
        return { type: 'ident', string: m[1] };
    }
    /** Integer tokens, possibly with unit */
    int() {
        const m = /^(([-+]?\d+)(\S+)?) */.exec(this.str);
        if (!m)
            return;
        this.skip(m);
        const n = parseInt(m[2], 10);
        const u = m[3] || '';
        return { type: 'number', string: m[1], unit: u, value: n };
    }
    /** Float tokens, possibly with unit */
    float() {
        const m = /^(((?:[-+]?\d+)?\.\d+)(\S+)?) */.exec(this.str);
        if (!m)
            return;
        this.skip(m);
        const n = parseFloat(m[2]);
        const u = m[3] || '';
        return { type: 'number', string: m[1], unit: u, value: n };
    }
    /** Number tokens, either float or int */
    number() {
        return this.float() || this.int();
    }
    /** Double-quoted strings */
    double() {
        const m = /^"([^"]*)" */.exec(this.str);
        if (!m)
            return;
        this.skip(m);
        return { type: 'string', quote: '"', string: `"${m[1]}"`, value: m[1] };
    }
    /** Single-quoted strings */
    single() {
        const m = /^'([^']*)' */.exec(this.str);
        if (!m)
            return;
        this.skip(m);
        return { type: 'string', quote: "'", string: `'${m[1]}'`, value: m[1] };
    }
    /** String tokens: single or double quoted */
    string() {
        return this.single() || this.double();
    }
    /** Attempt to parse any token */
    value() {
        return this.number() || this.ident() || this.string() || this.comma();
    }
    /** Run the full parse loop */
    parse() {
        const vals = [];
        while (this.str.length > 0) {
            const obj = this.value();
            if (!obj) {
                throw new Error(`failed to parse near \`${this.str.slice(0, 10)}...\``);
            }
            vals.push(obj);
        }
        return vals;
    }
}
//# sourceMappingURL=reworkcss-value.js.map