const __ANDROID__ = globalThis.__ANDROID__ !== undefined ? globalThis.__ANDROID__ : false;
const __APPLE__ = globalThis.__APPLE__ !== undefined ? globalThis.__APPLE__ : true;
import { Observable } from '../data/observable';
const lastFocusedViewOnPageKeyName = '__lastFocusedViewOnPage';
export const accessibilityBlurEvent = 'accessibilityBlur';
export const accessibilityFocusEvent = 'accessibilityFocus';
export const accessibilityFocusChangedEvent = 'accessibilityFocusChanged';
export const accessibilityPerformEscapeEvent = 'accessibilityPerformEscape';
/**
 * Send notification when accessibility focus state changes.
 * If either receivedFocus or lostFocus is true, 'accessibilityFocusChanged' is send with value true if element received focus
 * If receivedFocus, 'accessibilityFocus' is send
 * if lostFocus, 'accessibilityBlur' is send
 *
 * @param {View} view
 * @param {boolean} receivedFocus
 * @param {boolean} lostFocus
 */
export function notifyAccessibilityFocusState(view, receivedFocus, lostFocus) {
    if (!receivedFocus && !lostFocus) {
        return;
    }
    view.notify({
        eventName: accessibilityFocusChangedEvent,
        object: view,
        value: !!receivedFocus,
    });
    if (receivedFocus) {
        if (view.page) {
            view.page[lastFocusedViewOnPageKeyName] = new WeakRef(view);
        }
        view.notify({
            eventName: accessibilityFocusEvent,
            object: view,
        });
    }
    else if (lostFocus) {
        view.notify({
            eventName: accessibilityBlurEvent,
            object: view,
        });
    }
}
export function getLastFocusedViewOnPage(page) {
    try {
        const lastFocusedViewRef = page[lastFocusedViewOnPageKeyName];
        if (!lastFocusedViewRef) {
            return null;
        }
        const lastFocusedView = lastFocusedViewRef.deref();
        if (!lastFocusedView) {
            return null;
        }
        if (!lastFocusedView.parent || lastFocusedView.page !== page) {
            return null;
        }
        return lastFocusedView;
    }
    catch {
        // ignore
    }
    finally {
        delete page[lastFocusedViewOnPageKeyName];
    }
    return null;
}
export class SharedA11YObservable extends Observable {
}
export const AccessibilityServiceEnabledPropName = 'accessibilityServiceEnabled';
export class CommonA11YServiceEnabledObservable extends SharedA11YObservable {
    constructor(sharedA11YObservable) {
        super();
        const ref = new WeakRef(this);
        let lastValue;
        function callback() {
            const self = ref?.get();
            if (!self) {
                sharedA11YObservable.off(Observable.propertyChangeEvent, callback);
                return;
            }
            const newValue = !!sharedA11YObservable.accessibilityServiceEnabled;
            if (newValue !== lastValue) {
                self.set(AccessibilityServiceEnabledPropName, newValue);
                lastValue = newValue;
            }
        }
        sharedA11YObservable.on(Observable.propertyChangeEvent, callback);
        this.set(AccessibilityServiceEnabledPropName, !!sharedA11YObservable.accessibilityServiceEnabled);
    }
}
let a11yServiceEnabled;
export function isA11yEnabled() {
    if (typeof a11yServiceEnabled === 'boolean') {
        return a11yServiceEnabled;
    }
    return undefined;
}
export function setA11yEnabled(value) {
    a11yServiceEnabled = value;
}
export function enforceArray(val) {
    if (Array.isArray(val)) {
        return val;
    }
    if (typeof val === 'string') {
        return val.split(/[, ]/g).filter((v) => !!v);
    }
    return [];
}
export const VALID_FONT_SCALES = __APPLE__ // Apple supports a wider number of font scales than Android does.
    ? [0.5, 0.7, 0.85, 1, 1.15, 1.3, 1.5, 2, 2.5, 3, 3.5, 4]
    : [0.85, 1, 1.15, 1.3];
