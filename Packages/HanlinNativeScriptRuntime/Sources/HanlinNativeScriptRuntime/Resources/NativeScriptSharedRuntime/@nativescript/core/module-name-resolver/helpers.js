let appForModuleResolverCallback;
export function prepareAppForModuleResolver(callback) {
    appForModuleResolverCallback = callback;
}
export function initAppForModuleResolver() {
    if (appForModuleResolverCallback) {
        appForModuleResolverCallback();
        appForModuleResolverCallback = undefined;
    }
}
let resolverInstance;
export function getResolveInstance() {
    return resolverInstance;
}
/**
 * Used to set a global singular instance of ModuleNameResolver
 * @param resolver instance
 */
export function _setResolver(resolver) {
    resolverInstance = resolver;
}
export function clearResolverCache() {
    if (resolverInstance) {
        resolverInstance.clearCache();
    }
}
//# sourceMappingURL=helpers.js.map