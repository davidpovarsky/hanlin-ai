import { supportsGlass } from '../../../utils/constants';
import { iosGlassEffectProperty } from '../../core/view';
import { LiquidGlassCommon } from './liquid-glass-common';
export class LiquidGlass extends LiquidGlassCommon {
    createNativeView() {
        const glassSupported = supportsGlass();
        // Use UIVisualEffectView as the root so interactive effects can track touches
        const effect = glassSupported ? UIGlassEffect.effectWithStyle(toUIGlassStyle('clear')) : UIVisualEffect.new();
        if (glassSupported) {
            effect.interactive = true;
        }
        const effectView = UIVisualEffectView.alloc().initWithEffect(effect);
        effectView.frame = CGRectMake(0, 0, 0, 0);
        effectView.autoresizingMask = 2 /* UIViewAutoresizing.FlexibleWidth */ | 16 /* UIViewAutoresizing.FlexibleHeight */;
        effectView.clipsToBounds = true;
        // Host for all children so parent layout works as usual
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
            // If the child has an outer shadow layer, ensure it is attached under the child's layer
            if (childNativeView.outerShadowContainerLayer && !childNativeView.outerShadowContainerLayer.superlayer) {
                this.nativeViewProtected.layer.insertSublayerBelow(childNativeView.outerShadowContainerLayer, childNativeView.layer);
            }
            return true;
        }
        return false;
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        // When LiquidGlass is a child of FlexboxLayout (or any layout that passes a child
        // measure spec already reduced by the child's padding), GridLayout.onMeasure would
        // subtract our padding a second time. To prevent this double-deduction we temporarily
        // zero the effective padding/border values before delegating to the GridLayout
        // measurement, then restore them immediately after.
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
    onLayout(left, top, right, bottom) {
        // GridLayout.onLayout computes column/row offsets relative to (left, top), then
        // adds its own padding on top. Since the FlexboxLayout (or parent) already placed
        // our UIVisualEffectView at (left, top), we normalise to local coordinates so that
        // GridLayout lays children out in (0, 0, width, height) space — which is exactly
        // the coordinate space of our _contentHost UIView that hosts the children.
        super.onLayout(0, 0, right - left, bottom - top);
    }
    [iosGlassEffectProperty.setNative](value) {
        this._applyGlassEffect(value, {
            effectType: 'glass',
            targetView: this.nativeViewProtected,
            toGlassStyleFn: toUIGlassStyle,
        });
    }
}
export function toUIGlassStyle(value) {
    if (supportsGlass()) {
        switch (value) {
            case 'regular':
                return 0 /* UIGlassEffectStyle.Regular */;
            case 'clear':
                return 1 /* UIGlassEffectStyle.Clear */;
        }
    }
    return 1;
}
//# sourceMappingURL=index.ios.js.map