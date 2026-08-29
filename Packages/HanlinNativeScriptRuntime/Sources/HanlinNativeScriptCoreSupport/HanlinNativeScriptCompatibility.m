#import "HanlinNativeScriptCompatibility.h"

@implementation HanlinNativeScriptCompatibility

+ (NSString *)roundTripValue:(NSString *)value key:(NSString *)key {
    NSString *scopedKey = [@"hanlin.nativescript.compatibility." stringByAppendingString:key];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:value forKey:scopedKey];
    return [defaults stringForKey:scopedKey] ?: @"";
}

@end
