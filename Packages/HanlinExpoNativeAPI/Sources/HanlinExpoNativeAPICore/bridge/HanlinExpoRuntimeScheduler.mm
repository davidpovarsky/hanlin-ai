#import "HanlinExpoRuntimeScheduler.h"
#include <react/renderer/runtimescheduler/RuntimeSchedulerBinding.h>
#include "EXReactSchedulerDispatch.h"

@protocol HanlinExpoScheduledAppContext
- (void)setRuntime:(void *)runtime scheduler:(void *)scheduler dispatch:(const void *)dispatch;
@end

BOOL HanlinExpoInstallScheduledRuntime(void *runtimePointer, id appContext) {
  if (runtimePointer == nullptr || appContext == nil ||
      ![appContext respondsToSelector:@selector(setRuntime:scheduler:dispatch:)]) {
    return NO;
  }

  auto &runtime = *static_cast<facebook::jsi::Runtime *>(runtimePointer);
  auto binding = facebook::react::RuntimeSchedulerBinding::getBinding(runtime);
  auto scheduler = binding ? binding->getRuntimeScheduler() : nullptr;
  void *handle = expo::createReactSchedulerHandle(scheduler);
  if (handle == nullptr) {
    // A React-hosted runtime cannot safely execute async JSI work inline.
    NSLog(@"HANLIN_EXPO_RUNTIME_SCHEDULER_UNAVAILABLE");
    return NO;
  }

  [(id<HanlinExpoScheduledAppContext>)appContext
      setRuntime:runtimePointer
      scheduler:handle
      dispatch:reinterpret_cast<const void *>(&expo::dispatchOnReactScheduler)];
  return YES;
}
