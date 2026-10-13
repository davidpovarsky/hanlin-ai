#import "HanlinNativeServicesBridge.h"

@interface HanlinNativeServicesSessionBridge ()
@property(nonatomic, strong, nullable) id<HanlinNativeServicesProvider> provider;
@property(nonatomic, copy, readonly) NSString *sessionID;
- (instancetype)initWithProvider:(id<HanlinNativeServicesProvider>)provider
                        sessionID:(NSString *)sessionID;
- (void)invalidate;
@end

static id<HanlinNativeServicesProvider> _currentProvider = nil;
static NSMutableDictionary<NSString *, id<HanlinNativeServicesProvider>> *_sessionProviders = nil;
static NSMutableDictionary<NSString *, HanlinNativeServicesSessionBridge *> *_bootstrapBridges = nil;
static NSMutableDictionary<NSString *, NSMutableArray<HanlinNativeServicesSessionBridge *> *> *_boundBridges = nil;
static HanlinNativeServicesSessionBridge *_activeSessionBridge = nil;
static NSLock *_sessionLock = nil;

@implementation HanlinNativeServicesSessionBridge

- (instancetype)initWithProvider:(id<HanlinNativeServicesProvider>)provider
                        sessionID:(NSString *)sessionID {
    self = [super init];
    if (self) {
        _provider = provider;
        _sessionID = [sessionID copy];
    }
    return self;
}

- (nullable id<HanlinNativeServicesProvider>)providerSnapshot {
    @synchronized (self) { return self.provider; }
}

- (void)invalidate {
    @synchronized (self) { self.provider = nil; }
}

- (nullable NSString *)dataRootDirectory { return [[self providerSnapshot] dataRootDirectory]; }
- (nullable NSString *)stateDirectory { return [[self providerSnapshot] stateDirectory]; }
- (nullable NSString *)documentsDirectory { return [[self providerSnapshot] documentsDirectory]; }
- (nullable NSString *)cacheDirectory { return [[self providerSnapshot] cacheDirectory]; }

- (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    [provider executeJavaScript:source completion:completion];
}

- (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    [provider executeNode:source completion:completion];
}

- (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(NO, @"NativeScript Host Services session is no longer active."); return; }
    [provider nodeHealthCheckWithCompletion:completion];
}

- (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    [provider executePython:source completion:completion];
}

- (nullable NSString *)pythonVersion { return [[self providerSnapshot] pythonVersion]; }

- (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    [provider fetchURL:urlString completion:completion];
}

- (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    [provider sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON completion:completion];
}

- (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler {
    [[self providerSnapshot] registerRequestHandler:action capability:capability handler:handler];
}

@end

@implementation HanlinNativeServicesBridge

+ (void)initialize {
    if (self == [HanlinNativeServicesBridge class]) {
        _sessionProviders = [[NSMutableDictionary alloc] init];
        _bootstrapBridges = [[NSMutableDictionary alloc] init];
        _boundBridges = [[NSMutableDictionary alloc] init];
        _sessionLock = [[NSLock alloc] init];
    }
}

+ (void)registerProvider:(nullable id<HanlinNativeServicesProvider>)provider forSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    [_sessionLock lock];
    if (provider) {
        _sessionProviders[sessionID] = provider;
        if (!_currentProvider) {
            _currentProvider = provider;
        }
    } else {
        id<HanlinNativeServicesProvider> removedProvider = _sessionProviders[sessionID];
        [_sessionProviders removeObjectForKey:sessionID];
        if (_currentProvider == removedProvider) {
            _currentProvider = nil;
        }
    }
    [_sessionLock unlock];
}

