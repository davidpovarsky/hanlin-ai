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
        if (!_currentProvider || [_currentProvider isKindOfClass:NSClassFromString(@"HanlinNativeServicesHostProvider")]) {
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

+ (void)resetAllSessions {
    [_sessionLock lock];
    [_sessionProviders removeAllObjects];
    for (NSString *key in [_boundBridges allKeys]) {
        for (HanlinNativeServicesSessionBridge *bridge in _boundBridges[key]) {
            [bridge invalidate];
        }
    }
    [_boundBridges removeAllObjects];
    for (NSString *token in [_bootstrapBridges allKeys]) {
        [_bootstrapBridges[token] invalidate];
    }
    [_bootstrapBridges removeAllObjects];
    if (_activeSessionBridge) {
        [_activeSessionBridge invalidate];
        _activeSessionBridge = nil;
    }
    _currentProvider = nil;
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
    // Fail closed: Never cross-resolve arbitrary sessions from _sessionProviders.
    // Legacy single-session compatibility is supported ONLY when there is exactly 1 registered session or an explicit _currentProvider.
    // If multiple sessions exist and none is marked active, fail closed (return nil).
    if (!provider && _sessionProviders.count == 1) {
        provider = _sessionProviders.allValues.firstObject;
    } else if (!provider && _sessionProviders.count == 0) {
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
