#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Narrow Hanlin-specific semantics exposed to trusted NativeScript packages.
/// Ordinary Apple API access remains NativeScript's responsibility.
@interface HanlinNativeScriptCompatibility : NSObject
+ (NSString *)roundTripValue:(NSString *)value key:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
