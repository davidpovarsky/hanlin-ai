export function installPolyfillsFromModule(module, polyfills) {
    for (const polyfill of polyfills) {
        // `in` checks presence without reading the property — reading would force
        // runtime-provided lazy globals (e.g. TextDecoder) to materialize eagerly.
        if (!(polyfill in global)) {
            global[polyfill] = module[polyfill];
        }
    }
}
//# sourceMappingURL=utils.js.map