import { Trace } from '../../trace';
import { _updateTransitions } from './fragment.transitions';
import { profile } from '../../profiling';
import { getNativeApp } from '../../application/helpers-common';
import { Color } from '../../color';
import { CALLBACKS, FRAMEID } from './frame-constants';
export { CALLBACKS, FRAMEID };
export const framesCache = new Array();
function findPageForFragment(fragment, frame) {
    const fragmentTag = fragment.getTag();
    if (Trace.isEnabled()) {
        Trace.write(`Finding page for ${fragmentTag}.`, Trace.categories.NativeLifecycle);
    }
    let entry;
    const current = frame._currentEntry;
    const executingContext = frame._executingContext;
    if (current && current.fragmentTag === fragmentTag) {
        entry = current;
    }
    else if (executingContext && executingContext.entry && executingContext.entry.fragmentTag === fragmentTag) {
        entry = executingContext.entry;
    }
    let page;
    if (entry) {
        entry.recreated = true;
        page = entry.resolvedPage;
    }
    if (page) {
        const callbacks = fragment[CALLBACKS];
        callbacks.frame = frame;
        callbacks.entry = entry;
        entry.fragment = fragment;
        _updateTransitions(entry);
    }
    else {
        throw new Error(`Could not find a page for ${fragmentTag}.`);
    }
}
export class FragmentCallbacksImplementation {
    constructor() {
        this.backgroundBitmap = null;
    }
    onHiddenChanged(fragment, hidden, superFunc) {
        if (Trace.isEnabled()) {
            Trace.write(`${fragment}.onHiddenChanged(${hidden})`, Trace.categories.NativeLifecycle);
        }
        superFunc.call(fragment, hidden);
    }
    onCreateAnimator(fragment, transit, enter, nextAnim, superFunc) {
        let animator = null;
        const entry = this.entry;
        // Return enterAnimator only when new (no current entry) nested transition.
        if (enter && entry.isNestedDefaultTransition) {
            animator = entry.enterAnimator;
            entry.isNestedDefaultTransition = false;
        }
        return animator || superFunc.call(fragment, transit, enter, nextAnim);
    }
    onCreate(fragment, savedInstanceState, superFunc) {
        if (Trace.isEnabled()) {
            Trace.write(`${fragment}.onCreate(${savedInstanceState})`, Trace.categories.NativeLifecycle);
        }
        superFunc.call(fragment, savedInstanceState);
        // There is no entry set to the fragment, so this must be destroyed fragment that was recreated by Android.
        // We should find its corresponding page in our backstack and set it manually.
        if (!this.entry) {
            const args = fragment.getArguments();
            const frameId = args.getInt(FRAMEID);
            const frame = getFrameByNumberId(frameId);
            if (!frame) {
                throw new Error(`Cannot find Frame for ${fragment}`);
            }
            findPageForFragment(fragment, frame);
        }
    }
    onCreateView(fragment, inflater, container, savedInstanceState, superFunc) {
        if (Trace.isEnabled()) {
            Trace.write(`${fragment}.onCreateView(inflater, container, ${savedInstanceState})`, Trace.categories.NativeLifecycle);
        }
        const entry = this.entry;
        if (!entry) {
            // Recoverable race: a stale fragment is being driven to onCreateView by the
            // FragmentManager after its entry was cleared.
            // Using Trace.error (routes to an error handler, which throws) would be fatal as the error handler rethrows across the JNI boundary.
            // Trace.write(..., Trace.messageType.error) logs without routing through that throwing path.
            Trace.write(`${fragment}.onCreateView: entry is null or undefined`, Trace.categories.NativeLifecycle, Trace.messageType.error);
            return null;
        }
        const page = entry.resolvedPage;
        if (!page) {
            // Logging via Trace.error (routes to an error handler, which throws) here is fatal because the registered error handler rethrows across the JNI boundary.
            // Trace.write(..., Trace.messageType.error) keeps this recoverable path non-fatal.
            Trace.write(`${fragment}.onCreateView: entry has no resolvedPage`, Trace.categories.NativeLifecycle, Trace.messageType.error);
            return null;
        }
        const frame = this.frame;
        if (!frame) {
            // Recoverable race: the owning frame was already torn down. Returning null discards
            // this fragment; using Trace.error (routes to an error handler, which throws) would be fatal as the error handler rethrows across the JNI boundary.
            // Trace.write(..., Trace.messageType.error) logs without invoking the throwing error handler.
            Trace.write(`${fragment}.onCreateView: this.frame is null or undefined`, Trace.categories.NativeLifecycle, Trace.messageType.error);
            return null;
        }
        frame._resolvedPage = page;
        // @ts-ignore
        if (page.parent === frame) {
            frame._inheritStyles(page);
            // If we are navigating to a page that was destroyed
            // reinitialize its UI.
            if (!page._context) {
                const context = (container && container.getContext()) || (inflater && inflater.getContext());
                page._setupUI(context);
            }
            if (frame.isLoaded && !page.isLoaded) {
                page.callLoaded();
            }
        }
        else {
            if (!page.parent) {
                if (!frame._styleScope) {
                    // Make sure page will have styleScope even if parents don't.
                    page._updateStyleScope();
                }
                frame._addView(page);
            }
            else {
                throw new Error('Page is already shown on another frame.');
            }
        }
        const savedState = entry.viewSavedState;
        if (savedState) {
            page.nativeViewProtected.restoreHierarchyState(savedState);
            entry.viewSavedState = null;
        }
        // fixes 'java.lang.IllegalStateException: The specified child already has a parent. You must call removeView() on the child's parent first'.
        // on app resume in nested frame scenarios with support library version greater than 26.0.0
        // HACK: this whole code block shouldn't be necessary as the native view is supposedly removed from its parent
        // right after onDestroyView(...) is called but for some reason the fragment view (page) still thinks it has a
        // parent while its supposed parent believes it properly removed its children; in order to "force" the child to
        // lose its parent we temporarily add it to the parent, and then remove it (addViewInLayout doesn't trigger layout pass)
        const nativeView = page.nativeViewProtected;
        if (nativeView != null) {
            const parentView = nativeView.getParent();
            if (parentView instanceof android.view.ViewGroup) {
                if (parentView.getChildCount() === 0) {
                    parentView.addViewInLayout(nativeView, -1, new org.nativescript.widgets.CommonLayoutParams());
                }
                parentView.removeAllViews();
            }
        }
        return page.nativeViewProtected;
    }
    onSaveInstanceState(fragment, outState, superFunc) {
        if (Trace.isEnabled()) {
            Trace.write(`${fragment}.onSaveInstanceState(${outState})`, Trace.categories.NativeLifecycle);
        }
        superFunc.call(fragment, outState);
    }
    onDestroyView(fragment, superFunc) {
        try {
            if (Trace.isEnabled()) {
                Trace.write(`${fragment}.onDestroyView()`, Trace.categories.NativeLifecycle);
            }
            const hasRemovingParent = fragment.getRemovingParentFragment();
            if (hasRemovingParent) {
                const nativeFrameView = this.frame.nativeViewProtected;
                if (nativeFrameView) {
                    const bitmapDrawable = new android.graphics.drawable.BitmapDrawable(getNativeApp().getApplicationContext().getResources(), this.backgroundBitmap);
                    this.frame._originalBackground = this.frame.backgroundColor || new Color('White');
                    nativeFrameView.setBackgroundDrawable(bitmapDrawable);
                    this.backgroundBitmap = null;
                }
            }
        }
        finally {
            superFunc.call(fragment);
        }
    }
    onDestroy(fragment, superFunc) {
        if (Trace.isEnabled()) {
            Trace.write(`${fragment}.onDestroy()`, Trace.categories.NativeLifecycle);
        }
        superFunc.call(fragment);
        const entry = this.entry;
        if (!entry) {
            Trace.error(`${fragment}.onDestroy: entry is null or undefined`);
            return null;
        }
        // Check if entry fragment is still this fragment as the destroy lifecycle might have been called due to replace
        if (entry.fragment === fragment) {
            // [nested frames / fragments] see https://github.com/NativeScript/NativeScript/issues/6629
            // retaining reference to a destroyed fragment here somehow causes a cryptic
            // "IllegalStateException: Failure saving state: active fragment has cleared index: -1"
            // in a specific mixed parent / nested frame navigation scenario
            entry.fragment = null;
        }
        const page = entry.resolvedPage;
        if (!page) {
            // todo: check why this happens when using shared element transition!!!
            // commented out the Trace.error to prevent a crash (the app will still work interestingly)
            console.log(`${fragment}.onDestroy: entry has no resolvedPage`);
            // Trace.error(`${fragment}.onDestroy: entry has no resolvedPage`);
            return null;
        }
    }
    onPause(fragment, superFunc) {
        try {
            // Get view as bitmap and set it as background. This is workaround for the disapearing nested fragments.
            // TODO: Consider removing it when update to androidx.fragment:1.2.0
            const hasRemovingParent = fragment.getRemovingParentFragment();
            if (hasRemovingParent) {
                this.backgroundBitmap = this.loadBitmapFromView(this.frame.nativeViewProtected);
            }
        }
        finally {
            superFunc.call(fragment);
        }
    }
    onResume(fragment, superFunc) {
        const frame = this.entry.resolvedPage.frame;
        // on some cases during the first navigation on nested frames the animation doesn't trigger
        // we depend on the animation (even None animation) to set the entry as the current entry
        // animation should start between start and resume, so if we have an executing navigation here it probably means the animation was skipped
        // so we manually set the entry
        // also, to be compatible with fragments 1.2.x we need this setTimeout as animations haven't run on onResume yet
        const weakRef = new WeakRef(this);
        setTimeout(() => {
            const owner = weakRef.get();
            if (!owner) {
                return;
            }
            if (!owner.entry.isAnimationRunning) {
                if (frame._executingContext) {
                    frame.setCurrent(owner.entry, frame._executingContext.navigationType);
                }
                else {
                    // Restore cached animation settings if we just completed simulated first navigation (no animation)
                    frame._restoreTransitionState?.();
                }
            }
        }, 0);
        superFunc.call(fragment);
    }
    onStop(fragment, superFunc) {
        superFunc.call(fragment);
    }
    toStringOverride(fragment, superFunc) {
        const entry = this.entry;
        if (entry) {
            return `${entry.fragmentTag}<${entry.resolvedPage}>`;
        }
        else {
            return 'NO ENTRY, ' + superFunc.call(fragment);
        }
    }
    loadBitmapFromView(view) {
        // Don't try to create bitmaps with no dimensions as this causes a crash
        // This might happen when showing and closing dialogs fast.
        if (!(view && view.getWidth() > 0 && view.getHeight() > 0)) {
            return undefined;
        }
        // Another way to get view bitmap. Test performance vs setDrawingCacheEnabled
        // const width = view.getWidth();
        // const height = view.getHeight();
        // const bitmap = android.graphics.Bitmap.createBitmap(width, height, android.graphics.Bitmap.Config.ARGB_8888);
        // const canvas = new android.graphics.Canvas(bitmap);
        // view.layout(0, 0, width, height);
        // view.draw(canvas);
        // view.setDrawingCacheEnabled(true);
        // const drawCache = view.getDrawingCache();
        // const bitmap = android.graphics.Bitmap.createBitmap(drawCache);
        // view.setDrawingCacheEnabled(false);
        return org.nativescript.widgets.Utils.getBitmapFromView(view);
    }
}
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, Boolean, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onHiddenChanged", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, Number, Boolean, Number, Function]),
    __metadata("design:returntype", android.animation.Animator)
], FragmentCallbacksImplementation.prototype, "onCreateAnimator", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, android.os.Bundle, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onCreate", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, android.view.LayoutInflater, android.view.ViewGroup, android.os.Bundle, Function]),
    __metadata("design:returntype", android.view.View)
], FragmentCallbacksImplementation.prototype, "onCreateView", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, android.os.Bundle, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onSaveInstanceState", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [org.nativescript.widgets.FragmentBase, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onDestroyView", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onDestroy", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [org.nativescript.widgets.FragmentBase, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onPause", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [org.nativescript.widgets.FragmentBase, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onResume", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, Function]),
    __metadata("design:returntype", void 0)
], FragmentCallbacksImplementation.prototype, "onStop", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [androidx.fragment.app.Fragment, Function]),
    __metadata("design:returntype", String)
], FragmentCallbacksImplementation.prototype, "toStringOverride", null);
export function getFrameByNumberId(frameId) {
    // Find the frame for this activity.
    for (let i = 0, length = framesCache.length; i < length; i++) {
        const aliveFrame = framesCache[i].get();
        if (aliveFrame && aliveFrame.frameId === frameId) {
            return aliveFrame.owner;
        }
    }
    return null;
}
export function setFragmentCallbacks(fragment) {
    fragment[CALLBACKS] = new FragmentCallbacksImplementation();
}
//# sourceMappingURL=frame-helper-for-android.js.map