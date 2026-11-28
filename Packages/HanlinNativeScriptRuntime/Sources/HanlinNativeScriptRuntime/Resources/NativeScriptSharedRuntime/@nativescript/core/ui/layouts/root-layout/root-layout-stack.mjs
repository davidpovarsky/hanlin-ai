const rootLayoutStack = [];
export function _findRootLayoutById(id) {
    return rootLayoutStack.find((rootLayout) => rootLayout.id && rootLayout.id === id);
}
export function _pushIntoRootLayoutStack(rootLayout) {
    if (!rootLayoutStack.includes(rootLayout)) {
        rootLayoutStack.push(rootLayout);
    }
}
export function _removeFromRootLayoutStack(rootLayout) {
    const index = rootLayoutStack.indexOf(rootLayout);
    if (index > -1) {
        rootLayoutStack.splice(index, 1);
    }
}
export function _geRootLayoutFromStack(index) {
    return rootLayoutStack.length > index ? rootLayoutStack[index] : null;
}
//# sourceMappingURL=root-layout-stack.js.map