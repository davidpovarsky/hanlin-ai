#import "HanlinNativeServicesBridge.h"
#import <dispatch/dispatch.h>

@class HanlinNativeServicesPendingCallback;
typedef void (^HanlinPendingResultBlock)(id _Nullable value, NSString * _Nullable error);

@interface HanlinNativeServicesSessionBridge ()
@property(nonatomic, strong, nullable) id<HanlinNativeServicesProvider> provider;
@property(nonatomic, copy, readonly) NSString *sessionID;
@property(nonatomic, strong) NSMutableSet<HanlinNativeServicesPendingCallback *> *pendingCallbacks;
- (instancetype)initWithProvider:(id<HanlinNativeServicesProvider>)provider
                        sessionID:(NSString *)sessionID;
- (void)removePendingCallback:(HanlinNativeServicesPendingCallback *)callback;
- (nullable id<HanlinNativeServicesProvider>)detachCompletions;
@end

@interface HanlinNativeServicesBridge ()
+ (void)retireSessionID:(NSString *)sessionID
      expectedProvider:(nullable id<HanlinNativeServicesProvider>)expectedProvider
          sourceBridge:(nullable HanlinNativeServicesSessionBridge *)sourceBridge;
@end

/// Native work retains this box, never a JS completion directly. The bridge
/// detaches its JS block synchronously before cancelling its provider's work.
@interface HanlinNativeServicesPendingCallback : NSObject
@property(nonatomic, weak) HanlinNativeServicesSessionBridge *owner;
@property(nonatomic, copy, nullable) HanlinPendingResultBlock completion;
- (void)deliverValue:(nullable id)value error:(nullable NSString *)error;
- (void)invalidate;
@end

@implementation HanlinNativeServicesPendingCallback
- (void)deliverValue:(nullable id)value error:(nullable NSString *)error {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self deliverValue:value error:error]; });
        return;
    }
    HanlinPendingResultBlock completion;
    @synchronized (self) {
        completion = self.completion;
        self.completion = nil;
    }
    [self.owner removePendingCallback:self];
    if (completion) completion(value, error);
}
- (void)invalidate {
    __attribute__((objc_precise_lifetime)) HanlinPendingResultBlock retired;
    @synchronized (self) {
        retired = _completion;
        _completion = nil;
    }
    // Keep destruction of any captured JS function outside the object monitor.
    (void)retired;
}
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
        _pendingCallbacks = [NSMutableSet new];
    }
    return self;
}

- (nullable id<HanlinNativeServicesProvider>)providerSnapshot {
    @synchronized (self) { return self.provider; }
}

- (nullable HanlinNativeServicesPendingCallback *)trackCompletion:(HanlinPendingResultBlock)completion
                                                        provider:(id<HanlinNativeServicesProvider>)provider {
    HanlinNativeServicesPendingCallback *callback = [HanlinNativeServicesPendingCallback new];
    callback.owner = self;
    callback.completion = completion;
    BOOL accepted;
    @synchronized (self) {
        accepted = self.provider == provider;
        if (accepted) [self.pendingCallbacks addObject:callback];
    }
    if (!accepted) {
        [callback invalidate];
        return nil;
    }
    return callback;
}

- (nullable HanlinNativeServicesPendingCallback *)trackStringCompletion:(HanlinBridgeStringResultBlock)completion
                                                               provider:(id<HanlinNativeServicesProvider>)provider {
    return [self trackCompletion:^(id value, NSString *error) {
        if (completion) completion((NSString *)value, error);
    } provider:provider];
}

- (void)removePendingCallback:(HanlinNativeServicesPendingCallback *)callback {
    @synchronized (self) { [self.pendingCallbacks removeObject:callback]; }
}

