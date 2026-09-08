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

+ (void)updateSwiftUIProvider:(id)provider data:(nullable NSDictionary *)data {
    if (!provider) return;
    SEL updateSelector = NSSelectorFromString(@"updateDataWithData:");
    if ([provider respondsToSelector:updateSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [provider performSelector:updateSelector withObject:data];
#pragma clang diagnostic pop
        return;
    }
    SEL fallbackSelector = NSSelectorFromString(@"updateData:");
    if ([provider respondsToSelector:fallbackSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [provider performSelector:fallbackSelector withObject:data];
#pragma clang diagnostic pop
    }
}

+ (void)registerSwiftUIProvider:(id)provider eventHandler:(void (^)(NSDictionary *))handler {
    if (!provider) return;
    SEL registerSelector = NSSelectorFromString(@"registerEventHandler:");
    if ([provider respondsToSelector:registerSelector]) {
        void (*func)(id, SEL, id) = (void (*)(id, SEL, id))[provider methodForSelector:registerSelector];
        if (func) {
            func(provider, registerSelector, handler);
        }
    }
}

@end
