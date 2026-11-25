#import "HanlinNativeScriptCoreSupport.h"
#import <exception>

@interface HanlinNativeScriptPresenter (WindowFactoryPresentation)
- (id)presentNativeScriptApp:(UIViewController *)viewController;
@end

@class HanlinNativeScriptWindowSurfaceView;
@interface HanlinNativeScriptWindowContext ()
@property(nonatomic, readwrite, copy) NSString *windowID;
@property(nonatomic, readwrite, copy) NSString *packageID;
@property(nonatomic, readwrite, copy) NSString *applicationRoot;
@property(nonatomic, readwrite, copy) NSString *environmentJSON;
@property(nonatomic, readwrite, copy, nullable) NSString *styleSheetPath;
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
- (NSString *)resourcePath:(NSString *)relativePath {
    if (self.closed || !relativePath.length || [relativePath hasPrefix:@"/"] ||
        [relativePath rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) { return nil; }
    NSString *root = [self.applicationRoot stringByResolvingSymlinksInPath];
    NSString *candidate = [[self.applicationRoot stringByAppendingPathComponent:relativePath]
                            stringByResolvingSymlinksInPath];
    if (![candidate hasPrefix:[root stringByAppendingString:@"/"]]) { return nil; }
    return candidate;
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
    // The public setter rejects updates after closed=true. Clear the ivar
    // directly so no JS-originated lifecycle block survives VM teardown.
    _lifecycleHandler = nil;
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

/// This provider intentionally owns no app capabilities or paths. Selecting a
/// default package for the process-global bridge would cross window boundaries.
@interface HanlinNativeScriptNeutralServicesProvider : NSObject <HanlinNativeServicesProvider>
@end
@implementation HanlinNativeScriptNeutralServicesProvider
- (NSString *)executeRuntime:(NSString *)json completion:(HanlinBridgeStringResultBlock)completion {
    completion(nil, @"Use this window's explicit Host Services context."); return nil;
}
- (BOOL)cancelRuntime:(NSString *)requestID { return NO; }
- (void)invalidateRuntimeRequests {}
- (NSString *)dataRootDirectory { return nil; }
- (NSString *)stateDirectory { return nil; }
- (NSString *)documentsDirectory { return nil; }
- (NSString *)cacheDirectory { return nil; }
- (NSString *)pythonVersion { return nil; }
- (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    completion(nil, @"Use this window's explicit Host Services context.");
}
- (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    completion(nil, @"Use this window's explicit Host Services context.");
}
- (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    completion(NO, @"Use this window's explicit Host Services context.");
}
- (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    completion(nil, @"Use this window's explicit Host Services context.");
}
- (void)fetchURL:(NSString *)url completion:(HanlinBridgeStringResultBlock)completion {
    completion(nil, @"Use this window's explicit Host Services context.");
}
- (void)sendRequest:(NSString *)target action:(NSString *)action capability:(NSString *)capability
        payloadJSON:(NSString *)payload completion:(HanlinBridgeStringResultBlock)completion {
    completion(nil, @"Use this window's explicit Host Services context.");
}
- (void)registerRequestHandler:(NSString *)action capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler {
    // No process-global application handler is registered or retained.
}
@end

static NSString *HanlinFactoryRuntimeID;
static NSString *HanlinFactoryLastFailure;
static HanlinNativeScriptWindowFactoryBlock HanlinFactory;
static HanlinNativeScriptPackageLoaderBlock HanlinPackageLoader;
static NSString *HanlinFactoryLoadingWindowID;
static NSMutableDictionary<NSString *, HanlinNativeScriptWindowFactoryBlock> *HanlinPackageFactories;
static NSMutableDictionary<NSString *, HanlinNativeScriptWindowContext *> *HanlinFactoryWindows;

@implementation HanlinNativeScriptWindowFactoryRegistry
+ (id<HanlinNativeServicesProvider>)neutralRuntimeProvider { return [[HanlinNativeScriptNeutralServicesProvider alloc] init]; }
+ (BOOL)beginRuntimeSessionID:(NSString *)sessionID {
    NSAssert(NSThread.isMainThread, @"Factory runtime ownership belongs to the main thread.");
    if (HanlinFactoryRuntimeID || sessionID.length == 0) {
        HanlinFactoryLastFailure = @"Another NativeScript factory runtime is already active.";
        return NO;
    }
    HanlinFactoryRuntimeID = [sessionID copy];
    HanlinFactoryWindows = [[NSMutableDictionary alloc] init];
    HanlinPackageFactories = [[NSMutableDictionary alloc] init];
    HanlinFactoryLastFailure = nil;
    return YES;
}
+ (BOOL)registerFactory:(HanlinNativeScriptWindowFactoryBlock)factory {
    NSAssert(NSThread.isMainThread, @"Factory registration belongs to the main thread.");
    if (!HanlinFactoryRuntimeID || !factory) {
        HanlinFactoryLastFailure = @"Window factory registration requires its original runtime.";
        return NO;
    }
    if (HanlinPackageLoader) {
        NSString *windowID = HanlinFactoryLoadingWindowID;
        if (!windowID || HanlinPackageFactories[windowID]) {
            HanlinFactoryLastFailure = @"A package must register exactly one factory while its own entry loads.";
            return NO;
        }
        HanlinPackageFactories[windowID] = [factory copy];
    } else {
        if (HanlinFactory) {
            HanlinFactoryLastFailure = @"The legacy runtime already registered its window factory.";
            return NO;
        }
        HanlinFactory = [factory copy];
    }
    return YES;
}
+ (BOOL)registerPackageLoader:(HanlinNativeScriptPackageLoaderBlock)loader {
    NSAssert(NSThread.isMainThread, @"Package loader registration belongs to the main thread.");
    if (!HanlinFactoryRuntimeID || HanlinPackageLoader || HanlinFactory || !loader) {
        HanlinFactoryLastFailure = @"The neutral runtime must register exactly one package loader.";
        return NO;
    }
    HanlinPackageLoader = [loader copy];
    return YES;
}
+ (BOOL)loadPackageForWindowID:(NSString *)windowID configurationJSON:(NSString *)configurationJSON {
    NSAssert(NSThread.isMainThread, @"Package loading belongs to the main thread.");
    if (!HanlinPackageLoader || HanlinFactoryLoadingWindowID || !windowID.length ||
        HanlinPackageFactories[windowID] || HanlinFactoryWindows[windowID]) {
        HanlinFactoryLastFailure = @"The package load or its unique window namespace is unavailable.";
        return NO;
    }
    HanlinFactoryLoadingWindowID = [windowID copy];
    BOOL succeeded = NO;
    try {
        @try {
            HanlinPackageLoader(configurationJSON);
            succeeded = HanlinPackageFactories[windowID] != nil;
            if (!succeeded) {
                HanlinFactoryLastFailure = @"The isolated entry did not register its window factory.";
            }
        } @catch (NSException *exception) {
            HanlinFactoryLastFailure = exception.reason ?: @"The original NativeScript package loader failed.";
        }
    } catch (const std::exception &exception) {
        HanlinFactoryLastFailure = [NSString stringWithUTF8String:exception.what()];
    } catch (...) {
        HanlinFactoryLastFailure = @"The original NativeScript package loader raised a runtime exception.";
    }
    HanlinFactoryLoadingWindowID = nil;
    if (!succeeded) { [HanlinPackageFactories removeObjectForKey:windowID]; }
    return succeeded;
}
+ (BOOL)hasFactoryForRuntimeSessionID:(NSString *)sessionID {
    return [HanlinFactoryRuntimeID isEqualToString:sessionID] && (HanlinFactory != nil || HanlinPackageLoader != nil);
}
+ (HanlinNativeScriptWindowContext *)openWindowWithID:(NSString *)windowID
                                              bridge:(HanlinNativeServicesSessionBridge *)bridge {
    return [self openWindowWithID:windowID bridge:bridge packageID:@""
                 applicationRoot:@"" environmentJSON:@"{}" styleSheetPath:nil];
}
+ (HanlinNativeScriptWindowContext *)openWindowWithID:(NSString *)windowID
                                              bridge:(HanlinNativeServicesSessionBridge *)bridge
                                           packageID:(NSString *)packageID
                                     applicationRoot:(NSString *)applicationRoot
                                     environmentJSON:(NSString *)environmentJSON
                                      styleSheetPath:(NSString *)styleSheetPath {
    NSAssert(NSThread.isMainThread, @"Factory windows belong to the main thread.");
    HanlinNativeScriptWindowFactoryBlock factory = HanlinPackageFactories[windowID] ?: HanlinFactory;
    if (!factory || HanlinFactoryWindows[windowID] || !bridge || windowID.length == 0) {
        HanlinFactoryLastFailure = @"The window factory or its unique context is unavailable.";
        return nil;
    }
    HanlinNativeScriptWindowContext *context =
        [[HanlinNativeScriptWindowContext alloc] initWithID:windowID bridge:bridge];
    context.packageID = packageID;
    context.applicationRoot = applicationRoot;
    context.environmentJSON = environmentJSON;
    context.styleSheetPath = styleSheetPath;
    HanlinFactoryWindows[windowID] = context;
    BOOL succeeded = NO;
    try {
        @try {
            factory(context);
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
    [HanlinPackageFactories removeObjectForKey:windowID];
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
    HanlinPackageLoader = nil;
    HanlinFactoryLoadingWindowID = nil;
    HanlinPackageFactories = nil;
    HanlinFactoryWindows = nil;
    HanlinFactoryRuntimeID = nil;
}
+ (NSString *)lastFailure { return HanlinFactoryLastFailure; }
+ (NSUInteger)openWindowCount { return HanlinFactoryWindows.count; }
@end
