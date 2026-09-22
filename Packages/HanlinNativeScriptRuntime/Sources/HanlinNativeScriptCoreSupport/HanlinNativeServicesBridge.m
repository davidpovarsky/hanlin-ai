#import "HanlinNativeServicesBridge.h"

static id<HanlinNativeServicesProvider> _currentProvider = nil;
static NSMutableDictionary<NSString *, id<HanlinNativeServicesProvider>> *_sessionProviders = nil;
static NSLock *_sessionLock = nil;

@implementation HanlinNativeServicesBridge

+ (void)initialize {
    if (self == [HanlinNativeServicesBridge class]) {
        _sessionProviders = [[NSMutableDictionary alloc] init];
        _sessionLock = [[NSLock alloc] init];
    }
}

+ (void)registerProvider:(nullable id<HanlinNativeServicesProvider>)provider forSessionID:(NSString *)sessionID {
    if (!sessionID) return;
    [_sessionLock lock];
    if (provider) {
        _sessionProviders[sessionID] = provider;
        _currentProvider = provider;
    } else {
        [_sessionProviders removeObjectForKey:sessionID];
    }
    [_sessionLock unlock];
}

+ (void)unregisterProviderForSessionID:(NSString *)sessionID {
    if (!sessionID) return;
    [_sessionLock lock];
    [_sessionProviders removeObjectForKey:sessionID];
    [_sessionLock unlock];
}

+ (nullable id<HanlinNativeServicesProvider>)providerForSessionID:(NSString *)sessionID {
    if (!sessionID) return _currentProvider;
    [_sessionLock lock];
    id<HanlinNativeServicesProvider> provider = _sessionProviders[sessionID] ?: _currentProvider;
    [_sessionLock unlock];
    return provider;
}

+ (void)registerProvider:(nullable id<HanlinNativeServicesProvider>)provider {
    _currentProvider = provider;
}

+ (nullable id<HanlinNativeServicesProvider>)currentProvider {
    return _currentProvider;
}

+ (nullable NSString *)dataRootDirectory {
    return [_currentProvider dataRootDirectory];
}

+ (nullable NSString *)stateDirectory {
    return [_currentProvider stateDirectory];
}

+ (nullable NSString *)documentsDirectory {
    return [_currentProvider documentsDirectory];
}

+ (nullable NSString *)cacheDirectory {
    return [_currentProvider cacheDirectory];
}

+ (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        if (completion) {
            completion(nil, @"Host service provider not registered.");
        }
        return;
    }
    [provider executeJavaScript:source completion:completion];
}

+ (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        if (completion) {
            completion(nil, @"Host service provider not registered.");
        }
        return;
    }
    [provider executeNode:source completion:completion];
}

+ (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        if (completion) {
            completion(NO, @"Host service provider not registered.");
        }
        return;
    }
    [provider nodeHealthCheckWithCompletion:completion];
}

+ (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        if (completion) {
            completion(nil, @"Host service provider not registered.");
        }
        return;
    }
    [provider executePython:source completion:completion];
}

+ (nullable NSString *)pythonVersion {
    return [_currentProvider pythonVersion];
}

+ (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        if (completion) {
            completion(nil, @"Host service provider not registered.");
        }
        return;
    }
    [provider fetchURL:urlString completion:completion];
}

+ (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        if (completion) {
            completion(nil, @"Host service provider not registered.");
        }
        return;
    }
    [provider sendRequest:targetID action:action capability:capability payloadJSON:payloadJSON completion:completion];
}

+ (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler {
    id<HanlinNativeServicesProvider> provider = _currentProvider;
    if (!provider) {
        NSLog(@"[HanlinNativeServicesBridge] Cannot register request handler: provider not registered.");
        return;
    }
    [provider registerRequestHandler:action capability:capability handler:handler];
}

@end
