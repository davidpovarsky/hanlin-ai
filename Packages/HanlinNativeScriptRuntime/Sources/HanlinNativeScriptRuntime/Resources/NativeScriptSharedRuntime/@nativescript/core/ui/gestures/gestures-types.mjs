// Shared gesture types, interfaces, and enums for gestures-common.ts and touch-manager.ts
export var GestureEvents;
(function (GestureEvents) {
    GestureEvents["gestureAttached"] = "gestureAttached";
    GestureEvents["touchDown"] = "touchDown";
    GestureEvents["touchUp"] = "touchUp";
})(GestureEvents || (GestureEvents = {}));
export var GestureTypes;
(function (GestureTypes) {
    GestureTypes[GestureTypes["tap"] = 1] = "tap";
    GestureTypes[GestureTypes["doubleTap"] = 2] = "doubleTap";
    GestureTypes[GestureTypes["pinch"] = 4] = "pinch";
    GestureTypes[GestureTypes["pan"] = 8] = "pan";
    GestureTypes[GestureTypes["swipe"] = 16] = "swipe";
    GestureTypes[GestureTypes["rotation"] = 32] = "rotation";
    GestureTypes[GestureTypes["longPress"] = 64] = "longPress";
    GestureTypes[GestureTypes["touch"] = 128] = "touch";
})(GestureTypes || (GestureTypes = {}));
export var GestureStateTypes;
(function (GestureStateTypes) {
    GestureStateTypes[GestureStateTypes["cancelled"] = 0] = "cancelled";
    GestureStateTypes[GestureStateTypes["began"] = 1] = "began";
    GestureStateTypes[GestureStateTypes["changed"] = 2] = "changed";
    GestureStateTypes[GestureStateTypes["ended"] = 3] = "ended";
})(GestureStateTypes || (GestureStateTypes = {}));
export var SwipeDirection;
(function (SwipeDirection) {
    SwipeDirection[SwipeDirection["right"] = 1] = "right";
    SwipeDirection[SwipeDirection["left"] = 2] = "left";
    SwipeDirection[SwipeDirection["up"] = 4] = "up";
    SwipeDirection[SwipeDirection["down"] = 8] = "down";
})(SwipeDirection || (SwipeDirection = {}));
export var TouchAction;
(function (TouchAction) {
    TouchAction["down"] = "down";
    TouchAction["up"] = "up";
    TouchAction["move"] = "move";
    TouchAction["cancel"] = "cancel";
})(TouchAction || (TouchAction = {}));
//# sourceMappingURL=gestures-types.js.map