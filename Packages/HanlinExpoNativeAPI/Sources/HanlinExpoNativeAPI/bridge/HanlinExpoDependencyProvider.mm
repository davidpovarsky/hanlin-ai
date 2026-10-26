#import "HanlinExpoDependencyProvider.h"
#import "HanlinExpoNativeAPIGate.h"

#if __has_include("NativeScriptNativeApiModuleProvider.h")
#import "NativeScriptNativeApiModuleProvider.h"
#endif

#if __has_include("NativeScriptUIViewComponentView.h")
#import "NativeScriptUIViewComponentView.h"
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
  }
  return dict;
}

- (nonnull NSDictionary<NSString *, id<RCTModuleProvider>> *)moduleProviders {
  NSMutableDictionary<NSString *, id<RCTModuleProvider>> *dict = [NSMutableDictionary dictionary];
  Class providerClass = NSClassFromString(@"NativeScriptNativeApiModuleProvider");
  if (providerClass != Nil) {
    id provider = [[providerClass alloc] init];
    if (provider != nil) {
      dict[@"NativeScriptNativeApi"] = provider;
    }
  }
  return dict;
}

@end