export function getClosestValidFontScale(fontScale) {
    fontScale = Number(fontScale) || 1;
    return VALID_FONT_SCALES.sort((a, b) => Math.abs(fontScale - a) - Math.abs(fontScale - b))[0];
}
export var FontScaleCategory;
(function (FontScaleCategory) {
    FontScaleCategory["ExtraSmall"] = "extra-small";
    FontScaleCategory["Medium"] = "medium";
    FontScaleCategory["ExtraLarge"] = "extra-large";
})(FontScaleCategory || (FontScaleCategory = {}));
export const fontScaleExtraSmallCategoryClass = `a11y-fontscale-xs`;
export const fontScaleMediumCategoryClass = `a11y-fontscale-m`;
export const fontScaleExtraLargeCategoryClass = `a11y-fontscale-xl`;
export const fontScaleCategoryClasses = [fontScaleExtraSmallCategoryClass, fontScaleMediumCategoryClass, fontScaleExtraLargeCategoryClass];
export const a11yServiceEnabledClass = `a11y-service-enabled`;
export const a11yServiceDisabledClass = `a11y-service-disabled`;
export const a11yServiceClasses = [a11yServiceEnabledClass, a11yServiceDisabledClass];
let currentFontScale = null;
export function setFontScale(scale) {
    currentFontScale = scale;
}
export function getFontScale() {
    return currentFontScale;
}
export function getFontScaleCategory() {
    if (__ANDROID__) {
        return FontScaleCategory.Medium;
    }
    if (getFontScale() < 0.85) {
        return FontScaleCategory.ExtraSmall;
    }
    if (getFontScale() > 1.5) {
        return FontScaleCategory.ExtraLarge;
    }
    return FontScaleCategory.Medium;
}
let initAccessibilityCssHelperCallback;
export function setInitAccessibilityCssHelper(callback) {
    initAccessibilityCssHelperCallback = callback;
}
export function readyInitAccessibilityCssHelper() {
    if (initAccessibilityCssHelperCallback) {
        initAccessibilityCssHelperCallback();
        initAccessibilityCssHelperCallback = null;
    }
}
let initFontScaleCallback;
export function setInitFontScale(callback) {
    initFontScaleCallback = callback;
}
export function readyInitFontScale() {
    if (initFontScaleCallback) {
        initFontScaleCallback();
        initFontScaleCallback = null;
    }
}
let fontScaleCssClasses;
export function setFontScaleCssClasses(value) {
    fontScaleCssClasses = value;
}
export function getFontScaleCssClasses() {
    return fontScaleCssClasses;
}
let currentFontScaleClass = '';
export function setCurrentFontScaleClass(value) {
    currentFontScaleClass = value;
}
export function getCurrentFontScaleClass() {
    return currentFontScaleClass;
}
let currentFontScaleCategory = '';
export function setCurrentFontScaleCategory(value) {
    currentFontScaleCategory = value;
}
export function getCurrentFontScaleCategory() {
    return currentFontScaleCategory;
}
let currentA11YServiceClass = '';
export function setCurrentA11YServiceClass(value) {
    currentA11YServiceClass = value;
}
export function getCurrentA11YServiceClass() {
    return currentA11YServiceClass;
}
/**
 * Applies the current accessibility state — the a11y service class, the font scale
 * classes and the inherited font scale — to a root view.
 *
 * Runs for every window's root view; the `readyInit*` helpers next to it only wire up
 * the process-wide listeners that keep this state current, and do so once.
 */
