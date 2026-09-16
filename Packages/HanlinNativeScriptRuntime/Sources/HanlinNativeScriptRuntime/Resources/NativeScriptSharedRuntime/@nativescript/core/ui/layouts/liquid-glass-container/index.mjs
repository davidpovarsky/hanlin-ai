import { supportsGlass } from '../../../utils/constants';
import { iosGlassEffectProperty } from '../../core/view';
import { LiquidGlassContainerCommon } from './liquid-glass-container-common';
import { toUIGlassStyle } from '../liquid-glass';
export class LiquidGlassContainer extends LiquidGlassContainerCommon {
    constructor() {
        super(...arguments);
        this._normalizing = false;
    }
    createNativeView() {
        const glassSupported = supportsGlass();
        // Keep UIVisualEffectView as the root to preserve interactive container effect
        const effect = glassSupported ? UIGlassContainerEffect.alloc().init() : UIVisualEffect.new();
        if (glassSupported) {
            effect.spacing = 8;
        }
        const effectView = UIVisualEffectView.alloc().initWithEffect(effect);
        if (glassSupported) {
            effectView.overrideUserInterfaceStyle = 2 /* UIUserInterfaceStyle.Dark */;
        }
        effectView.clipsToBounds = true;
        effectView.autoresizingMask = 2 /* UIViewAutoresizing.FlexibleWidth */ | 16 /* UIViewAutoresizing.FlexibleHeight */;
        // Add a host view for children so parent can lay them out normally
        const host = UIView.new();
        host.frame = effectView.bounds;
        host.autoresizingMask = 2 /* UIViewAutoresizing.FlexibleWidth */ | 16 /* UIViewAutoresizing.FlexibleHeight */;
        host.userInteractionEnabled = true;
        effectView.contentView.addSubview(host);
        this._contentHost = host;
        return effectView;
    }
    _addViewToNativeVisualTree(child, atIndex) {
        const parentNativeView = this._contentHost;
        const childNativeView = child.nativeViewProtected;
        if (parentNativeView && childNativeView) {
            if (typeof atIndex !== 'number' || atIndex >= parentNativeView.subviews.count) {
                parentNativeView.addSubview(childNativeView);
            }
            else {
                parentNativeView.insertSubviewAtIndex(childNativeView, atIndex);
            }
            // Add outer shadow layer manually as it belongs to parent layer tree (this is needed for reusable views)
            if (childNativeView.outerShadowContainerLayer && !childNativeView.outerShadowContainerLayer.superlayer) {
                this.nativeViewProtected.layer.insertSublayerBelow(childNativeView.outerShadowContainerLayer, childNativeView.layer);
            }
            // Normalize in case the child comes in with a residual translate from a previous state
            this._scheduleNormalize();
            return true;
        }
        return false;
    }
    // When LiquidGlassContainer is a child of FlexboxLayout (or any layout that passes
    // a measure spec already reduced by the child's padding), AbsoluteLayout.onMeasure
    // would subtract our padding a second time. To prevent this double-deduction we
    // temporarily zero the effective padding/border values before delegating to the
    // AbsoluteLayout measurement, then restore them immediately after.
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        const pl = this.effectivePaddingLeft;
        const pr = this.effectivePaddingRight;
        const pt = this.effectivePaddingTop;
        const pb = this.effectivePaddingBottom;
        const bl = this.effectiveBorderLeftWidth;
        const br = this.effectiveBorderRightWidth;
        const bt = this.effectiveBorderTopWidth;
        const bb = this.effectiveBorderBottomWidth;
        this.effectivePaddingLeft = 0;
        this.effectivePaddingRight = 0;
        this.effectivePaddingTop = 0;
        this.effectivePaddingBottom = 0;
        this.effectiveBorderLeftWidth = 0;
        this.effectiveBorderRightWidth = 0;
        this.effectiveBorderTopWidth = 0;
        this.effectiveBorderBottomWidth = 0;
        try {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec);
        }
        finally {
            this.effectivePaddingLeft = pl;
            this.effectivePaddingRight = pr;
            this.effectivePaddingTop = pt;
            this.effectivePaddingBottom = pb;
            this.effectiveBorderLeftWidth = bl;
            this.effectiveBorderRightWidth = br;
            this.effectiveBorderTopWidth = bt;
            this.effectiveBorderBottomWidth = bb;
        }
    }
    // When children animate with translate (layer transform), UIVisualEffectView-based
    // container effects may recompute based on the underlying frames (not transforms),
    // which can cause jumps. Normalize any residual translation into the
    // child's frame so the effect uses the final visual positions.
    onLayout(left, top, right, bottom) {
        // AbsoluteLayout.onLayout positions children using our padding as an offset.
        // Since the FlexboxLayout (or parent) already placed our UIVisualEffectView at
        // (left, top), we normalise to local coordinates so that AbsoluteLayout places
        // children in (0, 0, width, height) space — the coordinate space of _contentHost.
        super.onLayout(0, 0, right - left, bottom - top);
        // Try to fold any pending translates into frames on each layout pass
        this._normalizeChildrenTransforms();
    }
    // Allow callers to stabilize layout after custom animations
    stabilizeLayout() {
        this._normalizeChildrenTransforms(true);
    }
    _scheduleNormalize() {
        if (this._normalizing)
            return;
        this._normalizing = true;
        // Next tick to allow any pending frame/transform updates to settle
        setTimeout(() => {
            try {
                this._normalizeChildrenTransforms();
            }
            finally {
                this._normalizing = false;
            }
        });
    }
    _normalizeChildrenTransforms(force = false) {
        let changed = false;
        const count = this.getChildrenCount?.() ?? 0;
        for (let i = 0; i < count; i++) {
            const child = this.getChildAt(i);
            if (!child)
                continue;
            const tx = child.translateX || 0;
            const ty = child.translateY || 0;
            if (!tx && !ty)
                continue;
            const native = child.nativeViewProtected;
            if (!native)
                continue;
            // Skip if the child is still animating (unless forced)
            if (!force) {
                const keys = native.layer.animationKeys ? native.layer.animationKeys() : null;
                const hasAnimations = !!(keys && keys.count > 0);
                if (hasAnimations)
                    continue;
            }
            const frame = native.frame;
            native.transform = CGAffineTransformIdentity;
            native.frame = CGRectMake(frame.origin.x + tx, frame.origin.y + ty, frame.size.width, frame.size.height);
            child.translateX = 0;
            child.translateY = 0;
            changed = true;
        }
        if (changed) {
            // Ask the effect view to re-evaluate its internal state using updated frames
            const nv = this.nativeViewProtected;
            if (nv) {
                nv.setNeedsLayout();
                nv.layoutIfNeeded();
                // Also request layout on contentView in case the effect inspects it directly
                nv.contentView?.setNeedsLayout?.();
                nv.contentView?.layoutIfNeeded?.();
            }
        }
    }
    [iosGlassEffectProperty.setNative](value) {
        this._applyGlassEffect(value, {
            effectType: 'container',
            targetView: this.nativeViewProtected,
            toGlassStyleFn: toUIGlassStyle,
        });
    }
}
//# sourceMappingURL=index.ios.js.map