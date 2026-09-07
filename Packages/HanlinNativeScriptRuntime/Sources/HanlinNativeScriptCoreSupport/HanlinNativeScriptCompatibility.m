#import "HanlinNativeScriptCompatibility.h"

@implementation HanlinNativeScriptCompatibility

+ (NSString *)roundTripValue:(NSString *)value key:(NSString *)key {
    NSString *scopedKey = [@"hanlin.nativescript.compatibility." stringByAppendingString:key];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:value forKey:scopedKey];
    return [defaults stringForKey:scopedKey] ?: @"";
}

+ (nullable id)createSwiftUIFixtureProvider {
    Class klass = NSClassFromString(@"HanlinNativeScriptSwiftUIFixtureProvider");
    if (!klass) {
        NSLog(@"[HanlinNativeScriptCompatibility] Fatal: HanlinNativeScriptSwiftUIFixtureProvider class not found in Objective-C runtime.");
        return nil;
    }

    if ([NSThread isMainThread]) {
        return [[klass alloc] init];
    } else {
        __block id provider = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            provider = [[klass alloc] init];
        });
        return provider;
    }
}

@end
