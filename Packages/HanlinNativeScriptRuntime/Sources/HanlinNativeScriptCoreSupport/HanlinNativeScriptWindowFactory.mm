#import "HanlinNativeScriptCoreSupport.h"
#import <exception>

@interface HanlinNativeScriptPresenter (WindowFactoryPresentation)
- (id)presentNativeScriptApp:(UIViewController *)viewController;
@end

@class HanlinNativeScriptWindowSurfaceView;
@interface HanlinNativeScriptWindowContext ()
@property(nonatomic, readwrite, copy) NSString *windowID;
@property(nonatomic, readwrite, strong) HanlinNativeServicesSessionBridge *servicesBridge;
@property(nonatomic, readwrite, strong) UIViewController *containerController;
@property(nonatomic, readwrite, getter=isClosed) BOOL closed;
@property(nonatomic, strong) HanlinNativeScriptPresenter *presenter;
@property(nonatomic, strong) HanlinNativeScriptWindowSurfaceView *surfaceObserver;
@property(nonatomic, weak, nullable) UIWindow *surface;
@property(nonatomic, weak, nullable) UIWindowScene *windowScene;
@property(nonatomic, copy, nullable) HanlinNativeScriptWindowLifecycleBlock lifecycleHandler;
- (instancetype)initWithID:(NSString *)windowID bridge:(HanlinNativeServicesSessionBridge *)bridge;
- (void)surfaceDidChange:(nullable UIWindow *)window;
- (void)close;
@end

@interface HanlinNativeScriptWindowSurfaceView : UIView
@property(nonatomic, weak) HanlinNativeScriptWindowContext *context;
@end
@implementation HanlinNativeScriptWindowSurfaceView
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.context surfaceDidChange:self.window];
}
@end