- (nullable id<HanlinNativeServicesProvider>)detachCompletions {
    id<HanlinNativeServicesProvider> provider;
    NSArray<HanlinNativeServicesPendingCallback *> *callbacks;
    @synchronized (self) {
        provider = self.provider;
        self.provider = nil;
        callbacks = self.pendingCallbacks.allObjects;
        [self.pendingCallbacks removeAllObjects];
    }
    for (HanlinNativeServicesPendingCallback *callback in callbacks) [callback invalidate];
    return provider;
}

- (void)invalidate {
    // Both JS invocation and VM destruction occur on the main thread. A queued
    // delivery retains only its box; the box loses its JS block before teardown.
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self invalidate]; });
        return;
    }
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) return;
    [HanlinNativeServicesBridge retireSessionID:self.sessionID
                              expectedProvider:provider sourceBridge:self];
}

- (nullable NSString *)executeRuntime:(NSString *)payloadJSON completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return nil; }
    HanlinNativeServicesPendingCallback *callback = [self trackStringCompletion:completion provider:provider];
    if (!callback) return nil;
    return [provider executeRuntime:payloadJSON completion:^(NSString *result, NSString *error) {
        [callback deliverValue:result error:error];
    }];
}

- (BOOL)cancelRuntime:(NSString *)requestID {
    return [[self providerSnapshot] cancelRuntime:requestID];
}

- (nullable NSString *)dataRootDirectory { return [[self providerSnapshot] dataRootDirectory]; }
- (nullable NSString *)stateDirectory { return [[self providerSnapshot] stateDirectory]; }
- (nullable NSString *)documentsDirectory { return [[self providerSnapshot] documentsDirectory]; }
- (nullable NSString *)cacheDirectory { return [[self providerSnapshot] cacheDirectory]; }

- (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    HanlinNativeServicesPendingCallback *callback = [self trackStringCompletion:completion provider:provider];
    if (!callback) return;
    [provider executeJavaScript:source completion:^(NSString *result, NSString *error) {
        [callback deliverValue:result error:error];
    }];
}

- (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    HanlinNativeServicesPendingCallback *callback = [self trackStringCompletion:completion provider:provider];
    if (!callback) return;
    [provider executeNode:source completion:^(NSString *result, NSString *error) {
        [callback deliverValue:result error:error];
    }];
}

- (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(NO, @"NativeScript Host Services session is no longer active."); return; }
    HanlinNativeServicesPendingCallback *callback = [self trackCompletion:^(id value, NSString *error) {
        if (completion) completion([value boolValue], error);
    } provider:provider];
    if (!callback) return;
    [provider nodeHealthCheckWithCompletion:^(BOOL success, NSString *error) {
        [callback deliverValue:@(success) error:error];
    }];
}

- (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    HanlinNativeServicesPendingCallback *callback = [self trackStringCompletion:completion provider:provider];
    if (!callback) return;
    [provider executePython:source completion:^(NSString *result, NSString *error) {
        [callback deliverValue:result error:error];
    }];
}

- (nullable NSString *)pythonVersion { return [[self providerSnapshot] pythonVersion]; }

- (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    HanlinNativeServicesPendingCallback *callback = [self trackStringCompletion:completion provider:provider];
    if (!callback) return;
    [provider fetchURL:urlString completion:^(NSString *result, NSString *error) {
        [callback deliverValue:result error:error];
    }];
}

- (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = [self providerSnapshot];
    if (!provider) { if (completion) completion(nil, @"NativeScript Host Services session is no longer active."); return; }
    HanlinNativeServicesPendingCallback *callback = [self trackStringCompletion:completion provider:provider];
    if (!callback) return;
    [provider sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON
        completion:^(NSString *result, NSString *error) { [callback deliverValue:result error:error]; }];
}

