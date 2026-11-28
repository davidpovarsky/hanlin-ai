#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Call only from React's didInitializeRuntime callback on the JavaScript thread.
/// Installs Expo's upstream weak React scheduler handle instead of an inline scheduler.
FOUNDATION_EXPORT BOOL HanlinExpoInstallScheduledRuntime(void *runtimePointer, id appContext);

NS_ASSUME_NONNULL_END
