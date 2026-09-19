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

@interface HanlinNativeServicesBridge : NSObject

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

NS_ASSUME_NONNULL_END
