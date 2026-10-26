#pragma once

#import <Foundation/Foundation.h>
#import <React_RCTAppDelegate/RCTDependencyProvider.h>

NS_ASSUME_NONNULL_BEGIN

@interface HanlinExpoDependencyProvider : NSObject <RCTDependencyProvider>

+ (instancetype)sharedProvider;

@end

NS_ASSUME_NONNULL_END
