#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^HanlinBridgeStringResultBlock)(NSString * _Nullable result, NSString * _Nullable error);
typedef void (^HanlinBridgeBoolResultBlock)(BOOL success, NSString * _Nullable error);
typedef void (^HanlinBridgeRequestHandlerBlock)(NSString *caller, NSString *payloadJSON, HanlinBridgeStringResultBlock reply);

@protocol HanlinNativeServicesProvider <NSObject>

- (nullable NSString *)dataRootDirectory;
- (nullable NSString *)stateDirectory;
- (nullable NSString *)documentsDirectory;
- (nullable NSString *)cacheDirectory;

- (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
- (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
- (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion;
- (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
- (nullable NSString *)pythonVersion;
- (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion;

- (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion;

- (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler;

@end

/// A provider-bound bridge object installed into one NativeScript global
/// object before untrusted application JavaScript starts executing.
@interface HanlinNativeServicesSessionBridge : NSObject

- (nullable NSString *)dataRootDirectory;
- (nullable NSString *)stateDirectory;
- (nullable NSString *)documentsDirectory;
- (nullable NSString *)cacheDirectory;

- (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
- (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
- (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion;
- (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
- (nullable NSString *)pythonVersion;
- (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion;

- (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion;

- (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler;

@end

@interface HanlinNativeServicesBridge : NSObject

+ (void)registerProvider:(nullable id<HanlinNativeServicesProvider>)provider forSessionID:(NSString *)sessionID;
+ (void)unregisterProviderForSessionID:(NSString *)sessionID;
+ (nullable id<HanlinNativeServicesProvider>)providerForSessionID:(NSString *)sessionID;

/// Consumes a host-issued, one-time bootstrap token. Application JavaScript
/// never supplies a session identifier to a Host Services operation.
+ (nullable HanlinNativeServicesSessionBridge *)claimSessionBridgeWithToken:(NSString *)token;

/// Active session bridge binding for runtime hosts
+ (void)setActiveSessionBridge:(nullable HanlinNativeServicesSessionBridge *)bridge forSessionID:(NSString *)sessionID;
+ (void)clearActiveSessionBridgeForSessionID:(NSString *)sessionID;
+ (nullable HanlinNativeServicesSessionBridge *)activeSessionBridge;

// Legacy single-session fallback. Modern sessions use the bound bridge above.
+ (void)registerProvider:(nullable id<HanlinNativeServicesProvider>)provider;
+ (nullable id<HanlinNativeServicesProvider>)currentProvider;

// Class methods callable directly from JavaScript / Objective-C
+ (nullable NSString *)dataRootDirectory;
+ (nullable NSString *)stateDirectory;
+ (nullable NSString *)documentsDirectory;
+ (nullable NSString *)cacheDirectory;

+ (void)executeJavaScript:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
+ (void)executeNode:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
+ (void)nodeHealthCheckWithCompletion:(HanlinBridgeBoolResultBlock)completion;
+ (void)executePython:(NSString *)source completion:(HanlinBridgeStringResultBlock)completion;
+ (nullable NSString *)pythonVersion;
+ (void)fetchURL:(NSString *)urlString completion:(HanlinBridgeStringResultBlock)completion;

+ (void)sendRequest:(NSString *)targetID
             action:(NSString *)action
         capability:(NSString *)capability
        payloadJSON:(NSString *)payloadJSON
         completion:(HanlinBridgeStringResultBlock)completion;

+ (void)registerRequestHandler:(NSString *)action
                    capability:(NSString *)capability
                       handler:(HanlinBridgeRequestHandlerBlock)handler;

@end

/// Prepares a one-time bootstrap token for a registered session.
FOUNDATION_EXPORT NSString * _Nullable HanlinNativeServicesPrepareSessionBootstrap(NSString *sessionID);

NS_ASSUME_NONNULL_END
