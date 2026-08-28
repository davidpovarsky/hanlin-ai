#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

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
