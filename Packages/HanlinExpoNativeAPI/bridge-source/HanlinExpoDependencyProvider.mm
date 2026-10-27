#import "HanlinExpoDependencyProvider.h"
#import "HanlinExpoNativeAPIGate.h"

#if __has_include("NativeScriptNativeApiModuleProvider.h")
#import "NativeScriptNativeApiModuleProvider.h"
#endif

#if __has_include("WorkletsModule.h")
#import "WorkletsModule.h"
#elif __has_include(<worklets/apple/WorkletsModule.h>)
#import <worklets/apple/WorkletsModule.h>
#endif

#import <React/RCTComponentViewProtocol.h>

extern "C" Class<RCTComponentViewProtocol> _Nullable NativeScriptUIViewCls(void);

@implementation HanlinExpoDependencyProvider

+ (instancetype)sharedProvider {
  static HanlinExpoDependencyProvider *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[HanlinExpoDependencyProvider alloc] init];
  });
  return sharedInstance;
}

- (NSArray<NSString *> *)imageURLLoaderClassNames {
  return @[];
}

- (NSArray<NSString *> *)imageDataDecoderClassNames {
  return @[];
}

- (NSArray<NSString *> *)URLRequestHandlerClassNames {
  return @[];
}

- (NSArray<NSString *> *)unstableModulesRequiringMainQueueSetup {
  return @[@"WorkletsModule"];
}

- (NSDictionary<NSString *, Class<RCTComponentViewProtocol>> *)thirdPartyFabricComponents {
  NSMutableDictionary<NSString *, Class<RCTComponentViewProtocol>> *dict = [NSMutableDictionary dictionary];
  Class cls = NSClassFromString(@"NativeScriptUIViewComponentView");
  if (cls == Nil && &NativeScriptUIViewCls != NULL) {
    cls = NativeScriptUIViewCls();
  }
  if (cls != Nil) {
    dict[@"NativeScriptUIView"] = cls;
  } else {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI] WARNING: NativeScriptUIViewComponentView not resolved");
  }
  return dict;
}

- (nonnull NSDictionary<NSString *, id<RCTModuleProvider>> *)moduleProviders {
  NSMutableDictionary<NSString *, id<RCTModuleProvider>> *dict = [NSMutableDictionary dictionary];
  
  // 1. NativeScript RN TurboModule provider
  Class nsProviderClass = NSClassFromString(@"NativeScriptNativeApiModuleProvider");
  if (nsProviderClass != Nil) {
    id provider = [[[nsProviderClass alloc] init] autorelease];
    if (provider != nil) {
      dict[@"NativeScriptNativeApi"] = provider;
    }
  }
  
  // 2. React Native Worklets TurboModule provider
  Class workletsClass = NSClassFromString(@"WorkletsModule");
  if (workletsClass != Nil) {
    id workletsProvider = [[[workletsClass alloc] init] autorelease];
    if (workletsProvider != nil) {
      dict[@"WorkletsModule"] = workletsProvider;
    }
  }

  NSAssert(dict[@"NativeScriptNativeApi"] != nil, @"[HANLIN_EXPO_NATIVEAPI] NativeScriptNativeApi provider must be non-nil");
  NSAssert(dict[@"WorkletsModule"] != nil, @"[HANLIN_EXPO_NATIVEAPI] WorkletsModule provider must be non-nil");

  return dict;
}

@end