- (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler {
    [[self providerSnapshot] registerRequestHandler:action capability:capability handler:handler];
}

@end

typedef void (^HanlinSyncWorkBlock)(void (^done)(NSString * _Nullable res, NSString * _Nullable err));

@interface HanlinSyncBox : NSObject
@property(nonatomic, copy, nullable) NSString *resultStr;
@property(nonatomic, copy, nullable) NSString *errorStr;
@property(nonatomic, assign) BOOL isFinished;
@property(nonatomic, assign) BOOL hasTimedOut;
@property(nonatomic, strong) NSLock *lock;
@end

@implementation HanlinSyncBox
- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _isFinished = NO;
        _hasTimedOut = NO;
    }
    return self;
}
@end

static NSString *HanlinExecuteSyncWithTimeout(NSTimeInterval timeoutSeconds, HanlinSyncWorkBlock workBlock) {
    HanlinSyncBox *box = [[HanlinSyncBox alloc] init];

    if (![NSThread isMainThread]) {
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        workBlock(^(NSString * _Nullable res, NSString * _Nullable err) {
            [box.lock lock];
            if (!box.hasTimedOut && !box.isFinished) {
                box.resultStr = res;
                box.errorStr = err;
                box.isFinished = YES;
                [box.lock unlock];
                dispatch_semaphore_signal(sema);
            } else {
                [box.lock unlock];
            }
        });
        long timeout = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)));
        [box.lock lock];
        if (timeout != 0 && !box.isFinished) {
            box.hasTimedOut = YES;
            [box.lock unlock];
            return [NSString stringWithFormat:@"Err: Execution timed out after %.0fs", timeoutSeconds];
        }
        NSString *err = box.errorStr;
        NSString *res = box.resultStr;
        [box.lock unlock];
        if (err.length > 0) {
            return [NSString stringWithFormat:@"Err: %@", err];
        }
        return res ?: @"";
    } else {
        workBlock(^(NSString * _Nullable res, NSString * _Nullable err) {
            [box.lock lock];
            if (!box.hasTimedOut && !box.isFinished) {
                box.resultStr = res;
                box.errorStr = err;
                box.isFinished = YES;
            }
            [box.lock unlock];
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];
        BOOL finished = NO;
        while (!finished && [deadline timeIntervalSinceNow] > 0) {
            @autoreleasepool {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
            }
            [box.lock lock];
            finished = box.isFinished;
            [box.lock unlock];
        }
        [box.lock lock];
        if (!box.isFinished) {
            box.hasTimedOut = YES;
            [box.lock unlock];
            return [NSString stringWithFormat:@"Err: Execution timed out after %.0fs", timeoutSeconds];
        }
        NSString *err = box.errorStr;
        NSString *res = box.resultStr;
        [box.lock unlock];
        if (err.length > 0) {
            return [NSString stringWithFormat:@"Err: %@", err];
        }
        return res ?: @"";
    }
}

@implementation HanlinNativeServicesBridge

+ (nullable NSString *)executeRuntime:(NSString *)payloadJSON completion:(HanlinBridgeStringResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(nil, @"Host service provider not registered."); return nil; }
    return [bridge executeRuntime:payloadJSON completion:completion];
}

+ (BOOL)cancelRuntime:(NSString *)requestID {
    return [[self activeSessionBridge] cancelRuntime:requestID];
}

- (nullable NSString *)executeRuntime:(NSString *)payloadJSON completion:(HanlinBridgeStringResultBlock)completion {
    return [self.class executeRuntime:payloadJSON completion:completion];
}

- (BOOL)cancelRuntime:(NSString *)requestID {
    return [self.class cancelRuntime:requestID];
}

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
    } else {
        [_sessionProviders removeObjectForKey:sessionID];
    }
    [_sessionLock unlock];
}

