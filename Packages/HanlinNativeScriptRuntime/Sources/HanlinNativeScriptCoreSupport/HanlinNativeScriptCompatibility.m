#import "HanlinNativeScriptCompatibility.h"
#import <UIKit/UIKit.h>

static Class _registeredProviderClass = nil;
static id _sharedProvider = nil;

@implementation HanlinNativeScriptCompatibility

+ (NSString *)roundTripValue:(NSString *)value key:(NSString *)key {
    NSString *scopedKey = [@"hanlin.nativescript.compatibility." stringByAppendingString:key];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:value forKey:scopedKey];
    return [defaults stringForKey:scopedKey] ?: @"";
}

+ (void)registerFixtureProviderClass:(Class)cls {
    _registeredProviderClass = cls;
}

+ (void)setSharedSwiftUIFixtureProvider:(id)provider {
    _sharedProvider = provider;
}

+ (nullable id)sharedSwiftUIFixtureProvider {
    return _sharedProvider;
}

+ (nullable id)createSwiftUIFixtureProvider {
    Class klass = _registeredProviderClass;
    if (!klass) {
        klass = NSClassFromString(@"HanlinNativeScriptSwiftUIFixtureProvider");
    }
    if (!klass) {
        klass = NSClassFromString(@"HanlinNativeScriptRuntime.HanlinNativeScriptSwiftUIFixtureProvider");
    }
    if (!klass && _sharedProvider) {
        NSLog(@"[HanlinNativeScriptCompatibility] Using shared provider=%@", _sharedProvider);
        return _sharedProvider;
    }
    if (!klass) {
        NSLog(@"[HanlinNativeScriptCompatibility] Fatal: HanlinNativeScriptSwiftUIFixtureProvider class not found in Objective-C runtime.");
        return nil;
    }

    __block id provider = nil;
    void (^instantiateBlock)(void) = ^{
        provider = [[klass alloc] init];
        if (provider) {
            if ([provider isKindOfClass:[UIViewController class]]) {
                UIView *v = [(UIViewController *)provider view];
                (void)v;
            }
        }
    };

    if ([NSThread isMainThread]) {
        instantiateBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), instantiateBlock);
    }
    int viewLoaded = [provider respondsToSelector:@selector(isViewLoaded)] ? (int)[(UIViewController *)provider isViewLoaded] : 0;
    NSLog(@"[HanlinNativeScriptCompatibility] Created provider=%@ isViewLoaded=%d", provider, viewLoaded);
    return provider;
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