export function applyAccessibilityCssToRoot(rootView) {
    if (!rootView) {
        return;
    }
    const a11yServiceClass = getCurrentA11YServiceClass();
    if (a11yServiceClass) {
        rootView.cssClasses.add(a11yServiceClass);
    }
    const fontScaleClass = getCurrentFontScaleClass();
    if (fontScaleClass) {
        rootView.cssClasses.add(fontScaleClass);
    }
    const fontScaleCategoryClass = getCurrentFontScaleCategory();
    if (fontScaleCategoryClass) {
        rootView.cssClasses.add(fontScaleCategoryClass);
    }
    const fontScale = getFontScale();
    if (fontScale) {
        rootView.style.fontScaleInternal = fontScale;
    }
}
export var AccessibilityTrait;
(function (AccessibilityTrait) {
    /**
     * The element allows direct touch interaction for VoiceOver users.
     */
    AccessibilityTrait["AllowsDirectInteraction"] = "allowsDirectInteraction";
    /**
     * The element should cause an automatic page turn when VoiceOver finishes reading the text within it.
     * Note: Requires custom view with accessibilityScroll(...)
     */
    AccessibilityTrait["CausesPageTurn"] = "pageTurn";
    /**
     * The element is not enabled and does not respond to user interaction.
     */
    AccessibilityTrait["NotEnabled"] = "disabled";
    /**
     * The element is currently selected.
     */
    AccessibilityTrait["Selected"] = "selected";
    /**
     * The element frequently updates its label or value.
     */
    AccessibilityTrait["UpdatesFrequently"] = "frequentUpdates";
})(AccessibilityTrait || (AccessibilityTrait = {}));
export var AccessibilityRole;
(function (AccessibilityRole) {
    /**
     * The element allows continuous adjustment through a range of values.
     */
    AccessibilityRole["Adjustable"] = "adjustable";
    /**
     * The element should be treated as a button.
     */
    AccessibilityRole["Button"] = "button";
    /**
     * The element behaves like a Checkbox
     */
    AccessibilityRole["Checkbox"] = "checkbox";
    /**
     * The element is a header that divides content into sections, such as the title of a navigation bar.
     */
    AccessibilityRole["Header"] = "header";
    /**
     * The element should be treated as an image.
     */
    AccessibilityRole["Image"] = "image";
    /**
     * The element should be treated as a image button.
     */
    AccessibilityRole["ImageButton"] = "imageButton";
    /**
     * The element behaves as a keyboard key.
     */
    AccessibilityRole["KeyboardKey"] = "keyboardKey";
    /**
     * The element should be treated as a link.
     */
    AccessibilityRole["Link"] = "link";
    /**
     * The element has no traits.
     */
    AccessibilityRole["None"] = "none";
    /**
     * The element plays its own sound when activated.
     */
    AccessibilityRole["PlaysSound"] = "plays";
    /**
     * The element behaves like a ProgressBar
     */
    AccessibilityRole["ProgressBar"] = "progressBar";
    /**
     * The element behaves like a RadioButton
     */
    AccessibilityRole["RadioButton"] = "radioButton";
    /**
     * The element should be treated as a search field.
     */
    AccessibilityRole["Search"] = "search";
    /**
     * The element behaves like a SpinButton
     */
    AccessibilityRole["SpinButton"] = "spinButton";
    /**
     * The element starts a media session when it is activated.
     */
    AccessibilityRole["StartsMediaSession"] = "startsMedia";
    /**
     * The element should be treated as static text that cannot change.
     */
    AccessibilityRole["StaticText"] = "text";
    /**
     * The element provides summary information when the application starts.
     */
    AccessibilityRole["Summary"] = "summary";
    /**
     * The element behaves like a switch
     */
    AccessibilityRole["Switch"] = "switch";
})(AccessibilityRole || (AccessibilityRole = {}));
export var AccessibilityState;
(function (AccessibilityState) {
    AccessibilityState["Selected"] = "selected";
    AccessibilityState["Checked"] = "checked";
    AccessibilityState["Unchecked"] = "unchecked";
    AccessibilityState["Disabled"] = "disabled";
})(AccessibilityState || (AccessibilityState = {}));
export var AccessibilityLiveRegion;
(function (AccessibilityLiveRegion) {
    AccessibilityLiveRegion["None"] = "none";
    AccessibilityLiveRegion["Polite"] = "polite";
    AccessibilityLiveRegion["Assertive"] = "assertive";
})(AccessibilityLiveRegion || (AccessibilityLiveRegion = {}));
export var IOSPostAccessibilityNotificationType;
(function (IOSPostAccessibilityNotificationType) {
    IOSPostAccessibilityNotificationType["Announcement"] = "announcement";
    IOSPostAccessibilityNotificationType["Screen"] = "screen";
    IOSPostAccessibilityNotificationType["Layout"] = "layout";
})(IOSPostAccessibilityNotificationType || (IOSPostAccessibilityNotificationType = {}));
export var AndroidAccessibilityEvent;
(function (AndroidAccessibilityEvent) {
    /**
     * Invalid selection/focus position.
     */
    AndroidAccessibilityEvent["INVALID_POSITION"] = "invalid_position";
    /**
     * Maximum length of the text fields.
     */
    AndroidAccessibilityEvent["MAX_TEXT_LENGTH"] = "max_text_length";
    /**
     * Represents the event of clicking on a android.view.View like android.widget.Button, android.widget.CompoundButton, etc.
     */
    AndroidAccessibilityEvent["VIEW_CLICKED"] = "view_clicked";
    /**
     * Represents the event of long clicking on a android.view.View like android.widget.Button, android.widget.CompoundButton, etc.
     */
    AndroidAccessibilityEvent["VIEW_LONG_CLICKED"] = "view_long_clicked";
    /**
     * Represents the event of selecting an item usually in the context of an android.widget.AdapterView.
     */
    AndroidAccessibilityEvent["VIEW_SELECTED"] = "view_selected";
    /**
     * Represents the event of setting input focus of a android.view.View.
     */
    AndroidAccessibilityEvent["VIEW_FOCUSED"] = "view_focused";
    /**
     * Represents the event of changing the text of an android.widget.EditText.
     */
    AndroidAccessibilityEvent["VIEW_TEXT_CHANGED"] = "view_text_changed";
    /**
     * Represents the event of opening a android.widget.PopupWindow, android.view.Menu, android.app.Dialog, etc.
     */
    AndroidAccessibilityEvent["WINDOW_STATE_CHANGED"] = "window_state_changed";
    /**
     * Represents the event showing a android.app.Notification.
     */
    AndroidAccessibilityEvent["NOTIFICATION_STATE_CHANGED"] = "notification_state_changed";
    /**
     * Represents the event of a hover enter over a android.view.View.
     */
    AndroidAccessibilityEvent["VIEW_HOVER_ENTER"] = "view_hover_enter";
    /**
     * Represents the event of a hover exit over a android.view.View.
     */
    AndroidAccessibilityEvent["VIEW_HOVER_EXIT"] = "view_hover_exit";
    /**
     * Represents the event of starting a touch exploration gesture.
     */
    AndroidAccessibilityEvent["TOUCH_EXPLORATION_GESTURE_START"] = "touch_exploration_gesture_start";
    /**
     * Represents the event of ending a touch exploration gesture.
     */
    AndroidAccessibilityEvent["TOUCH_EXPLORATION_GESTURE_END"] = "touch_exploration_gesture_end";
    /**
     * Represents the event of changing the content of a window and more specifically the sub-tree rooted at the event's source.
     */
    AndroidAccessibilityEvent["WINDOW_CONTENT_CHANGED"] = "window_content_changed";
    /**
     * Represents the event of scrolling a view.
     */
    AndroidAccessibilityEvent["VIEW_SCROLLED"] = "view_scrolled";
    /**
     * Represents the event of changing the selection in an android.widget.EditText.
     */
    AndroidAccessibilityEvent["VIEW_TEXT_SELECTION_CHANGED"] = "view_text_selection_changed";
    /**
     * Represents the event of an application making an announcement.
     */
    AndroidAccessibilityEvent["ANNOUNCEMENT"] = "announcement";
    /**
     * Represents the event of gaining accessibility focus.
     */
    AndroidAccessibilityEvent["VIEW_ACCESSIBILITY_FOCUSED"] = "view_accessibility_focused";
    /**
     * Represents the event of clearing accessibility focus.
     */
    AndroidAccessibilityEvent["VIEW_ACCESSIBILITY_FOCUS_CLEARED"] = "view_accessibility_focus_cleared";
    /**
     * Represents the event of traversing the text of a view at a given movement granularity.
     */
    AndroidAccessibilityEvent["VIEW_TEXT_TRAVERSED_AT_MOVEMENT_GRANULARITY"] = "view_text_traversed_at_movement_granularity";
    /**
     * Represents the event of beginning gesture detection.
     */
    AndroidAccessibilityEvent["GESTURE_DETECTION_START"] = "gesture_detection_start";
    /**
     * Represents the event of ending gesture detection.
     */
    AndroidAccessibilityEvent["GESTURE_DETECTION_END"] = "gesture_detection_end";
    /**
     * Represents the event of the user starting to touch the screen.
     */
    AndroidAccessibilityEvent["TOUCH_INTERACTION_START"] = "touch_interaction_start";
    /**
     * Represents the event of the user ending to touch the screen.
     */
    AndroidAccessibilityEvent["TOUCH_INTERACTION_END"] = "touch_interaction_end";
    /**
     * Mask for AccessibilityEvent all types.
     */
    AndroidAccessibilityEvent["ALL_MASK"] = "all";
})(AndroidAccessibilityEvent || (AndroidAccessibilityEvent = {}));
//# sourceMappingURL=accessibility-common.js.map