// Retire every bridge before cancelling any provider. One provider may have
// multiple claimed bridges; cancellation can synchronously complete them all.
+ (void)retireSessionID:(NSString *)sessionID
      expectedProvider:(nullable id<HanlinNativeServicesProvider>)expectedProvider
          sourceBridge:(nullable HanlinNativeServicesSessionBridge *)sourceBridge {
    NSMutableSet<HanlinNativeServicesSessionBridge *> *retired = [NSMutableSet new];
    NSHashTable<id<HanlinNativeServicesProvider>> *providers = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> registered = _sessionProviders[sessionID];
    BOOL preservingReplacement = expectedProvider && registered != expectedProvider;
    if (!preservingReplacement) {
        if (registered) [providers addObject:registered];
        [_sessionProviders removeObjectForKey:sessionID];
    }
    // A stale bridge retires all bridges of its old provider, while preserving
    // a replacement registered under the same ID and that replacement's bridges.
    NSMutableArray<HanlinNativeServicesSessionBridge *> *kept = [NSMutableArray new];
    for (HanlinNativeServicesSessionBridge *bridge in _boundBridges[sessionID]) {
        if (preservingReplacement && [bridge providerSnapshot] != expectedProvider) [kept addObject:bridge];
        else [retired addObject:bridge];
    }
    if (kept.count) _boundBridges[sessionID] = kept;
    else [_boundBridges removeObjectForKey:sessionID];
    if ([_activeSessionBridge.sessionID isEqualToString:sessionID] &&
        (!preservingReplacement || [_activeSessionBridge providerSnapshot] == expectedProvider)) {
        [retired addObject:_activeSessionBridge];
        _activeSessionBridge = nil;
    }
    NSArray<NSString *> *tokens = [_bootstrapBridges keysOfEntriesPassingTest:
        ^BOOL(NSString *token, HanlinNativeServicesSessionBridge *bridge, BOOL *stop) {
            return [bridge.sessionID isEqualToString:sessionID] &&
                (!preservingReplacement || [bridge providerSnapshot] == expectedProvider);
        }].allObjects;
    for (NSString *tok in tokens) [retired addObject:_bootstrapBridges[tok]];
    [_bootstrapBridges removeObjectsForKeys:tokens];
    [_sessionLock unlock];
    if (sourceBridge) [retired addObject:sourceBridge];
    for (HanlinNativeServicesSessionBridge *bridge in retired) {
        id<HanlinNativeServicesProvider> provider = [bridge detachCompletions];
        if (provider) [providers addObject:provider];
    }
    for (id<HanlinNativeServicesProvider> provider in providers) [provider invalidateRuntimeRequests];
}

+ (void)unregisterProviderForSessionID:(NSString *)sessionID {
    if (sessionID.length == 0) return;
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self unregisterProviderForSessionID:sessionID]; });
        return;
    }
    [self retireSessionID:sessionID expectedProvider:nil sourceBridge:nil];
}

+ (void)resetAllSessions {
    if (![NSThread isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self resetAllSessions]; });
        return;
    }
    NSMutableSet<HanlinNativeServicesSessionBridge *> *retired = [NSMutableSet new];
    NSHashTable<id<HanlinNativeServicesProvider>> *providers = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
    [_sessionLock lock];
    for (id<HanlinNativeServicesProvider> provider in _sessionProviders.allValues) [providers addObject:provider];
    if (_currentProvider) [providers addObject:_currentProvider];
    [_sessionProviders removeAllObjects];
    for (NSArray<HanlinNativeServicesSessionBridge *> *bridges in _boundBridges.allValues) {
        [retired addObjectsFromArray:bridges];
    }
    [_boundBridges removeAllObjects];
    [retired addObjectsFromArray:_bootstrapBridges.allValues];
    [_bootstrapBridges removeAllObjects];
    if (_activeSessionBridge) [retired addObject:_activeSessionBridge];
    _activeSessionBridge = nil;
    _currentProvider = nil;
    [_sessionLock unlock];
    for (HanlinNativeServicesSessionBridge *bridge in retired) {
        id<HanlinNativeServicesProvider> provider = [bridge detachCompletions];
        if (provider) [providers addObject:provider];
    }
    for (id<HanlinNativeServicesProvider> provider in providers) [provider invalidateRuntimeRequests];
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