+ (void)unregisterProviderForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> removedProvider = _sessionProviders[sessionID];
    [_sessionProviders removeObjectForKey:sessionID];
    if (_currentProvider == removedProvider) {
        _currentProvider = nil;
    }
    for (HanlinNativeServicesSessionBridge *bridge in _boundBridges[sessionID]) {
        [bridge invalidate];
    }
    [_boundBridges removeObjectForKey:sessionID];
    if ([_activeSessionBridge.sessionID isEqualToString:sessionID]) {
        [_activeSessionBridge invalidate];
        _activeSessionBridge = nil;
    }
    NSArray<NSString *> *tokens = [_bootstrapBridges keysOfEntriesPassingTest:
        ^BOOL(NSString *token, HanlinNativeServicesSessionBridge *bridge, BOOL *stop) {
            return [bridge.sessionID isEqualToString:sessionID];
        }].allObjects;
    for (NSString *tok in tokens) {
        [_bootstrapBridges[tok] invalidate];
    }
    [_bootstrapBridges removeObjectsForKeys:tokens];
    [_sessionLock unlock];
}

+ (nullable id<HanlinNativeServicesProvider>)providerForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return nil;
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> provider = _sessionProviders[sessionID];
    [_sessionLock unlock];
    return provider;
}

+ (nullable HanlinNativeServicesSessionBridge *)claimSessionBridgeWithToken:(NSString *)token {
    if (token.length == 0) return nil;
    [_sessionLock lock];
    HanlinNativeServicesSessionBridge *bridge = _bootstrapBridges[token];
    [_bootstrapBridges removeObjectForKey:token];
    if (bridge) {
        NSMutableArray<HanlinNativeServicesSessionBridge *> *bridges = _boundBridges[bridge.sessionID];
        if (!bridges) {
            bridges = [[NSMutableArray alloc] init];
            _boundBridges[bridge.sessionID] = bridges;
        }
        [bridges addObject:bridge];
    }
    [_sessionLock unlock];
    return bridge;
}

+ (void)setActiveSessionBridge:(nullable HanlinNativeServicesSessionBridge *)bridge forSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    [_sessionLock lock];
    _activeSessionBridge = bridge;
    if (bridge) {
        _currentProvider = [bridge providerSnapshot];
    }
    [_sessionLock unlock];
}

+ (void)clearActiveSessionBridgeForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    [_sessionLock lock];
    if ([_activeSessionBridge.sessionID isEqualToString:sessionID]) {
        _activeSessionBridge = nil;
    }
    [_sessionLock unlock];
}

+ (nullable HanlinNativeServicesSessionBridge *)activeSessionBridge {
    [_sessionLock lock];
    HanlinNativeServicesSessionBridge *bridge = _activeSessionBridge;
    [_sessionLock unlock];
    return bridge;
}

+ (void)registerProvider:(nullable id<HanlinNativeServicesProvider>)provider {
    [_sessionLock lock];
    _currentProvider = provider;
    [_sessionLock unlock];
}

+ (nullable id<HanlinNativeServicesProvider>)currentProvider {
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> provider = nil;
    if (_activeSessionBridge) {
        provider = [_activeSessionBridge providerSnapshot];
    }
    if (!provider && !_activeSessionBridge) {
        provider = _currentProvider;
    }
    [_sessionLock unlock];
    return provider;
}

+ (nullable NSString *)dataRootDirectory { return [[self currentProvider] dataRootDirectory]; }
+ (nullable NSString *)stateDirectory { return [[self currentProvider] stateDirectory]; }
+ (nullable NSString *)documentsDirectory { return [[self currentProvider] documentsDirectory]; }
+ (nullable NSString *)cacheDirectory { return [[self currentProvider] cacheDirectory]; }

+ (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [provider executeJavaScript:source completion:completion];
}

+ (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [provider executeNode:source completion:completion];
}

+ (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { if (completion) completion(NO, @"Host service provider not registered."); return; }
    [provider nodeHealthCheckWithCompletion:completion];
}

+ (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [provider executePython:source completion:completion];
}

+ (nullable NSString *)pythonVersion { return [[self currentProvider] pythonVersion]; }

+ (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [provider fetchURL:urlString completion:completion];
}

+ (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [provider sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON completion:completion];
}

+ (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) {
        NSLog(@"[HanlinNativeServicesBridge] Cannot register request handler: provider not registered.");
        return;
    }
    [provider registerRequestHandler:action capability:capability handler:handler];
}

typedef void (^HanlinSyncWorkBlock)(void (^done)(NSString * _Nullable res, NSString * _Nullable err));

