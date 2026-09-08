#import <Foundation/Foundation.h>

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
@end

NS_ASSUME_NONNULL_END