+ (void)clearLegacyProviderIfMatches:(id<HanlinNativeServicesProvider>)provider {
    [_sessionLock lock];
    if (_currentProvider == provider) {
        _currentProvider = nil;
    }
    [_sessionLock unlock];
}

+ (nullable id<HanlinNativeServicesProvider>)legacyProvider {
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> p = _currentProvider;
    [_sessionLock unlock];
    return p;
}

+ (nullable id<HanlinNativeServicesProvider>)currentProvider {
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> provider = nil;
    if (_activeSessionBridge) {
        provider = [_activeSessionBridge providerSnapshot];
    }
    [_sessionLock unlock];
    return provider;
}

+ (nullable NSString *)dataRootDirectory { return [[self currentProvider] dataRootDirectory]; }
+ (nullable NSString *)stateDirectory { return [[self currentProvider] stateDirectory]; }
+ (nullable NSString *)documentsDirectory { return [[self currentProvider] documentsDirectory]; }
+ (nullable NSString *)cacheDirectory { return [[self currentProvider] cacheDirectory]; }

+ (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [bridge executeJavaScript:source completion:completion];
}

+ (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [bridge executeNode:source completion:completion];
}

+ (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(NO, @"Host service provider not registered."); return; }
    [bridge nodeHealthCheckWithCompletion:completion];
}

+ (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [bridge executePython:source completion:completion];
}

+ (nullable NSString *)pythonVersion {
    id<HanlinNativeServicesProvider> provider = [self currentProvider] ?: [self legacyProvider];
    return [provider pythonVersion];
}

+ (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [bridge fetchURL:urlString completion:completion];
}

+ (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion {
    HanlinNativeServicesSessionBridge *bridge = [self activeSessionBridge];
    if (!bridge) { if (completion) completion(nil, @"Host service provider not registered."); return; }
    [bridge sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON completion:completion];
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
    if ([provider respondsToSelector:@selector(registerRequestHandler:capability:handler:)]) {
        [provider registerRequestHandler:action capability:capability handler:^(NSString *caller, NSString *payloadJSON, HanlinBridgeStringResultBlock reply) {
            NSLog(@"[HanlinNativeServicesBridge] Action handler invoked for action=%@ caller=%@ payload=%@", action, caller, payloadJSON);
            NSDictionary *reqDict = nil;
            if (payloadJSON.length > 0) {
                NSData *data = [payloadJSON dataUsingEncoding:NSUTF8StringEncoding];
                if (data) {
                    reqDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                }
            }
            NSDictionary *replyDict = @{
                @"source": @"hanlin.demo.script-parity",
                @"action": action ?: @"",
                @"caller": caller ?: @"",
                @"request": reqDict ?: @{},
                @"status": @"ok"
            };
            NSData *replyData = [NSJSONSerialization dataWithJSONObject:replyDict options:0 error:nil];
            NSString *replyStr = replyData ? [[NSString alloc] initWithData:replyData encoding:NSUTF8StringEncoding] : @"{}";
            if (reply) reply(replyStr, nil);
        }];
    }
}

+ (NSString *)roundTripValue:(NSString *)value key:(NSString *)key {
    if ([key isEqualToString:@"hostService.dataRoot"]) {
        return [self dataRootDirectory] ?: @"";
    }
    if ([key isEqualToString:@"hostService.state"]) {
        return [self stateDirectory] ?: @"";
    }
    if ([key isEqualToString:@"hostService.executeJavaScript"]) {
        return [self executeJavaScriptSync:value] ?: @"";
    }
    if ([key isEqualToString:@"hostService.executeNode"]) {
        return [self executeNodeSync:value] ?: @"";
    }
    if ([key isEqualToString:@"hostService.executePython"]) {
        return [self executePythonSync:value] ?: @"";
    }
    if ([key isEqualToString:@"hostService.fetchURL"]) {
        return [self fetchURLSync:value] ?: @"";
    }
    if ([key hasPrefix:@"hostService.sendRequest:"]) {
        NSArray *parts = [key componentsSeparatedByString:@":"];
        NSString *targetID = parts.count > 1 ? parts[1] : @"";
        NSString *action = parts.count > 2 ? parts[2] : @"";
        NSString *capability = parts.count > 3 ? parts[3] : @"";
        return [self sendRequestSync:targetID
                              action:action
                          capability:capability
                         payloadJSON:value] ?: @"";
    }
    if ([key isEqualToString:@"hostService.sendRequest"]) {
        if (value.length > 0) {
            NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]]) {
                NSString *targetID = dict[@"targetID"] ?: @"";
                NSString *action = dict[@"action"] ?: @"";
                NSString *capability = dict[@"capability"] ?: @"";
                id payload = dict[@"payload"] ?: dict[@"payloadJSON"] ?: @"";
                NSString *payloadJSON = [payload isKindOfClass:[NSString class]] ? payload : @"";
                if (![payload isKindOfClass:[NSString class]]) {
                    NSData *pData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
                    if (pData) payloadJSON = [[NSString alloc] initWithData:pData encoding:NSUTF8StringEncoding];
                }
                return [self sendRequestSync:targetID
                                      action:action
                                  capability:capability
                                 payloadJSON:payloadJSON] ?: @"";
            }
        }
    }
    if ([key hasPrefix:@"hostService.registerAction:"]) {
        NSString *capability = [key substringFromIndex:@"hostService.registerAction:".length];
        [self registerAction:value capability:capability];
        return @"registered";
    }
    NSString *scopedKey = [@"hanlin.nativescript.compatibility." stringByAppendingString:key];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:value forKey:scopedKey];
    return [defaults stringForKey:scopedKey] ?: @"";
}