static NSString *HanlinExecuteSyncWithTimeout(NSTimeInterval timeoutSeconds, HanlinSyncWorkBlock workBlock) {
    __block NSString *resultStr = nil;
    __block NSString *errorStr = nil;
    __block BOOL finished = NO;

    if (![NSThread isMainThread]) {
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        workBlock(^(NSString * _Nullable res, NSString * _Nullable err) {
            resultStr = res;
            errorStr = err;
            finished = YES;
            dispatch_semaphore_signal(sema);
        });
        long timeout = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)));
        if (timeout != 0 && !finished) {
            return [NSString stringWithFormat:@"Err: Execution timed out after %.0fs", timeoutSeconds];
        }
    } else {
        workBlock(^(NSString * _Nullable res, NSString * _Nullable err) {
            resultStr = res;
            errorStr = err;
            finished = YES;
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];
        while (!finished && [deadline timeIntervalSinceNow] > 0) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
        }
        if (!finished) {
            return [NSString stringWithFormat:@"Err: Execution timed out after %.0fs", timeoutSeconds];
        }
    }

    if (errorStr.length > 0) {
        return [NSString stringWithFormat:@"Err: %@", errorStr];
    }
    return resultStr ?: @"";
}

+ (nullable NSString *)executeJavaScriptSync:(NSString *)source {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { return @"Err: Host service provider not registered."; }
    return HanlinExecuteSyncWithTimeout(20.0, ^(void (^done)(NSString * _Nullable res, NSString * _Nullable err)) {
        [self executeJavaScript:source completion:done];
    });
}

+ (nullable NSString *)executeNodeSync:(NSString *)source {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { return @"Err: Host service provider not registered."; }
    return HanlinExecuteSyncWithTimeout(20.0, ^(void (^done)(NSString * _Nullable res, NSString * _Nullable err)) {
        [self executeNode:source completion:done];
    });
}

+ (nullable NSString *)executePythonSync:(NSString *)source {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { return @"Err: Host service provider not registered."; }
    return HanlinExecuteSyncWithTimeout(20.0, ^(void (^done)(NSString * _Nullable res, NSString * _Nullable err)) {
        [self executePython:source completion:done];
    });
}

+ (nullable NSString *)fetchURLSync:(NSString *)urlString {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { return @"Err: Host service provider not registered."; }
    return HanlinExecuteSyncWithTimeout(20.0, ^(void (^done)(NSString * _Nullable res, NSString * _Nullable err)) {
        [self fetchURL:urlString completion:done];
    });
}

+ (nullable NSString *)sendRequestSync:(NSString *)targetID
                                action:(NSString *)action
                            capability:(NSString *)capability
                           payloadJSON:(NSString *)payloadJSON {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) { return @"Err: Host service provider not registered."; }
    return HanlinExecuteSyncWithTimeout(20.0, ^(void (^done)(NSString * _Nullable res, NSString * _Nullable err)) {
        [self sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON completion:done];
    });
}

+ (void)registerAction:(NSString *)action capability:(NSString *)capability {
    id<HanlinNativeServicesProvider> provider = [self currentProvider];
    if (!provider) {
        NSLog(@"[HanlinNativeServicesBridge] Cannot register action: provider not registered.");
        return;
    }
    if ([provider respondsToSelector:@selector(registerAction:capability:)]) {
        [(id)provider registerAction:action capability:capability];
    }
}

@end

/// Internal host-only entry point used by the NativeScript runtime wrapper.
/// It returns a one-time token, never a caller-selectable session identifier.
NSString * _Nullable HanlinNativeServicesPrepareSessionBootstrap(NSString *sessionID) {
    if (sessionID.length == 0) return nil;
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> provider = _sessionProviders[sessionID];
    if (!provider) {
        [_sessionLock unlock];
        return nil;
    }
    NSString *token = NSUUID.UUID.UUIDString.lowercaseString;
    _bootstrapBridges[token] = [[HanlinNativeServicesSessionBridge alloc] initWithProvider:provider sessionID:sessionID];
    [_sessionLock unlock];
    return token;
}
