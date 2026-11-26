#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "HanlinNativeServicesBridge.h"

NS_ASSUME_NONNULL_BEGIN
@class HanlinNativeScriptWindowContext;
typedef void (^HanlinNativeScriptWindowFactoryBlock)(HanlinNativeScriptWindowContext *context);
typedef void (^HanlinNativeScriptPackageLoaderBlock)(NSString *configurationJSON);
typedef void (^HanlinNativeScriptWindowLifecycleBlock)(NSString *event, UIWindow * _Nullable window);

/// One Host-owned surface and provider. Never resolves services using focus.
@interface HanlinNativeScriptWindowContext : NSObject
@property(nonatomic, readonly, copy) NSString *windowID;
@property(nonatomic, readonly, copy) NSString *packageID;
@property(nonatomic, readonly, copy) NSString *applicationRoot;
@property(nonatomic, readonly, copy) NSString *environmentJSON;
@property(nonatomic, readonly, copy, nullable) NSString *styleSheetPath;
@property(nonatomic, readonly, strong) HanlinNativeServicesSessionBridge *servicesBridge;
@property(nonatomic, readonly, strong) UIViewController *containerController;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;
- (nullable NSString *)resourcePath:(NSString *)relativePath;
- (void)presentViewController:(UIViewController *)controller;
- (void)setLifecycleHandler:(HanlinNativeScriptWindowLifecycleBlock)handler;
- (void)showFailure:(NSString *)message;
@end

/// The one main runtime registers a cooperating factory; windows retain distinct contexts.
@interface HanlinNativeScriptWindowFactoryRegistry : NSObject
+ (id<HanlinNativeServicesProvider>)neutralRuntimeProvider;
+ (BOOL)beginRuntimeSessionID:(NSString *)sessionID NS_SWIFT_NAME(beginRuntime(sessionID:));
+ (BOOL)registerFactory:(HanlinNativeScriptWindowFactoryBlock)factory;
/// Only the neutral Host entry registers this original ns:module loader.
+ (BOOL)registerPackageLoader:(HanlinNativeScriptPackageLoaderBlock)loader;
+ (BOOL)loadPackageForWindowID:(NSString *)windowID configurationJSON:(NSString *)configurationJSON
    NS_SWIFT_NAME(loadPackage(windowID:configurationJSON:));
+ (BOOL)hasFactoryForRuntimeSessionID:(NSString *)sessionID NS_SWIFT_NAME(hasFactory(sessionID:));
+ (nullable HanlinNativeScriptWindowContext *)openWindowWithID:(NSString *)windowID
                                                     bridge:(HanlinNativeServicesSessionBridge *)bridge
    NS_SWIFT_NAME(openWindow(id:bridge:));
+ (nullable HanlinNativeScriptWindowContext *)openWindowWithID:(NSString *)windowID
                                                     bridge:(HanlinNativeServicesSessionBridge *)bridge
                                                  packageID:(NSString *)packageID
                                            applicationRoot:(NSString *)applicationRoot
                                            environmentJSON:(NSString *)environmentJSON
                                             styleSheetPath:(nullable NSString *)styleSheetPath
    NS_SWIFT_NAME(openWindow(id:bridge:packageID:applicationRoot:environmentJSON:styleSheetPath:));
+ (void)closeWindowWithID:(NSString *)windowID NS_SWIFT_NAME(closeWindow(id:));
+ (void)endRuntimeSessionID:(NSString *)sessionID NS_SWIFT_NAME(endRuntime(sessionID:));
+ (nullable NSString *)lastFailure;
+ (NSUInteger)openWindowCount;
@end
NS_ASSUME_NONNULL_END
