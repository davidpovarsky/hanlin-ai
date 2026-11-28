// stubs to avoid bundler warnings
export const updateContentDescription = (view /* View */, forceUpdate) => null;
export function applyContentDescription(view /* View */, forceUpdate) {
    return null;
}
export function androidGetCurrentActivity() { }
export function androidGetForegroundActivity() { }
export function androidSetForegroundActivity(activity) { }
export function androidGetStartActivity() { }
export function androidSetStartActivity(activity) { }
export function setupAccessibleView(view /* any */) {
    const uiView = view.nativeViewProtected;
    if (!uiView) {
        return;
    }
    /**
     * We need to map back from the UIView to the NativeScript View.
     *
     * We do that by setting the uiView's tag to the View's domId.
     * This way we can do reverse lookup.
     */
    uiView.tag = view._domId;
}
//# sourceMappingURL=helpers.ios.js.map