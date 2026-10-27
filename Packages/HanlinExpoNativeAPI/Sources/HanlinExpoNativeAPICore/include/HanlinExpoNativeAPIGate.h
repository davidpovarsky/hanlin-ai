#pragma once

#import <Foundation/Foundation.h>

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

+ (void)registerActiveSessionContext:(HanlinExpoNativeAPISessionContext *)context;
+ (void)bindRuntime:(nullable void *)runtimePointer forSessionID:(NSString *)sessionID;
+ (void)revokeSession:(NSString *)sessionID;
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

NS_ASSUME_NONNULL_END