@implementation HanlinNativeScriptWindowContext
- (instancetype)initWithID:(NSString *)windowID bridge:(HanlinNativeServicesSessionBridge *)bridge {
    self = [super init];
    if (self) {
        _windowID = [windowID copy];
        _servicesBridge = bridge;
        _presenter = [[HanlinNativeScriptPresenter alloc] init];
        // Deliberately do not install this presenter as the global embedder delegate.
        _containerController = _presenter.containerController;
        _surfaceObserver = [[HanlinNativeScriptWindowSurfaceView alloc] initWithFrame:CGRectZero];
        _surfaceObserver.context = self;
        _surfaceObserver.userInteractionEnabled = NO;
        _surfaceObserver.accessibilityElementsHidden = YES;
        [_containerController.view addSubview:_surfaceObserver];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(sceneDidDisconnect:) name:UISceneDidDisconnectNotification object:nil];
        [center addObserver:self selector:@selector(sceneDidActivate:) name:UISceneDidActivateNotification object:nil];
        [center addObserver:self selector:@selector(sceneWillDeactivate:) name:UISceneWillDeactivateNotification object:nil];
        [center addObserver:self selector:@selector(sceneDidEnterBackground:) name:UISceneDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(sceneWillEnterForeground:) name:UISceneWillEnterForegroundNotification object:nil];
    }
    return self;
}
- (void)presentViewController:(UIViewController *)controller {
    NSAssert(NSThread.isMainThread, @"NativeScript window presentation belongs to the main thread.");
    if (self.closed) { return; }
    [self.presenter presentNativeScriptApp:controller];
    [self surfaceDidChange:self.containerController.view.window];
}
- (void)setLifecycleHandler:(HanlinNativeScriptWindowLifecycleBlock)handler {
    if (self.closed) { return; }
    _lifecycleHandler = [handler copy];
    [self surfaceDidChange:self.containerController.view.window];
}
- (void)surfaceDidChange:(UIWindow *)window {
    if (self.closed || !window) {
        // A covering full-screen modal can temporarily remove a view from its
        // window. Only actual scene disconnect/lease close tears down NS content.
        return;
    }
    BOOL changed = self.surface != window || self.windowScene != window.windowScene;
    self.surface = window;
    self.windowScene = window.windowScene;
    if (self.lifecycleHandler) {
        self.lifecycleHandler(changed ? @"attached" : @"surface", window);
        if (window.windowScene.activationState == UISceneActivationStateForegroundActive) {
            self.lifecycleHandler(@"activate", window);
        }
    }
}
- (void)sendSceneEvent:(NSString *)event notification:(NSNotification *)notification {
    if (!self.closed && notification.object == self.windowScene && self.lifecycleHandler) {
        self.lifecycleHandler(event, self.surface);
    }
}
- (void)sceneDidDisconnect:(NSNotification *)note { [self sendSceneEvent:@"detached" notification:note]; }
- (void)sceneDidActivate:(NSNotification *)note { [self sendSceneEvent:@"activate" notification:note]; }
- (void)sceneWillDeactivate:(NSNotification *)note { [self sendSceneEvent:@"deactivate" notification:note]; }
- (void)sceneDidEnterBackground:(NSNotification *)note { [self sendSceneEvent:@"background" notification:note]; }
- (void)sceneWillEnterForeground:(NSNotification *)note { [self sendSceneEvent:@"foreground" notification:note]; }
- (void)showFailure:(NSString *)message {
    if (self.closed) { return; }
    UIViewController *controller = [[UIViewController alloc] init];
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.accessibilityIdentifier = @"hanlin-nativescript-window-error";
    controller.view = label;
    [self presentViewController:controller];
}
- (void)close {
    if (self.closed) { return; }
    self.closed = YES;
    HanlinNativeScriptWindowLifecycleBlock handler = self.lifecycleHandler;
    self.lifecycleHandler = nil;
    @try {
        if (handler) { handler(@"close", self.surface); }
    } @finally {
        [NSNotificationCenter.defaultCenter removeObserver:self];
        self.surfaceObserver.context = nil;
        [self.presenter detach];
        [self.servicesBridge invalidate];
        self.surface = nil;
        self.windowScene = nil;
    }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

static NSString *HanlinFactoryRuntimeID;
static NSString *HanlinFactoryLastFailure;
static HanlinNativeScriptWindowFactoryBlock HanlinFactory;
static NSMutableDictionary<NSString *, HanlinNativeScriptWindowContext *> *HanlinFactoryWindows;

@implementation HanlinNativeScriptWindowFactoryRegistry
+ (BOOL)beginRuntimeSessionID:(NSString *)sessionID {
    NSAssert(NSThread.isMainThread, @"Factory runtime ownership belongs to the main thread.");
    if (HanlinFactoryRuntimeID || sessionID.length == 0) {
        HanlinFactoryLastFailure = @"Another NativeScript factory runtime is already active.";
        return NO;
    }
    HanlinFactoryRuntimeID = [sessionID copy];
    HanlinFactoryWindows = [[NSMutableDictionary alloc] init];
    HanlinFactoryLastFailure = nil;
    return YES;
}
+ (BOOL)registerFactory:(HanlinNativeScriptWindowFactoryBlock)factory {
    NSAssert(NSThread.isMainThread, @"Factory registration belongs to the main thread.");
    if (!HanlinFactoryRuntimeID || HanlinFactory || !factory) {
        HanlinFactoryLastFailure = @"The active runtime must register exactly one window factory.";
        return NO;
    }
    HanlinFactory = [factory copy];
    return YES;
}
+ (BOOL)hasFactoryForRuntimeSessionID:(NSString *)sessionID {
    return [HanlinFactoryRuntimeID isEqualToString:sessionID] && HanlinFactory != nil;
}
+ (HanlinNativeScriptWindowContext *)openWindowWithID:(NSString *)windowID
                                              bridge:(HanlinNativeServicesSessionBridge *)bridge {
    NSAssert(NSThread.isMainThread, @"Factory windows belong to the main thread.");
    if (!HanlinFactory || HanlinFactoryWindows[windowID] || !bridge || windowID.length == 0) {
        HanlinFactoryLastFailure = @"The window factory or its unique context is unavailable.";
        return nil;
    }
    HanlinNativeScriptWindowContext *context =
        [[HanlinNativeScriptWindowContext alloc] initWithID:windowID bridge:bridge];
    HanlinFactoryWindows[windowID] = context;
    BOOL succeeded = NO;
    try {
        @try {
            HanlinFactory(context);
            succeeded = YES;
        } @catch (NSException *exception) {
            HanlinFactoryLastFailure = exception.reason ?: @"The NativeScript window factory failed.";
        }
    } catch (const std::exception &exception) {
        HanlinFactoryLastFailure = [NSString stringWithUTF8String:exception.what()];
    } catch (...) {
        HanlinFactoryLastFailure = @"The NativeScript window factory raised a runtime exception.";
    }
    if (!succeeded) {
        [self closeWindowWithID:windowID];
        return nil;
    }
    return context;
}
+ (void)closeWindowWithID:(NSString *)windowID {
    NSAssert(NSThread.isMainThread, @"Factory window cleanup belongs to the main thread.");
    HanlinNativeScriptWindowContext *context = HanlinFactoryWindows[windowID];
    if (!context) { return; }
    [HanlinFactoryWindows removeObjectForKey:windowID];
    try {
        @try { [context close]; }
        @catch (NSException *exception) {
            HanlinFactoryLastFailure = exception.reason ?: @"NativeScript window cleanup failed.";
        }
    } catch (...) {
        HanlinFactoryLastFailure = @"NativeScript window cleanup raised a runtime exception.";
    }
}
+ (void)endRuntimeSessionID:(NSString *)sessionID {
    NSAssert(NSThread.isMainThread, @"Factory runtime cleanup belongs to the main thread.");
    if (![HanlinFactoryRuntimeID isEqualToString:sessionID]) { return; }
    for (NSString *windowID in HanlinFactoryWindows.allKeys) { [self closeWindowWithID:windowID]; }
    // Release JS-originated blocks while their VM is still alive.
    HanlinFactory = nil;
    HanlinFactoryWindows = nil;
    HanlinFactoryRuntimeID = nil;
}
+ (NSString *)lastFailure { return HanlinFactoryLastFailure; }
+ (NSUInteger)openWindowCount { return HanlinFactoryWindows.count; }
@end
