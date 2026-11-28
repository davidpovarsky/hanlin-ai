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
export function getDebugRequestMethodAndBody(options) {
    const method = typeof options.method === 'string' ? options.method : 'GET';
    if (typeof options.content === 'string') {
        return { method, postData: options.content };
    }
    if (options.content instanceof FormData) {
        return { method, postData: options.content.toString() };
    }
    return { method };
}
//# sourceMappingURL=http-request-internal-common.js.map