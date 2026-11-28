// Utility functions for view-base and related modules
export function booleanConverter(v) {
    if (typeof v === 'string') {
        v = v.trim().toLowerCase();
        return v === 'true' || v === '1';
    }
    return !!v;
}
//# sourceMappingURL=utils.js.map