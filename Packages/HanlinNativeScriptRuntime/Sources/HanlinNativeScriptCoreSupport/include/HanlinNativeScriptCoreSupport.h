#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "HanlinNativeScriptCompatibility.h"
#import "HanlinNativeServicesBridge.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const HanlinNativeScriptRuntimeErrorDomain;

typedef NS_ERROR_ENUM(HanlinNativeScriptRuntimeErrorDomain, HanlinNativeScriptRuntimeErrorCode) {
    HanlinNativeScriptRuntimeErrorInvalidConfiguration = 1,
    HanlinNativeScriptRuntimeErrorInitializationFailed = 2,
    HanlinNativeScriptRuntimeErrorExecutionFailed = 3,
};

@interface HanlinNativeScriptRuntimeHost : NSObject

- (nullable instancetype)initWithBaseDirectory:(NSString *)baseDirectory
                                applicationPath:(NSString *)applicationPath
                                          error:(NSError * _Nullable * _Nullable)error
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)runMainApplicationWithError:(NSError * _Nullable * _Nullable)error;

/// Installs a provider-bound Host Services bridge into this runtime before
/// application JavaScript starts. The session identifier is never exposed to
/// the application and cannot be supplied on individual calls.
- (BOOL)bindHostServicesSessionID:(NSString *)sessionID
                            error:(NSError * _Nullable * _Nullable)error;

- (void)shutdown;

@end

@interface HanlinNativeScriptContainerController : UIViewController
@end

@interface HanlinNativeScriptPresenter : NSObject

@property(nonatomic, readonly) HanlinNativeScriptContainerController *containerController;
@property(nonatomic, readonly, nullable) UIViewController *guestController;

- (void)install;
- (void)detach;

@end

NS_ASSUME_NONNULL_END
