#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "HanlinNativeServicesBridge.h"

NS_ASSUME_NONNULL_BEGIN
@class HanlinNativeScriptWindowContext;
typedef void (^HanlinNativeScriptWindowFactoryBlock)(HanlinNativeScriptWindowContext *context);
typedef void (^HanlinNativeScriptWindowLifecycleBlock)(NSString *event, UIWindow * _Nullable window);

/// One Host-owned surface and provider. Never resolves services using focus.
@interface HanlinNativeScriptWindowContext : NSObject
@property(nonatomic, readonly, copy) NSString *windowID;
@property(nonatomic, readonly, strong) HanlinNativeServicesSessionBridge *servicesBridge;
@property(nonatomic, readonly, strong) UIViewController *containerController;
@property(nonatomic, readonly, getter=isClosed) BOOL closed;
- (void)presentViewController:(UIViewController *)controller;
- (void)setLifecycleHandler:(HanlinNativeScriptWindowLifecycleBlock)handler;
- (void)showFailure:(NSString *)message;
@end

/// The one main runtime registers a cooperating factory; windows retain distinct contexts.
@interface HanlinNativeScriptWindowFactoryRegistry : NSObject
+ (BOOL)beginRuntimeSessionID:(NSString *)sessionID NS_SWIFT_NAME(beginRuntime(sessionID:));
+ (BOOL)registerFactory:(HanlinNativeScriptWindowFactoryBlock)factory;
+ (BOOL)hasFactoryForRuntimeSessionID:(NSString *)sessionID NS_SWIFT_NAME(hasFactory(sessionID:));
+ (nullable HanlinNativeScriptWindowContext *)openWindowWithID:(NSString *)windowID
                                                     bridge:(HanlinNativeServicesSessionBridge *)bridge
    NS_SWIFT_NAME(openWindow(id:bridge:));
+ (void)closeWindowWithID:(NSString *)windowID NS_SWIFT_NAME(closeWindow(id:));
+ (void)endRuntimeSessionID:(NSString *)sessionID NS_SWIFT_NAME(endRuntime(sessionID:));
+ (nullable NSString *)lastFailure;
+ (NSUInteger)openWindowCount;
@end
NS_ASSUME_NONNULL_END
