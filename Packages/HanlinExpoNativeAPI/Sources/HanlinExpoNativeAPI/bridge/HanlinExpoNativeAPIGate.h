#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HanlinExpoNativeAPISessionContext : NSObject

@property (nonatomic, readonly, copy) NSString *sessionID;
@property (nonatomic, readonly, copy) NSString *packageID;
@property (nonatomic, readonly) BOOL isNativeAPIGranted;

- (instancetype)initWithSessionID:(NSString *)sessionID
                        packageID:(NSString *)packageID
               isNativeAPIGranted:(BOOL)isNativeAPIGranted;

@end

@interface HanlinExpoNativeAPIGate : NSObject

+ (void)registerActiveSessionContext:(HanlinExpoNativeAPISessionContext *)context;
+ (void)revokeSession:(NSString *)sessionID;
+ (nullable HanlinExpoNativeAPISessionContext *)activeSessionContext;
+ (BOOL)isNativeAPIAuthorizedForCurrentSession;
+ (nullable NSString *)bundledMetadataPath;
+ (void)setBundledMetadataPathOverride:(nullable NSString *)path;
+ (void)reset;

@end

NS_ASSUME_NONNULL_END
