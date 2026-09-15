export function addHeader(headers, key, value) {
    if (!headers[key]) {
        headers[key] = value;
    }
    else if (Array.isArray(headers[key])) {
        headers[key].push(value);
    }
    else {
        headers[key] = [headers[key], value];
    }
}
//# sourceMappingURL=http-request-internal-common.js.map