static HanlinNativeServicesBridge *_sharedBridgeInstance = nil;

+ (instancetype)sharedBridge {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedBridgeInstance = [[HanlinNativeServicesBridge alloc] init];
    });
    return _sharedBridgeInstance;
}

- (nullable NSString *)dataRootDirectory { return [self.class dataRootDirectory]; }
- (nullable NSString *)stateDirectory { return [self.class stateDirectory]; }
- (nullable NSString *)documentsDirectory { return [self.class documentsDirectory]; }
- (nullable NSString *)cacheDirectory { return [self.class cacheDirectory]; }

- (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    [self.class executeJavaScript:source completion:completion];
}

- (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    [self.class executeNode:source completion:completion];
}

- (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    [self.class nodeHealthCheckWithCompletion:completion];
}

- (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    [self.class executePython:source completion:completion];
}

- (nullable NSString *)pythonVersion { return [self.class pythonVersion]; }

- (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion {
    [self.class fetchURL:urlString completion:completion];
}

- (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion {
    [self.class sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON completion:completion];
}

- (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler {
    [self.class registerRequestHandler:action capability:capability handler:handler];
}

- (nullable NSString *)executeJavaScriptSync:(NSString *)source {
    return [self.class executeJavaScriptSync:source];
}

- (nullable NSString *)executeNodeSync:(NSString *)source {
    return [self.class executeNodeSync:source];
}

- (nullable NSString *)executePythonSync:(NSString *)source {
    return [self.class executePythonSync:source];
}

- (nullable NSString *)fetchURLSync:(NSString *)urlString {
    return [self.class fetchURLSync:urlString];
}

- (nullable NSString *)sendRequestSync:(NSString *)targetID
                                action:(NSString *)action
                            capability:(NSString *)capability
                           payloadJSON:(NSString *)payloadJSON {
    return [self.class sendRequestSync:targetID action:action capability:capability payloadJSON:payloadJSON];
}

- (void)registerAction:(NSString *)action capability:(NSString *)capability {
    [self.class registerAction:action capability:capability];
}

- (NSString *)roundTripValue:(NSString *)value key:(NSString *)key {
    return [self.class roundTripValue:value key:key];
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
