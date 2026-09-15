import { ViewCommon, isEnabledProperty, originXProperty, originYProperty, isUserInteractionEnabledProperty, testIDProperty, iosGlassEffectProperty, statusBarStyleProperty } from './view-common';
import { isAccessibilityServiceEnabled } from '../../../application';
import { updateA11yPropertiesCallback } from '../../../application/helpers-common';
import { hiddenProperty } from '../view-base';
import { Trace } from '../../../trace';
import { layout, ios as iosUtils, getWindow } from '../../../utils';
import { SDK_VERSION, supportsGlass } from '../../../utils/constants';
import { IOSHelper } from './view-helper';
import { ios as iosBackground } from '../../styling/background';
import { perspectiveProperty, visibilityProperty, opacityProperty, rotateProperty, rotateXProperty, rotateYProperty, scaleXProperty, scaleYProperty, translateXProperty, translateYProperty, zIndexProperty, backgroundInternalProperty, directionProperty } from '../../styling/style-properties';
import { profile } from '../../../profiling';
import { accessibilityEnabledProperty, accessibilityHiddenProperty, accessibilityHintProperty, accessibilityIdentifierProperty, accessibilityLabelProperty, accessibilityLanguageProperty, accessibilityLiveRegionProperty, accessibilityMediaSessionProperty, accessibilityRoleProperty, accessibilityStateProperty, accessibilityValueProperty, accessibilityIgnoresInvertColorsProperty } from '../../../accessibility/accessibility-properties';
import { IOSPostAccessibilityNotificationType } from '../../../accessibility';
import { CoreTypes } from '../../../core-types';
import { SharedTransition } from '../../transition/shared-transition';
import { Color } from '../../../color';
export * from './view-common';
export * from './view-helper';
// This one can eventually be cleaned up but causes issues with a lot of ui-suite plugins in particular if not exported here
export * from '../properties';
const PFLAG_FORCE_LAYOUT = 1;
const PFLAG_MEASURED_DIMENSION_SET = 1 << 1;
const PFLAG_LAYOUT_REQUIRED = 1 << 2;
export class View extends ViewCommon {
    constructor() {
        super(...arguments);
        this._isLaidOut = false;
        this._isTransformed = false;
        this._privateFlags = PFLAG_LAYOUT_REQUIRED | PFLAG_FORCE_LAYOUT;
        this._suspendCATransaction = false;
    }
    get nativeBackgroundState() {
        return this._nativeBackgroundState;
    }
    get isLayoutRequired() {
        return (this._privateFlags & PFLAG_LAYOUT_REQUIRED) === PFLAG_LAYOUT_REQUIRED;
    }
    get isLayoutRequested() {
        return (this._privateFlags & PFLAG_FORCE_LAYOUT) === PFLAG_FORCE_LAYOUT;
    }
    disposeNativeView() {
        super.disposeNativeView();
        this._cachedFrame = null;
        this._isLaidOut = false;
        this._isTransformed = false;
    }
    requestLayout() {
        this._privateFlags |= PFLAG_FORCE_LAYOUT;
        super.requestLayout();
        const nativeView = this.nativeViewProtected;
        if (nativeView && nativeView.setNeedsLayout) {
            nativeView.setNeedsLayout();
        }
        if (this.viewController && this.viewController.view !== nativeView) {
            this.viewController.view.setNeedsLayout();
        }
    }
    measure(widthMeasureSpec, heightMeasureSpec) {
        const measureSpecsChanged = this._setCurrentMeasureSpecs(widthMeasureSpec, heightMeasureSpec);
        if (this.nativeViewProtected && (this.isLayoutRequested || measureSpecsChanged)) {
            // first clears the measured dimension flag
            this._privateFlags &= ~PFLAG_MEASURED_DIMENSION_SET;
            // measure ourselves, this should set the measured dimension flag back
            this.onMeasure(widthMeasureSpec, heightMeasureSpec);
            this._privateFlags |= PFLAG_LAYOUT_REQUIRED;
            // flag not set, setMeasuredDimension() was not invoked, we trace
            // the exception to warn the developer
            if ((this._privateFlags & PFLAG_MEASURED_DIMENSION_SET) !== PFLAG_MEASURED_DIMENSION_SET) {
                if (Trace.isEnabled()) {
                    Trace.write('onMeasure() did not set the measured dimension by calling setMeasuredDimension() ' + this, Trace.categories.Layout, Trace.messageType.error);
                }
            }
        }
    }
    layout(left, top, right, bottom, setFrame = true) {
        const { boundsChanged, sizeChanged } = this._setCurrentLayoutBounds(left, top, right, bottom);
        if (setFrame) {
            this.layoutNativeView(left, top, right, bottom);
        }
        const needsLayout = boundsChanged || this.isLayoutRequired;
        if (needsLayout) {
            let position;
            if (this.nativeViewProtected && SDK_VERSION > 10) {
                // on iOS 11+ it is possible to have a changed layout frame due to safe area insets
                // get the frame and adjust the position, so that onLayout works correctly
                position = IOSHelper.getPositionFromFrame(this.nativeViewProtected.frame);
            }
            else {
                position = { left, top, right, bottom };
            }
            this.onLayout(position.left, position.top, position.right, position.bottom);
            this._privateFlags &= ~PFLAG_LAYOUT_REQUIRED;
        }
        this.updateBackground(sizeChanged, needsLayout);
        this._privateFlags &= ~PFLAG_FORCE_LAYOUT;
    }
    updateBackground(sizeChanged, needsLayout) {
        if (sizeChanged) {
            this._onSizeChanged();
        }
        else if (this._nativeBackgroundState === 'invalid') {
            const background = this.style.backgroundInternal;
            this._redrawNativeBackground(background);
        }
        else {
            // Update layers that don't belong to view's layer (e.g. shadow layers)
            if (needsLayout) {
                this.layoutOuterShadows();
            }
        }
    }
    layoutOuterShadows() {
        const nativeView = this.nativeViewProtected;
        if (nativeView?.outerShadowContainerLayer) {
            CATransaction.setDisableActions(true);
            nativeView.outerShadowContainerLayer.bounds = nativeView.bounds;
            nativeView.outerShadowContainerLayer.position = nativeView.center;
            CATransaction.setDisableActions(false);
        }
    }
    setMeasuredDimension(measuredWidth, measuredHeight) {
        super.setMeasuredDimension(measuredWidth, measuredHeight);
        this._privateFlags |= PFLAG_MEASURED_DIMENSION_SET;
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        const view = this.nativeViewProtected;
        const width = layout.getMeasureSpecSize(widthMeasureSpec);
        const widthMode = layout.getMeasureSpecMode(widthMeasureSpec);
        const height = layout.getMeasureSpecSize(heightMeasureSpec);
        const heightMode = layout.getMeasureSpecMode(heightMeasureSpec);
        let nativeWidth = 0;
        let nativeHeight = 0;
        if (view) {
            const nativeSize = layout.measureNativeView(view, width, widthMode, height, heightMode);
            nativeWidth = nativeSize.width;
            nativeHeight = nativeSize.height;
        }
        let measureWidth = Math.max(nativeWidth, this.effectiveMinWidth);
        let measureHeight = Math.max(nativeHeight, this.effectiveMinHeight);
        // Clamp to max-width/max-height (effectiveMax* is Infinity when unconstrained).
        // Applied after min so that max wins when min > max, matching CSS.
        measureWidth = Math.min(measureWidth, this.effectiveMaxWidth);
        measureHeight = Math.min(measureHeight, this.effectiveMaxHeight);
        const widthAndState = View.resolveSizeAndState(measureWidth, width, widthMode, 0);
        const heightAndState = View.resolveSizeAndState(measureHeight, height, heightMode, 0);
        this.setMeasuredDimension(widthAndState, heightAndState);
    }
    onLayout(left, top, right, bottom) {
        //
    }
    _modifyNativeViewFrame(nativeView, frame) {
        let transform;
        if (this._isTransformed) {
            // Always set identity transform before setting frame
            transform = nativeView.layer.transform;
            nativeView.layer.transform = CATransform3DIdentity;
        }
        else {
            transform = null;
        }
        nativeView.frame = frame;
        const adjustedFrame = this.applySafeAreaInsets(frame);
        if (adjustedFrame) {
            nativeView.frame = adjustedFrame;
        }
        if (transform != null) {
            // Re-apply the transform after the frame is adjusted
            nativeView.layer.transform = transform;
        }
        const boundsOrigin = nativeView.bounds.origin;
        const boundsFrame = adjustedFrame || frame;
        nativeView.bounds = CGRectMake(boundsOrigin.x, boundsOrigin.y, boundsFrame.size.width, boundsFrame.size.height);
        nativeView.layoutIfNeeded();
    }
    _setNativeViewFrame(nativeView, frame) {
        const oldFrame = this._cachedFrame || nativeView.frame;
        if (!CGRectEqualToRect(oldFrame, frame)) {
            if (Trace.isEnabled()) {
                Trace.write(this + ' :_setNativeViewFrame: ' + JSON.stringify(IOSHelper.getPositionFromFrame(frame)), Trace.categories.Layout);
            }
            this._cachedFrame = frame;
            this._modifyNativeViewFrame(nativeView, frame);
            this._raiseLayoutChangedEvent();
            this._isLaidOut = true;
        }
        else if (!this._isLaidOut) {
            this._cachedFrame = frame;
            // Rects could be equal on the first layout and an event should be raised.
            this._raiseLayoutChangedEvent();
            // But make sure event is raised only once if rects are equal on the first layout as
            // this method is called twice with equal rects in landscape mode (vs only once in portrait)
            this._isLaidOut = true;
        }
    }
    get isLayoutValid() {
        if (this.nativeViewProtected) {
            return !this.isLayoutRequested;
        }
        return false;
    }
    layoutNativeView(left, top, right, bottom) {
        if (!this.nativeViewProtected) {
            return;
        }
        const nativeView = this.nativeViewProtected;
        const frame = IOSHelper.getFrameFromPosition({
            left,
            top,
            right,
            bottom,
        });
        this._setNativeViewFrame(nativeView, frame);
    }
    _layoutParent() {
        if (this.nativeViewProtected) {
            const frame = this.nativeViewProtected.frame;
            const origin = frame.origin;
            const size = frame.size;
            const left = layout.toDevicePixels(origin.x);
            const top = layout.toDevicePixels(origin.y);
            const width = layout.toDevicePixels(size.width);
            const height = layout.toDevicePixels(size.height);
            this._setLayoutFlags(left, top, width + left, height + top);
        }
        super._layoutParent();
    }
    _setLayoutFlags(left, top, right, bottom) {
        const width = right - left;
        const height = bottom - top;
        const widthSpec = layout.makeMeasureSpec(width, layout.EXACTLY);
        const heightSpec = layout.makeMeasureSpec(height, layout.EXACTLY);
        this._setCurrentMeasureSpecs(widthSpec, heightSpec);
        this._privateFlags &= ~PFLAG_FORCE_LAYOUT;
        this.setMeasuredDimension(width, height);
        const { boundsChanged, sizeChanged } = this._setCurrentLayoutBounds(left, top, right, bottom);
        this.updateBackground(sizeChanged, boundsChanged);
        this._privateFlags &= ~PFLAG_LAYOUT_REQUIRED;
    }
    focus() {
        if (this.ios) {
            return this.ios.becomeFirstResponder();
        }
        return false;
    }
    applySafeAreaInsets(frame) {
        if (!__VISIONOS__ && SDK_VERSION <= 10) {
            return null;
        }
        if (this.iosIgnoreSafeArea) {
            return frame;
        }
        if (!this.iosOverflowSafeArea || !this.iosOverflowSafeAreaEnabled) {
            return IOSHelper.shrinkToSafeArea(this, frame);
        }
        else if (this.nativeViewProtected && this.nativeViewProtected.window) {
            return IOSHelper.expandBeyondSafeArea(this, frame);
        }
        return null;
    }
    getSafeAreaInsets() {
        const safeAreaInsets = this.nativeViewProtected && this.nativeViewProtected.safeAreaInsets;
        const insets = { left: 0, top: 0, right: 0, bottom: 0 };
        if (this.iosIgnoreSafeArea) {
            return insets;
        }
        // An iOS-managed ScrollView ancestor already applies safe-area insets via
        // adjustedContentInset; subtracting them here too would double-count them.
        if (IOSHelper.hasIOSManagedInsetAncestor(this)) {
            return insets;
        }
        if (safeAreaInsets) {
            insets.left = layout.round(layout.toDevicePixels(safeAreaInsets.left));
            insets.top = layout.round(layout.toDevicePixels(safeAreaInsets.top));
            insets.right = layout.round(layout.toDevicePixels(safeAreaInsets.right));
            insets.bottom = layout.round(layout.toDevicePixels(safeAreaInsets.bottom));
        }
        return insets;
    }
    _setDefaultPaddings(insets) {
        if (insets instanceof UIEdgeInsets) {
            this._defaultPaddingTop = layout.toDevicePixels(insets.top);
            this._defaultPaddingRight = layout.toDevicePixels(insets.right);
            this._defaultPaddingBottom = layout.toDevicePixels(insets.bottom);
            this._defaultPaddingLeft = layout.toDevicePixels(insets.left);
        }
        else {
            this._defaultPaddingTop = 0;
            this._defaultPaddingRight = 0;
            this._defaultPaddingBottom = 0;
            this._defaultPaddingLeft = 0;
        }
    }
    getLocationInWindow() {
        if (!this.nativeViewProtected || !this.nativeViewProtected.window) {
            return undefined;
        }
        const pointInWindow = this.nativeViewProtected.convertPointToView(this.nativeViewProtected.bounds.origin, null);
        return {
            x: pointInWindow.x,
            y: pointInWindow.y,
        };
    }
    getLocationOnScreen() {
        if (!this.nativeViewProtected || !this.nativeViewProtected.window) {
            return undefined;
        }
        const pointInWindow = this.nativeViewProtected.convertPointToView(this.nativeViewProtected.bounds.origin, null);
        const pointOnScreen = this.nativeViewProtected.window.convertPointToWindow(pointInWindow, null);
        return {
            x: pointOnScreen.x,
            y: pointOnScreen.y,
        };
    }
    getLocationRelativeTo(otherView) {
        if (!this.nativeViewProtected || !this.nativeViewProtected.window || !otherView.nativeViewProtected || !otherView.nativeViewProtected.window || this.nativeViewProtected.window !== otherView.nativeViewProtected.window) {
            return undefined;
        }
        const myPointInWindow = this.nativeViewProtected.convertPointToView(this.nativeViewProtected.bounds.origin, null);
        const otherPointInWindow = otherView.nativeViewProtected.convertPointToView(otherView.nativeViewProtected.bounds.origin, null);
        return {
            x: myPointInWindow.x - otherPointInWindow.x,
            y: myPointInWindow.y - otherPointInWindow.y,
        };
    }
    _onSizeChanged() {
        const nativeView = this.nativeViewProtected;
        if (!nativeView) {
            return;
        }
        const background = this.style.backgroundInternal;
        const backgroundDependsOnSize = (background.image && background.image !== 'none') || background.clipPath || !background.hasUniformBorder() || background.hasBorderRadius() || background.hasBoxShadows();
        if (this._nativeBackgroundState === 'invalid' || (this._nativeBackgroundState === 'drawn' && backgroundDependsOnSize)) {
            this._redrawNativeBackground(background);
        }
    }
    updateNativeTransform() {
        const scaleX = this.scaleX || 1e-6;
        const scaleY = this.scaleY || 1e-6;
        const perspective = this.perspective || 300;
        const nativeView = this.nativeViewProtected;
        let transform = new CATransform3D(CATransform3DIdentity);
        // Only set perspective if there is 3D rotation
        if (this.rotateX || this.rotateY) {
            transform.m34 = -1 / perspective;
        }
        transform = CATransform3DTranslate(transform, this.translateX, this.translateY, 0);
        transform = iosUtils.applyRotateTransform(transform, this.rotateX, this.rotateY, this.rotate);
        transform = CATransform3DScale(transform, scaleX, scaleY, 1);
        if (!CATransform3DEqualToTransform(this.nativeViewProtected.layer.transform, transform)) {
            const updateSuspended = this._isPresentationLayerUpdateSuspended();
            if (!updateSuspended) {
                CATransaction.begin();
            }
            // Disable CALayer animatable property changes
            CATransaction.setDisableActions(true);
            this.nativeViewProtected.layer.transform = transform;
            if (nativeView.outerShadowContainerLayer) {
                nativeView.outerShadowContainerLayer.transform = transform;
            }
            this._isTransformed = this.nativeViewProtected && !CATransform3DEqualToTransform(this.nativeViewProtected.transform3D, CATransform3DIdentity);
            CATransaction.setDisableActions(false);
            if (!updateSuspended) {
                CATransaction.commit();
            }
        }
    }
    updateOriginPoint(originX, originY) {
        const nativeView = this.nativeViewProtected;
        const newPoint = CGPointMake(originX, originY);
        // Disable CALayer animatable property changes
        CATransaction.setDisableActions(true);
        nativeView.layer.anchorPoint = newPoint;
        // Bounds have to be recalculated after anchor point update
        if (this._cachedFrame) {
            const frame = this._cachedFrame;
            this._cachedFrame = null;
            this._setNativeViewFrame(nativeView, frame);
        }
        // Make sure new origin also applies to outer shadow layers
        if (nativeView.outerShadowContainerLayer) {
            // This is the new frame after view origin point update
            const frame = nativeView.frame;
            nativeView.outerShadowContainerLayer.anchorPoint = newPoint;
            nativeView.outerShadowContainerLayer.position = CGPointMake(frame.origin.x + frame.size.width * originX, frame.origin.y + frame.size.height * originY);
        }
        CATransaction.setDisableActions(false);
    }
    // By default we update the view's presentation layer when setting backgroundColor and opacity properties.
    // This is done by calling CATransaction begin and commit methods.
    // This action should be disabled when updating those properties during an animation.
    _suspendPresentationLayerUpdates() {
        this._suspendCATransaction = true;
    }
    _resumePresentationLayerUpdates() {
        this._suspendCATransaction = false;
    }
    _isPresentationLayerUpdateSuspended() {
        return this._suspendCATransaction || this._suspendNativeUpdatesCount > 0;
    }
    _showNativeModalView(parent, options) {
        const parentWithController = IOSHelper.getParentWithViewController(parent);
        if (!parentWithController) {
            Trace.write(`Could not find parent with viewController for ${parent} while showing modal view.`, Trace.categories.ViewHierarchy, Trace.messageType.error);
            return;
        }
        const parentController = parentWithController.viewController;
        if (parentController.presentedViewController) {
            Trace.write('Parent is already presenting view controller. Close the current modal page before showing another one!', Trace.categories.ViewHierarchy, Trace.messageType.error);
            return;
        }
        if (!parentController.view || !parentController.view.window) {
            Trace.write('Parent page is not part of the window hierarchy.', Trace.categories.ViewHierarchy, Trace.messageType.error);
            return;
        }
        this._setupAsRootView({});
        super._showNativeModalView(parentWithController, options);
        let controller = this.viewController;
        if (!controller) {
            const nativeView = this.ios || this.nativeViewProtected;
            controller = IOSHelper.UILayoutViewController.initWithOwner(new WeakRef(this));
            if (nativeView instanceof UIView) {
                controller.view.addSubview(nativeView);
            }
            this.viewController = controller;
        }
        if (options.transition) {
            controller.modalPresentationStyle = 4 /* UIModalPresentationStyle.Custom */;
            if (options.transition.instance) {
                this._transitioningDelegate = UIViewControllerTransitioningDelegateImpl.initWithOwner(new WeakRef(options.transition.instance));
                controller.transitioningDelegate = this._transitioningDelegate;
                this.transitionId = options.transition.instance.id;
                const transitionState = SharedTransition.getState(options.transition.instance.id);
                if (transitionState?.interactive?.dismiss) {
                    // interactive transitions via gestures
                    // TODO - these could be typed as: boolean | (view: View) => void
                    // to allow users to define their own custom gesture dismissals
                    options.transition.instance.setupInteractiveGesture(this._closeModalCallback.bind(this), this);
                }
            }
        }
        else if (options.fullscreen) {
            controller.modalPresentationStyle = 0 /* UIModalPresentationStyle.FullScreen */;
        }
        else {
            controller.modalPresentationStyle = 2 /* UIModalPresentationStyle.FormSheet */;
            //check whether both height and width is provided and are positive numbers
            // set it has prefered content size to the controller presenting the dialog
            if (options.ios && options.ios.width > 0 && options.ios.height > 0) {
                controller.preferredContentSize = CGSizeMake(options.ios.width, options.ios.height);
            }
            else {
                //use CSS & attribute width & height if option is not provided
                const handler = () => {
                    if (this.viewController) {
                        const w = (this.width || this.style.width);
                        const h = (this.height || this.style.height);
                        //TODO: only numeric value is supported, percentage value is not supported like Android
                        if (w > 0 && h > 0) {
                            this.viewController.preferredContentSize = CGSizeMake(w, h);
                        }
                    }
                    this.off(View.loadedEvent, handler);
                };
                this.on(View.loadedEvent, handler);
            }
        }
        if (options.ios) {
            if (options.ios.presentationStyle) {
                const presentationStyle = options.ios.presentationStyle;
                controller.modalPresentationStyle = presentationStyle;
                if (presentationStyle === 7 /* UIModalPresentationStyle.Popover */) {
                    this._setupPopoverControllerDelegate(controller, parent);
                }
            }
            if (options.ios.statusBarStyle) {
                /**
                 * https://developer.apple.com/documentation/uikit/uiviewcontroller/modalpresentationcapturesstatusbarappearance
                 */
                controller.modalPresentationCapturesStatusBarAppearance = true;
                this.statusBarStyle = options.ios.statusBarStyle;
            }
        }
        const cancelable = options.cancelable !== undefined ? !!options.cancelable : true;
        if (SDK_VERSION >= 13) {
            if (cancelable) {
                // Listen for dismiss modal callback.
                this._setupAdaptiveControllerDelegate(controller);
            }
            else {
                // Prevent users from dismissing the modal.
                controller.modalInPresentation = true;
            }
        }
        this.horizontalAlignment = 'stretch';
        this.verticalAlignment = 'stretch';
        this._raiseShowingModallyEvent();
        const animated = options.animated === undefined ? true : !!options.animated;
        if (!this._modalAnimatedOptions) {
            // track the user's animated options to use upon close as well
            this._modalAnimatedOptions = [];
        }
        this._modalAnimatedOptions.push(animated);
        // TODO: a11y
        // controller.accessibilityViewIsModal = true;
        // controller.accessibilityPerformEscape = () => {
        //   console.log('accessibilityPerformEscape!!')
        //   return true;
        // }
        parentController.presentViewControllerAnimatedCompletion(controller, animated, null);
        const transitionCoordinator = parentController.transitionCoordinator;
        if (transitionCoordinator) {
            transitionCoordinator.animateAlongsideTransitionCompletion(null, () => {
                setTimeout(() => {
                    // ensure raised on main queue
                    this._raiseShownModallyEvent();
                });
            });
        }
        else {
            // Apparently iOS 9+ stops all transitions and animations upon application suspend and transitionCoordinator becomes null here in this case.
            // Since we are not waiting for any transition to complete, i.e. transitionCoordinator is null, we can directly raise our shownModally event.
            // Take a look at https://github.com/NativeScript/NativeScript/issues/2173 for more info and a sample project.
            this._raiseShownModallyEvent();
        }
        controller = null;
    }
    _hideNativeModalView(parent, whenClosedCallback) {
        if (!parent || !parent.viewController) {
            Trace.error('Trying to hide modal view but no parent with viewController specified.');
            return;
        }
        // modal view has already been closed by UI, probably as a popover
        if (!parent.viewController.presentedViewController) {
            whenClosedCallback();
            return;
        }
        const parentController = parent.viewController;
        let animated = true;
        if (this._modalAnimatedOptions?.length) {
            animated = this._modalAnimatedOptions.slice(-1)[0];
        }
        parentController.dismissViewControllerAnimatedCompletion(animated, () => {
            const transitionState = SharedTransition.getState(this.transitionId);
            if (!transitionState?.interactiveCancelled) {
                this._transitioningDelegate = null;
                // this.off('pan', this._interactiveDismissGesture);
                if (this._modalAnimatedOptions) {
                    this._modalAnimatedOptions.pop();
                }
            }
            whenClosedCallback();
        });
    }
    [isEnabledProperty.getDefault]() {
        const nativeView = this.nativeViewProtected;
        return nativeView instanceof UIControl ? nativeView.enabled : true;
    }
    [isEnabledProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        if (nativeView instanceof UIControl) {
            nativeView.enabled = value;
        }
    }
    [originXProperty.getDefault]() {
        return this.nativeViewProtected.layer.anchorPoint.x;
    }
    [originXProperty.setNative](value) {
        this.updateOriginPoint(value, this.originY);
    }
    [originYProperty.getDefault]() {
        return this.nativeViewProtected.layer.anchorPoint.y;
    }
    [originYProperty.setNative](value) {
        this.updateOriginPoint(this.originX, value);
    }
    [testIDProperty.setNative](value) {
        this.setAccessibilityIdentifier(this.nativeViewProtected, value);
    }
    setAccessibilityIdentifier(view, value) {
        view.accessibilityIdentifier = value;
        if (this.testID && this.testID !== value)
            this.testID = value;
        if (this.accessibilityIdentifier !== value)
            this.accessibilityIdentifier = value;
    }
    [accessibilityEnabledProperty.setNative](value) {
        this.nativeViewProtected.isAccessibilityElement = !!value;
        updateA11yPropertiesCallback(this);
    }
    [accessibilityIdentifierProperty.getDefault]() {
        return this.nativeViewProtected.accessibilityIdentifier;
    }
    [accessibilityIdentifierProperty.setNative](value) {
        this.setAccessibilityIdentifier(this.nativeViewProtected, value);
    }
    [accessibilityRoleProperty.setNative](value) {
        this.accessibilityRole = value;
        updateA11yPropertiesCallback(this);
    }
    [accessibilityValueProperty.setNative](value) {
        value = value == null ? null : `${value}`;
        this.nativeViewProtected.accessibilityValue = value;
    }
    [accessibilityLabelProperty.setNative](value) {
        value = value == null ? null : `${value}`;
        // not sure if needed for Label:
        // if ((<any>this).nativeTextViewProtected) {
        //   (<any>this).nativeTextViewProtected.accessibilityLabel = value;
        // } else {
        this.nativeViewProtected.accessibilityLabel = value;
        // }
    }
    [accessibilityHintProperty.setNative](value) {
        value = value == null ? null : `${value}`;
        this.nativeViewProtected.accessibilityHint = value;
    }
    [accessibilityIgnoresInvertColorsProperty.setNative](value) {
        this.nativeViewProtected.accessibilityIgnoresInvertColors = !!value;
    }
    [accessibilityLanguageProperty.setNative](value) {
        value = value == null ? null : `${value}`;
        this.nativeViewProtected.accessibilityLanguage = value;
    }
    [accessibilityHiddenProperty.setNative](value) {
        this.nativeViewProtected.accessibilityElementsHidden = !!value;
        updateA11yPropertiesCallback(this);
    }
    [accessibilityLiveRegionProperty.setNative]() {
        updateA11yPropertiesCallback(this);
    }
    [accessibilityStateProperty.setNative](value) {
        this.accessibilityState = value;
        updateA11yPropertiesCallback(this);
    }
    [accessibilityMediaSessionProperty.setNative]() {
        updateA11yPropertiesCallback(this);
    }
    [isUserInteractionEnabledProperty.getDefault]() {
        return this.nativeViewProtected.userInteractionEnabled;
    }
    [isUserInteractionEnabledProperty.setNative](value) {
        this.nativeViewProtected.userInteractionEnabled = value;
    }
    [hiddenProperty.getDefault]() {
        return this.nativeViewProtected.hidden;
    }
    [hiddenProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        nativeView.hidden = value;
        // Apply visibility value to shadows as well
        if (nativeView.outerShadowContainerLayer) {
            nativeView.outerShadowContainerLayer.hidden = nativeView.hidden;
        }
    }
    [visibilityProperty.getDefault]() {
        return this.nativeViewProtected.hidden ? CoreTypes.Visibility.collapse : CoreTypes.Visibility.visible;
    }
    [visibilityProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        switch (value) {
            case CoreTypes.Visibility.visible:
                nativeView.hidden = false;
                break;
            case CoreTypes.Visibility.hidden:
            case CoreTypes.Visibility.collapse:
                nativeView.hidden = true;
                break;
            default:
                throw new Error(`Invalid visibility value: ${value}. Valid values are: "${CoreTypes.Visibility.visible}", "${CoreTypes.Visibility.hidden}", "${CoreTypes.Visibility.collapse}".`);
        }
        // Apply visibility value to shadows as well
        if (nativeView.outerShadowContainerLayer) {
            nativeView.outerShadowContainerLayer.hidden = nativeView.hidden;
        }
    }
    [opacityProperty.getDefault]() {
        return this.nativeViewProtected.alpha;
    }
    [opacityProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        const updateSuspended = this._isPresentationLayerUpdateSuspended();
        if (!updateSuspended) {
            CATransaction.begin();
        }
        // Disable CALayer animatable property changes
        CATransaction.setDisableActions(true);
        nativeView.alpha = value;
        // Apply opacity value to shadows as well
        if (nativeView.outerShadowContainerLayer) {
            nativeView.outerShadowContainerLayer.opacity = value;
        }
        CATransaction.setDisableActions(false);
        if (!updateSuspended) {
            CATransaction.commit();
        }
    }
    [rotateProperty.getDefault]() {
        return 0;
    }
    [rotateProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [rotateXProperty.getDefault]() {
        return 0;
    }
    [rotateXProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [rotateYProperty.getDefault]() {
        return 0;
    }
    [rotateYProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [perspectiveProperty.getDefault]() {
        return 300;
    }
    [perspectiveProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [scaleXProperty.getDefault]() {
        return 1;
    }
    [scaleXProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [scaleYProperty.getDefault]() {
        return 1;
    }
    [scaleYProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [translateXProperty.getDefault]() {
        return 0;
    }
    [translateXProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [translateYProperty.getDefault]() {
        return 0;
    }
    [translateYProperty.setNative](value) {
        this.updateNativeTransform();
    }
    [zIndexProperty.getDefault]() {
        return 0;
    }
    [zIndexProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        nativeView.layer.zPosition = value;
        // Apply z-index to shadows as well
        if (nativeView.outerShadowContainerLayer) {
            nativeView.outerShadowContainerLayer.zPosition = value;
        }
    }
    [backgroundInternalProperty.getDefault]() {
        return this.nativeViewProtected.backgroundColor;
    }
    [backgroundInternalProperty.setNative](value) {
        this._nativeBackgroundState = 'invalid';
        if (this.isLayoutValid) {
            this._redrawNativeBackground(value);
        }
    }
    _applyGlassEffect(value, options) {
        const config = typeof value !== 'string' ? value : null;
        const variant = config ? config.variant : value;
        const defaultDuration = 0.3;
        const duration = config ? (config.animateChangeDuration ?? defaultDuration) : defaultDuration;
        const glassSupported = supportsGlass();
        let effect = UIVisualEffect.new();
        // Create the appropriate effect based on type and variant
        if (value && !['identity', 'none'].includes(variant) && glassSupported) {
            if (options.effectType === 'glass') {
                const styleFn = options.toGlassStyleFn || this.toUIGlassStyle.bind(this);
                effect = UIGlassEffect.effectWithStyle(styleFn(variant));
                if (config) {
                    effect.interactive = !!config.interactive;
                    if (config.tint) {
                        effect.tintColor = typeof config.tint === 'string' ? new Color(config.tint).ios : config.tint;
                    }
                }
            }
            else if (options.effectType === 'container') {
                effect = UIGlassContainerEffect.alloc().init();
                effect.spacing = config?.spacing ?? 8;
            }
        }
        // Handle creating new effect view or updating existing one
        if (options.targetView) {
            // Update existing effect view
            if (options.onUpdate) {
                options.onUpdate(options.targetView, effect, duration);
            }
            else {
                // Default update behavior: animate effect changes
                UIView.animateWithDurationAnimations(duration, () => {
                    options.targetView.effect = effect;
                });
            }
            return undefined;
        }
        else if (options.onCreate) {
            // Create new effect view and let caller handle setup
            const effectView = UIVisualEffectView.alloc().initWithEffect(effect);
            options.onCreate(effectView, effect);
            return effectView;
        }
        return undefined;
    }
    [statusBarStyleProperty.getDefault]() {
        return this.style.statusBarStyle;
    }
    [statusBarStyleProperty.setNative](value) {
        this.style.statusBarStyle = value;
        this.updateStatusBarStyle(value);
    }
    updateStatusBarStyle(value) {
        // iOS requires a controller invalidation to re-evaluate `preferredStatusBarStyle`.
        const ownerController = this.viewController || IOSHelper.getParentWithViewController(this)?.viewController;
        IOSHelper.invalidateStatusBarAppearance(ownerController, `View.updateStatusBarStyle:${value}`);
    }
    [iosGlassEffectProperty.setNative](value) {
        if (!this.nativeViewProtected || !supportsGlass()) {
            return;
        }
        if (!this._glassEffectView) {
            // Create new glass effect view
            this._glassEffectView = this._applyGlassEffect(value, {
                effectType: 'glass',
                onCreate: (effectView, effect) => {
                    // let touches pass to content
                    effectView.userInteractionEnabled = false;
                    effectView.clipsToBounds = true;
                    // size & autoresize
                    if (this._glassEffectMeasure) {
                        clearTimeout(this._glassEffectMeasure);
                    }
                    this._glassEffectMeasure = setTimeout(() => {
                        const size = this.nativeViewProtected.bounds.size;
                        effectView.frame = CGRectMake(0, 0, size.width, size.height);
                        effectView.autoresizingMask = 2;
                        this.nativeViewProtected.insertSubviewAtIndex(effectView, 0);
                    });
                },
            });
        }
        else {
            // Update existing glass effect view
            this._applyGlassEffect(value, {
                effectType: 'glass',
                targetView: this._glassEffectView,
            });
        }
    }
    [directionProperty.setNative](value) {
        const nativeView = this.nativeViewProtected;
        switch (value) {
            case CoreTypes.LayoutDirection.ltr:
                nativeView.semanticContentAttribute = 3 /* UISemanticContentAttribute.ForceLeftToRight */;
                break;
            case CoreTypes.LayoutDirection.rtl:
                nativeView.semanticContentAttribute = 4 /* UISemanticContentAttribute.ForceRightToLeft */;
                break;
            default:
                nativeView.semanticContentAttribute = 0 /* UISemanticContentAttribute.Unspecified */;
                break;
        }
    }
    sendAccessibilityEvent(options) {
        if (!isAccessibilityServiceEnabled()) {
            return;
        }
        if (!options.iosNotificationType) {
            return;
        }
        let notification;
        let args = this.nativeViewProtected;
        if (options?.message) {
            args = options.message;
        }
        switch (options.iosNotificationType) {
            case IOSPostAccessibilityNotificationType.Announcement: {
                notification = UIAccessibilityAnnouncementNotification;
                break;
            }
            case IOSPostAccessibilityNotificationType.Layout: {
                notification = UIAccessibilityLayoutChangedNotification;
                break;
            }
            case IOSPostAccessibilityNotificationType.Screen: {
                notification = UIAccessibilityScreenChangedNotification;
                break;
            }
            default: {
                return;
            }
        }
        UIAccessibilityPostNotification(notification, args ?? null);
    }
    accessibilityAnnouncement(msg = this.accessibilityLabel) {
        this.sendAccessibilityEvent({
            iosNotificationType: IOSPostAccessibilityNotificationType.Announcement,
            message: msg,
        });
    }
    accessibilityScreenChanged() {
        this.sendAccessibilityEvent({
            iosNotificationType: IOSPostAccessibilityNotificationType.Screen,
        });
    }
    toUIGlassStyle(value) {
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
    _getCurrentLayoutBounds() {
        const nativeView = this.nativeViewProtected;
        if (nativeView && !this.isCollapsed) {
            const frame = nativeView.frame;
            const origin = frame.origin;
            const size = frame.size;
            return {
                left: Math.round(layout.toDevicePixels(origin.x)),
                top: Math.round(layout.toDevicePixels(origin.y)),
                right: Math.round(layout.toDevicePixels(origin.x + size.width)),
                bottom: Math.round(layout.toDevicePixels(origin.y + size.height)),
            };
        }
        else {
            return { left: 0, top: 0, right: 0, bottom: 0 };
        }
    }
    _redrawNativeBackground(value) {
        const updateSuspended = this._isPresentationLayerUpdateSuspended();
        if (!updateSuspended) {
            CATransaction.begin();
        }
        // Disable CALayer animatable property changes
        CATransaction.setDisableActions(true);
        const nativeView = this.nativeViewProtected;
        if (nativeView) {
            if (value instanceof UIColor) {
                nativeView.backgroundColor = value;
            }
            else {
                iosBackground.createBackgroundUIColor(this, (color) => {
                    nativeView.backgroundColor = color;
                });
                this._setNativeClipToBounds();
            }
        }
        CATransaction.setDisableActions(false);
        if (!updateSuspended) {
            CATransaction.commit();
        }
        this._nativeBackgroundState = 'drawn';
    }
    _setNativeClipToBounds() {
        const view = this.nativeViewProtected;
        if (view) {
            const backgroundInternal = this.style.backgroundInternal;
            view.clipsToBounds = view instanceof UIScrollView || backgroundInternal.hasBorderWidth() || backgroundInternal.hasBorderRadius();
        }
    }
    _setupPopoverControllerDelegate(controller, parent) {
        const popoverPresentationController = controller.popoverPresentationController;
        this._popoverPresentationDelegate = IOSHelper.UIPopoverPresentationControllerDelegateImp.initWithOwnerAndCallback(new WeakRef(this), this._closeModalCallback);
        popoverPresentationController.delegate = this._popoverPresentationDelegate;
        let view;
        do {
            view = parent.nativeViewProtected;
            parent = parent.parent;
        } while (parent && !view);
        // Note: sourceView and sourceRect are needed to specify the anchor location for the popover.
        // Note: sourceView should be the button triggering the modal. If it the Page the popover might appear "behind" the page content
        popoverPresentationController.sourceView = view;
        popoverPresentationController.sourceRect = CGRectMake(0, 0, view.frame.size.width, view.frame.size.height);
    }
    _setupAdaptiveControllerDelegate(controller) {
        this._adaptivePresentationDelegate = IOSHelper.UIAdaptivePresentationControllerDelegateImp.initWithOwnerAndCallback(new WeakRef(this), this._closeModalCallback);
        if (controller?.presentationController) {
            controller.presentationController.delegate = this._adaptivePresentationDelegate;
        }
    }
}
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Number, Number, Number, Object]),
    __metadata("design:returntype", void 0)
], View.prototype, "layout", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Number, Number]),
    __metadata("design:returntype", void 0)
], View.prototype, "onMeasure", null);
View.prototype._nativeBackgroundState = 'unset';
var UIViewControllerTransitioningDelegateImpl = (function (_super) {
    __extends(UIViewControllerTransitioningDelegateImpl, _super);
    function UIViewControllerTransitioningDelegateImpl() {
        return _super !== null && _super.apply(this, arguments) || this;
    }
    UIViewControllerTransitioningDelegateImpl.initWithOwner = function (owner) {
        var delegate = UIViewControllerTransitioningDelegateImpl.new();
        delegate.owner = owner;
        return delegate;
    };
    UIViewControllerTransitioningDelegateImpl.prototype.animationControllerForDismissedController = function (dismissed) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner === null || owner === void 0 ? void 0 : owner.iosDismissedController) {
            return owner.iosDismissedController(dismissed);
        }
        return null;
    };
    UIViewControllerTransitioningDelegateImpl.prototype.animationControllerForPresentedControllerPresentingControllerSourceController = function (presented, presenting, source) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner === null || owner === void 0 ? void 0 : owner.iosPresentedController) {
            return owner.iosPresentedController(presented, presenting, source);
        }
        return null;
    };
    UIViewControllerTransitioningDelegateImpl.prototype.interactionControllerForDismissal = function (animator) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner === null || owner === void 0 ? void 0 : owner.iosInteractionDismiss) {
            var transitionState = SharedTransition.getState(owner.id);
            if (transitionState === null || transitionState === void 0 ? void 0 : transitionState.interactiveBegan) {
                return owner.iosInteractionDismiss(animator);
            }
        }
        return null;
    };
    UIViewControllerTransitioningDelegateImpl.prototype.interactionControllerForPresentation = function (animator) {
        var _a;
        var owner = (_a = this.owner) === null || _a === void 0 ? void 0 : _a.deref();
        if (owner === null || owner === void 0 ? void 0 : owner.iosInteractionPresented) {
            return owner.iosInteractionPresented(animator);
        }
        return null;
    };
    UIViewControllerTransitioningDelegateImpl.ObjCProtocols = [UIViewControllerTransitioningDelegate];
    return UIViewControllerTransitioningDelegateImpl;
}(NSObject));
export class ContainerView extends View {
    constructor() {
        super();
        this.iosOverflowSafeArea = true;
    }
}
export class CustomLayoutView extends ContainerView {
    createNativeView() {
        const window = getWindow?.();
        return UIView.alloc().initWithFrame(window ? window.screen.bounds : UIScreen.mainScreen.bounds);
    }
    get ios() {
        return this.nativeViewProtected;
    }
    onMeasure(widthMeasureSpec, heightMeasureSpec) {
        // Don't call super because it will set MeasureDimension. This method must be overridden and calculate its measuredDimensions.
    }
    _addViewToNativeVisualTree(child, atIndex) {
        super._addViewToNativeVisualTree(child, atIndex);
        const parentNativeView = this.nativeViewProtected;
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
                parentNativeView.layer.insertSublayerBelow(childNativeView.outerShadowContainerLayer, childNativeView.layer);
            }
            return true;
        }
        return false;
    }
    _removeViewFromNativeVisualTree(child) {
        super._removeViewFromNativeVisualTree(child);
        if (child.nativeViewProtected) {
            const nativeView = child.nativeViewProtected;
            // Remove outer shadow layer manually as it belongs to parent layer tree
            if (nativeView.outerShadowContainerLayer) {
                nativeView.outerShadowContainerLayer.removeFromSuperlayer();
            }
            nativeView.removeFromSuperview();
        }
    }
}
//# sourceMappingURL=index.ios.js.map