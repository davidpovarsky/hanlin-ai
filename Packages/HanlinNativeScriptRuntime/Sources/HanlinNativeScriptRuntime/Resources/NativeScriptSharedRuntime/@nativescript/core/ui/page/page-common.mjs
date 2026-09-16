var PageBase_1;
import { ContentView } from '../content-view';
import { CSSType } from '../core/view';
import { booleanConverter } from '../core/view-base';
import { Property, CssProperty } from '../core/properties';
import { Style } from '../styling/style';
import { Color } from '../../color';
import { isFrame } from '../frame/frame-helpers';
import { ActionBar } from '../action-bar';
import { profile } from '../../profiling';
import { PageEvents } from './events';
let PageBase = PageBase_1 = class PageBase extends ContentView {
    constructor() {
        super(...arguments);
        this.accessibilityAnnouncePageEnabled = true;
    }
    get navigationContext() {
        return this._navigationContext;
    }
    get actionBar() {
        if (!this._actionBar) {
            this.hasActionBar = true;
            this._actionBar = new ActionBar();
            this._addView(this._actionBar);
        }
        return this._actionBar;
    }
    set actionBar(value) {
        if (!value) {
            throw new Error('ActionBar cannot be null or undefined.');
        }
        if (this._actionBar !== value) {
            if (this._actionBar) {
                this._removeView(this._actionBar);
            }
            this.hasActionBar = true;
            this._actionBar = value;
            this._addView(this._actionBar);
        }
    }
    get androidStatusBarBackground() {
        return this.style.androidStatusBarBackground;
    }
    set androidStatusBarBackground(value) {
        this.style.androidStatusBarBackground = value;
    }
    get page() {
        return this;
    }
    _parentChanged(oldParent) {
        const newParent = this.parent;
        if (newParent && !isFrame(newParent)) {
            throw new Error(`Page can only be nested inside Frame. New parent: ${newParent}`);
        }
        super._parentChanged(oldParent);
    }
    _addChildFromBuilder(name, value) {
        if (value instanceof ActionBar) {
            this.actionBar = value;
        }
        else {
            super._addChildFromBuilder(name, value);
        }
    }
    getKeyframeAnimationWithName(animationName) {
        return this._styleScope.getKeyframeAnimationWithName(animationName);
    }
    get frame() {
        return this.parent;
    }
    createNavigatedData(eventName, isBackNavigation) {
        return {
            eventName: eventName,
            object: this,
            context: this.navigationContext,
            isBackNavigation: isBackNavigation,
        };
    }
    onNavigatingTo(context, isBackNavigation, bindingContext) {
        this._navigationContext = context;
        if (isBackNavigation && this._styleScope) {
            this._styleScope.ensureSelectors();
            if (!this._cssState.isSelectorsLatestVersionApplied()) {
                this._onCssStateChange();
            }
        }
        //https://github.com/NativeScript/NativeScript/issues/731
        if (!isBackNavigation && bindingContext !== undefined && bindingContext !== null) {
            this.bindingContext = bindingContext;
        }
        this.notify(this.createNavigatedData(PageBase_1.navigatingToEvent, isBackNavigation));
    }
    onNavigatedTo(isBackNavigation) {
        this.notify(this.createNavigatedData(PageBase_1.navigatedToEvent, isBackNavigation));
        if (this.accessibilityAnnouncePageEnabled) {
            this.accessibilityScreenChanged(!!isBackNavigation);
        }
    }
    onNavigatingFrom(isBackNavigation) {
        this.notify(this.createNavigatedData(PageBase_1.navigatingFromEvent, isBackNavigation));
    }
    onNavigatedFrom(isBackNavigation) {
        this.notify(this.createNavigatedData(PageBase_1.navigatedFromEvent, isBackNavigation));
        this._navigationContext = undefined;
    }
    eachChildView(callback) {
        super.eachChildView(callback);
        if (this.hasActionBar) {
            callback(this.actionBar);
        }
    }
    get _childrenCount() {
        return (this.content ? 1 : 0) + (this._actionBar ? 1 : 0);
    }
    accessibilityScreenChanged(refocus) {
        return;
    }
};
PageBase.navigatingToEvent = PageEvents.navigatingToEvent;
PageBase.navigatedToEvent = PageEvents.navigatedToEvent;
PageBase.navigatingFromEvent = PageEvents.navigatingFromEvent;
PageBase.navigatedFromEvent = PageEvents.navigatedFromEvent;
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, Boolean, Object]),
    __metadata("design:returntype", void 0)
], PageBase.prototype, "onNavigatingTo", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Boolean]),
    __metadata("design:returntype", void 0)
], PageBase.prototype, "onNavigatedTo", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Boolean]),
    __metadata("design:returntype", void 0)
], PageBase.prototype, "onNavigatingFrom", null);
__decorate([
    profile,
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Boolean]),
    __metadata("design:returntype", void 0)
], PageBase.prototype, "onNavigatedFrom", null);
PageBase = PageBase_1 = __decorate([
    CSSType('Page')
], PageBase);
export { PageBase };
PageBase.prototype.recycleNativeView = 'never';
/**
 * Dependency property used to hide the Navigation Bar in iOS and the Action Bar in Android.
 */
export const actionBarHiddenProperty = new Property({
    name: 'actionBarHidden',
    affectsLayout: __APPLE__,
    valueConverter: booleanConverter,
});
actionBarHiddenProperty.register(PageBase);
/**
 * Dependency property that specify if page background should span under status bar.
 */
export const backgroundSpanUnderStatusBarProperty = new Property({
    name: 'backgroundSpanUnderStatusBar',
    defaultValue: false,
    affectsLayout: __APPLE__,
    valueConverter: booleanConverter,
});
backgroundSpanUnderStatusBarProperty.register(PageBase);
/**
 * Dependency property used to control if swipe back navigation in iOS is enabled.
 * This property is iOS specific. Default value: true
 */
export const enableSwipeBackNavigationProperty = new Property({
    name: 'enableSwipeBackNavigation',
    defaultValue: true,
    valueConverter: booleanConverter,
});
enableSwipeBackNavigationProperty.register(PageBase);
/**
 * Property backing androidStatusBarBackground.
 */
export const androidStatusBarBackgroundProperty = new CssProperty({
    name: 'androidStatusBarBackground',
    cssName: 'android-status-bar-background',
    equalityComparer: Color.equals,
    valueConverter: (v) => new Color(v),
});
androidStatusBarBackgroundProperty.register(Style);
//# sourceMappingURL=page-common.js.map