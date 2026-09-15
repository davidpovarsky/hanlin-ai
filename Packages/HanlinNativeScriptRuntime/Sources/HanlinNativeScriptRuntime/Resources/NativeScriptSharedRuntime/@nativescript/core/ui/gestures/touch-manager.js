import { Animation } from '../animation';
import { isObject, isFunction } from '../../utils/types';
import { GestureEvents, GestureStateTypes, GestureTypes } from './gestures-common';
export var TouchAnimationTypes;
(function (TouchAnimationTypes) {
    TouchAnimationTypes["up"] = "up";
    TouchAnimationTypes["down"] = "down";
})(TouchAnimationTypes || (TouchAnimationTypes = {}));
/**
 * Manage interactivity in your apps easily with TouchManager.
 * Store reusable down/up animation settings for touches as well as optionally enable automatic tap (down/up) animations for your app.
 */
export class TouchManager {
    /**
     * The TouchManager uses this internally.
     * Adds touch animations to view based upon it's touchAnimation property or TouchManager.animations.
     * @param view NativeScript view instance
     */
    static addAnimations(view) {
        const handleDown = (view?.touchAnimation && (view?.touchAnimation).down) || (TouchManager.animations && TouchManager.animations.down);
        const handleUp = (view?.touchAnimation && (view?.touchAnimation).up) || (TouchManager.animations && TouchManager.animations.up);
        if (__APPLE__) {
            if (view?.ios?.addTargetActionForControlEvents) {
                // can use UIControlEvents
                if (!TouchManager.touchHandlers) {
                    TouchManager.touchHandlers = [];
                }
                TouchManager.touchHandlers.push({
                    view,
                    handler: TouchControlHandler.initWithOwner(new WeakRef(view)),
                });
                if (handleDown) {
                    view.ios.addTargetActionForControlEvents(TouchManager.touchHandlers[TouchManager.touchHandlers.length - 1].handler, GestureEvents.touchDown, 1 /* UIControlEvents.TouchDown */ | 16 /* UIControlEvents.TouchDragEnter */);
                    view.on(GestureEvents.touchDown, (args) => {
                        TouchManager.startAnimationForType(view, TouchAnimationTypes.down);
                    });
                }
                if (handleUp) {
                    view.ios.addTargetActionForControlEvents(TouchManager.touchHandlers[TouchManager.touchHandlers.length - 1].handler, GestureEvents.touchUp, 32 /* UIControlEvents.TouchDragExit */ | 256 /* UIControlEvents.TouchCancel */ | 64 /* UIControlEvents.TouchUpInside */ | 128 /* UIControlEvents.TouchUpOutside */);
                    view.on(GestureEvents.touchUp, (args) => {
                        TouchManager.startAnimationForType(view, TouchAnimationTypes.up);
                    });
                }
            }
            else {
                if (handleDown || handleUp) {
                    view.on(GestureEvents.gestureAttached, (args) => {
                        if (args.type === GestureTypes.longPress) {
                            args.ios.minimumPressDuration = args.object?.touchDelay || 0;
                        }
                    });
                    view.on(GestureTypes[GestureTypes.longPress], (args) => {
                        switch (args.state) {
                            case GestureStateTypes.began:
                                if (handleDown) {
                                    TouchManager.startAnimationForType(args.view, TouchAnimationTypes.down);
                                }
                                break;
                            case GestureStateTypes.cancelled:
                            case GestureStateTypes.ended:
                                if (handleUp) {
                                    TouchManager.startAnimationForType(args.view, TouchAnimationTypes.up);
                                }
                                break;
                        }
                    });
                }
            }
        }
        else {
            if (handleDown || handleUp) {
                view.on(GestureTypes[GestureTypes.touch], (args) => {
                    switch (args.action) {
                        case 'down':
                            if (handleDown) {
                                view.notify({
                                    eventName: GestureEvents.touchDown,
                                    object: view,
                                    data: args.android,
                                });
                            }
                            break;
                        case 'up':
                        case 'cancel':
                            if (handleUp) {
                                view.notify({
                                    eventName: GestureEvents.touchUp,
                                    object: view,
                                    data: args.android,
                                });
                            }
                            break;
                    }
                });
                if (handleDown) {
                    view.on(GestureEvents.touchDown, (args) => {
                        TouchManager.startAnimationForType(view, TouchAnimationTypes.down);
                    });
                }
                if (handleUp) {
                    view.on(GestureEvents.touchUp, (args) => {
                        TouchManager.startAnimationForType(view, TouchAnimationTypes.up);
                    });
                }
            }
        }
        view.on('disposeNativeView', (args) => {
            const index = TouchManager.touchHandlers?.findIndex((handler) => handler.view === args.object);
            if (index > -1) {
                TouchManager.touchHandlers.splice(index, 1);
            }
            TouchManager.touchAnimationDefinitions = TouchManager.touchAnimationDefinitions?.filter((d) => d.view !== args.object);
        });
    }
    static startAnimationForType(view, type) {
        if (view) {
            const animate = function (definition) {
                if (definition) {
                    if (isFunction(definition)) {
                        definition(view);
                    }
                    else {
                        if (!TouchManager.touchAnimationDefinitions) {
                            TouchManager.touchAnimationDefinitions = [];
                        }
                        // reuse animations for each type
                        let touchAnimation;
                        // triggering animations should always cancel other animations which may be in progress
                        for (const d of TouchManager.touchAnimationDefinitions) {
                            if (d.view === view && d.animation) {
                                d.animation.cancel();
                                if (d.type === type) {
                                    touchAnimation = d.animation;
                                }
                            }
                        }
                        if (!touchAnimation) {
                            touchAnimation = new Animation([
                                {
                                    target: view,
                                    ...definition,
                                },
                            ]);
                            TouchManager.touchAnimationDefinitions.push({
                                view,
                                type,
                                animation: touchAnimation,
                            });
                        }
                        touchAnimation.play().catch(() => { });
                    }
                }
            };
            // always use instance defined animation over global
            if (isObject(view.touchAnimation) && view.touchAnimation[type]) {
                animate(view.touchAnimation[type]);
            }
            else if (TouchManager.animations?.[type]) {
                // fallback to globally defined
                animate(TouchManager.animations?.[type]);
            }
        }
    }
    /**
     * The TouchManager uses this internally.
     * Adds visionOS hover styles to views based upon it's visionHoverStyle property
     * @param view NativeScript view instance
     */
    static addHoverStyle(view) {
        if (__VISIONOS__ && view?.ios) {
            if (!TouchManager.visionHoverOptions) {
                TouchManager.visionHoverOptions = {};
            }
            if (!TouchManager.visionHoverOptions['default']) {
                // Add default hoverStyle to apply everywhere (no custom hover style being defined on this view)
                TouchManager.visionHoverOptions['default'] = {
                    effect: 'automatic',
                };
            }
            if (!TouchManager.visionHoverStyleCache) {
                TouchManager.visionHoverStyleCache = {};
            }
            const createHoverStyleFromOptions = function (options) {
                let effect;
                switch (options.effect) {
                    case 'automatic':
                        effect = UIHoverAutomaticEffect.effect();
                        break;
                    case 'highlight':
                        effect = UIHoverHighlightEffect.effect();
                        break;
                    case 'lift':
                        effect = UIHoverLiftEffect.effect();
                        break;
                }
                let shape;
                switch (options.shape) {
                    case 'circle':
                        shape = UIShape.circleShape;
                        break;
                    case 'rect':
                        if (options.shapeCornerRadius) {
                            shape = UIShape.rectShapeWithCornerRadius(options.shapeCornerRadius);
                        }
                        else {
                            shape = UIShape.rectShape;
                        }
                        break;
                }
                return UIHoverStyle.styleWithEffectShape(effect, shape);
            };
            if (!TouchManager.visionHoverStyleCache['default']) {
                const defaultOptions = TouchManager.visionHoverOptions['default'];
                TouchManager.visionHoverStyleCache['default'] = createHoverStyleFromOptions(defaultOptions || {
                    effect: 'automatic',
                });
            }
            if (view.visionHoverStyle) {
                if (typeof view.visionHoverStyle === 'string') {
                    view.ios.hoverStyle = TouchManager.visionHoverStyleCache[view.visionHoverStyle] || TouchManager.visionHoverStyleCache['default'];
                }
            }
            else {
                view.ios.hoverStyle = TouchManager.visionHoverStyleCache['default'];
            }
        }
    }
}
export let TouchControlHandler;
ensureTouchControlHandlers();
function ensureTouchControlHandlers() {
    if (__APPLE__) {
        var TouchHandlerImpl = (function (_super) {
            __extends(TouchHandlerImpl, _super);
            function TouchHandlerImpl() {
                return _super !== null && _super.apply(this, arguments) || this;
            }
            TouchHandlerImpl.initWithOwner = function (owner) {
                var handler = TouchHandlerImpl.new();
                handler._owner = owner;
                return handler;
            };
            TouchHandlerImpl.prototype.touchDown = function (args) {
                var _a, _b, _c, _d;
                (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a).notify({
                    eventName: GestureEvents.touchDown,
                    object: (_d = (_c = this._owner) === null || _c === void 0 ? void 0 : _c.deref) === null || _d === void 0 ? void 0 : _d.call(_c),
                    data: args,
                });
            };
            TouchHandlerImpl.prototype.touchUp = function (args) {
                var _a, _b, _c, _d;
                (_b = (_a = this._owner) === null || _a === void 0 ? void 0 : _a.deref) === null || _b === void 0 ? void 0 : _b.call(_a).notify({
                    eventName: GestureEvents.touchUp,
                    object: (_d = (_c = this._owner) === null || _c === void 0 ? void 0 : _c.deref) === null || _d === void 0 ? void 0 : _d.call(_c),
                    data: args,
                });
            };
            TouchHandlerImpl.ObjCExposedMethods = {
                touchDown: { returns: interop.types.void, params: [interop.types.id] },
                touchUp: { returns: interop.types.void, params: [interop.types.id] },
            };
            return TouchHandlerImpl;
        }(NSObject));
        TouchControlHandler = TouchHandlerImpl;
    }
}
//# sourceMappingURL=touch-manager.js.map