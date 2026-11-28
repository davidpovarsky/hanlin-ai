#pragma once

#import <Foundation/Foundation.h>

@class UIView;

NS_ASSUME_NONNULL_BEGIN

@interface HanlinExpoNativeAPISessionContext : NSObject
@property (nonatomic, readonly, copy) NSString *sessionID;
@property (nonatomic, readonly, copy) NSString *packageID;
@property (nonatomic, readonly) BOOL isNativeAPIGranted;
@property (nonatomic, readonly) uint64_t generation;
- (instancetype)initWithSessionID:(NSString *)sessionID
                        packageID:(NSString *)packageID
               isNativeAPIGranted:(BOOL)isNativeAPIGranted
                       generation:(uint64_t)generation;
@end

@interface HanlinExpoNativeAPIGate : NSObject
// Each live React runtime belongs to its own session. Registration never replaces
// another session and unbound runtimes are never attributed to the latest window.
+ (void)registerActiveSessionContext:(HanlinExpoNativeAPISessionContext *)context;
+ (void)bindRuntime:(nullable void *)runtimePointer forSessionID:(NSString *)sessionID;
+ (nullable HanlinExpoNativeAPISessionContext *)sessionContextForRuntime:(nullable void *)runtimePointer;
+ (nullable HanlinExpoNativeAPISessionContext *)sessionContextForSessionID:(NSString *)sessionID;
// Bind the concrete React root before it enters the view hierarchy. UIKit host IDs
// are only unique inside their own JS VM, so view ownership supplies the namespace.
+ (void)bindView:(UIView *)view forSessionID:(NSString *)sessionID NS_SWIFT_NAME(bindView(_:forSessionID:));
+ (nullable HanlinExpoNativeAPISessionContext *)sessionContextForView:(UIView *)view;
+ (void)revokeSession:(NSString *)sessionID;
// Compatibility entry points operate only when there is one unambiguous session.
+ (void)revokeActiveSession;
+ (void)invalidateAllSessions;
+ (nullable HanlinExpoNativeAPISessionContext *)activeSessionContext;
+ (BOOL)isNativeAPIAuthorizedForCurrentSession;
+ (BOOL)isNativeAPIAuthorizedForRuntime:(nullable void *)runtimePointer;
+ (nullable NSString *)bundledMetadataPath;
+ (void)setBundledMetadataPathOverride:(nullable NSString *)path;
+ (void)reset;
@end

FOUNDATION_EXPORT void HanlinExpoNativeAPIClearWorkletRuntime(void);
FOUNDATION_EXPORT void HanlinExpoNativeAPIClearWorkletRuntimeForSession(NSString *sessionID);

NS_ASSUME_NONNULL_END
