#import <Foundation/Foundation.h>
#import "HanlinNativeServicesBridge.h"

NS_ASSUME_NONNULL_BEGIN

/// Narrow Hanlin-specific semantics exposed to trusted NativeScript packages.
/// Ordinary Apple API access remains NativeScript's responsibility.
@interface HanlinNativeScriptCompatibility : NSObject
+ (NSString *)roundTripValue:(NSString *)value key:(NSString *)key;
+ (nullable id)createSwiftUIFixtureProvider;
+ (void)updateSwiftUIProvider:(id)provider data:(nullable NSDictionary *)data;
+ (void)registerSwiftUIProvider:(id)provider eventHandler:(void (^)(NSDictionary *))handler;
+ (void)registerFixtureProviderClass:(Class)cls;
+ (void)setSharedSwiftUIFixtureProvider:(id)provider;
+ (nullable id)sharedSwiftUIFixtureProvider;
+ (void)sendEventToRegisteredHandler:(NSDictionary *)eventData;
+ (void)recordEvent:(NSDictionary *)payload;
+ (nullable NSNumber *)latestEventCount;
+ (nullable NSDictionary *)latestEvent;
+ (nullable NSString *)currentDataRootDirectory;
+ (nullable NSString *)currentStateDirectory;
+ (nullable NSString *)hostServicePathForType:(NSString *)pathType;
+ (nullable NSString *)executeJavaScriptSync:(NSString *)source;
+ (nullable NSString *)executeNodeSync:(NSString *)source;
+ (nullable NSString *)executePythonSync:(NSString *)source;
+ (nullable NSString *)fetchURLSync:(NSString *)urlString;
+ (nullable NSString *)sendRequestSync:(NSString *)targetID
                                action:(NSString *)action
                            capability:(NSString *)capability
                           payloadJSON:(NSString *)payloadJSON;
+ (void)registerAction:(NSString *)action capability:(NSString *)capability;

+ (instancetype)sharedCompatibility;

- (NSString *)roundTripValue:(NSString *)value key:(NSString *)key;
- (nullable NSString *)currentDataRootDirectory;
- (nullable NSString *)currentStateDirectory;
- (nullable NSString *)dataRootDirectory;
- (nullable NSString *)stateDirectory;
- (nullable NSString *)executeJavaScriptSync:(NSString *)source;
- (nullable NSString *)executeNodeSync:(NSString *)source;
- (nullable NSString *)executePythonSync:(NSString *)source;
- (nullable NSString *)fetchURLSync:(NSString *)urlString;
- (nullable NSString *)sendRequestSync:(NSString *)targetID
                                action:(NSString *)action
                            capability:(NSString *)capability
                           payloadJSON:(NSString *)payloadJSON;
- (void)registerAction:(NSString *)action capability:(NSString *)capability;
@end

NS_ASSUME_NONNULL_END
