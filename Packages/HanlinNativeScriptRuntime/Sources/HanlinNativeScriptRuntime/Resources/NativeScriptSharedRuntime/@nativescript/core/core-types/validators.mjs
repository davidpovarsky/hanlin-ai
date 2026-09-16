// Utility functions for validation and parsing, shared between core-types and properties
export function makeValidator(...values) {
    return function (value) {
        return values.indexOf(value) !== -1;
    };
}
export function makeParser(isValid, allowNumbers = false) {
    return (value) => {
        const lower = value && value.toLowerCase();
        if (isValid(value)) {
            return value;
        }
        else if (isValid(lower)) {
            return lower;
        }
        else {
            if (allowNumbers) {
                const convNumber = +value;
                if (!isNaN(convNumber)) {
                    return value;
                }
            }
            throw new Error('Invalid value: ' + value);
        }
    };
}
//# sourceMappingURL=validators.js.map