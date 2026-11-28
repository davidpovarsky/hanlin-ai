#import "HanlinExpoNativeAPIGate.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mutex>
#import <unordered_map>
#import <string>

@implementation HanlinExpoNativeAPISessionContext

- (instancetype)initWithSessionID:(NSString *)sessionID
                        packageID:(NSString *)packageID
               isNativeAPIGranted:(BOOL)isNativeAPIGranted
                       generation:(uint64_t)generation {
  if (self = [super init]) {
    _sessionID = [sessionID copy];
    _packageID = [packageID copy];
    _isNativeAPIGranted = isNativeAPIGranted;
    _generation = generation;
  }
  return self;
}

- (void)dealloc {
  [_sessionID release];
  [_packageID release];
  [super dealloc];
}

@end

static std::mutex sGateMutex;
static NSMutableDictionary<NSString*, HanlinExpoNativeAPISessionContext*> *sContexts = nil;
static NSString *sBundledMetadataPathOverride = nil;
static std::unordered_map<void*, std::string> sRuntimeToSessionMap;
static char sViewSessionKey;

// The runtime module may be omitted by focused consumers of the gate.
extern "C" void HanlinExpoNativeAPIClearWorkletRuntime(void) __attribute__((weak));
extern "C" void HanlinExpoNativeAPIClearWorkletRuntimeForSession(NSString *) __attribute__((weak));

@implementation HanlinExpoNativeAPIGate

+ (void)registerActiveSessionContext:(HanlinExpoNativeAPISessionContext *)context {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sContexts == nil) sContexts = [[NSMutableDictionary alloc] init];
  sContexts[context.sessionID] = context;
  NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Registered session context session=%@ package=%@ gen=%llu granted=%d",
        context.sessionID, context.packageID, (unsigned long long)context.generation, context.isNativeAPIGranted);
}

+ (void)bindRuntime:(nullable void *)runtimePointer forSessionID:(NSString *)sessionID {
  if (runtimePointer == nullptr || sessionID == nil) return;
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sContexts[sessionID] == nil) return;
  sRuntimeToSessionMap[runtimePointer] = sessionID.UTF8String;
}

+ (nullable HanlinExpoNativeAPISessionContext *)sessionContextForRuntime:(nullable void *)runtimePointer {
  if (runtimePointer == nullptr) return nil;
  std::lock_guard<std::mutex> lock(sGateMutex);
  auto entry = sRuntimeToSessionMap.find(runtimePointer);
  if (entry == sRuntimeToSessionMap.end()) return nil;
  NSString *sessionID = [NSString stringWithUTF8String:entry->second.c_str()];
  return [[sContexts[sessionID] retain] autorelease];
}

+ (nullable HanlinExpoNativeAPISessionContext *)sessionContextForSessionID:(NSString *)sessionID {
  if (sessionID == nil) return nil;
  std::lock_guard<std::mutex> lock(sGateMutex);
  return [[sContexts[sessionID] retain] autorelease];
}

+ (void)bindView:(UIView *)view forSessionID:(NSString *)sessionID {
  objc_setAssociatedObject(view, &sViewSessionKey, sessionID, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

+ (nullable HanlinExpoNativeAPISessionContext *)sessionContextForView:(UIView *)view {
  for (UIView *ancestor = view; ancestor != nil; ancestor = ancestor.superview) {
    NSString *sessionID = objc_getAssociatedObject(ancestor, &sViewSessionKey);
    if (sessionID != nil) return [self sessionContextForSessionID:sessionID];
  }
  return nil;
}

+ (void)revokeSession:(NSString *)sessionID {
  if (sessionID == nil) return;
  {
    std::lock_guard<std::mutex> lock(sGateMutex);
    [sContexts removeObjectForKey:sessionID];
    std::string targetSession = sessionID.UTF8String;
    for (auto entry = sRuntimeToSessionMap.begin(); entry != sRuntimeToSessionMap.end();) {
      if (entry->second == targetSession) entry = sRuntimeToSessionMap.erase(entry);
      else ++entry;
    }
  }
  // Do not invoke a module while holding the gate mutex. Closing B cannot clear A.
  if (&HanlinExpoNativeAPIClearWorkletRuntimeForSession != NULL) {
    HanlinExpoNativeAPIClearWorkletRuntimeForSession(sessionID);
  }
}

+ (void)revokeActiveSession {
  HanlinExpoNativeAPISessionContext *context = [self activeSessionContext];
  if (context != nil) [self revokeSession:context.sessionID];
}

+ (void)invalidateAllSessions {
  {
    std::lock_guard<std::mutex> lock(sGateMutex);
    [sContexts removeAllObjects];
    sRuntimeToSessionMap.clear();
  }
  if (&HanlinExpoNativeAPIClearWorkletRuntime != NULL) {
    HanlinExpoNativeAPIClearWorkletRuntime();
  }
}

+ (nullable HanlinExpoNativeAPISessionContext *)activeSessionContext {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sContexts.count != 1) return nil;
  return [[[sContexts allValues].firstObject retain] autorelease];
}

+ (BOOL)isNativeAPIAuthorizedForCurrentSession {
  return [self activeSessionContext] != nil;
}

+ (BOOL)isNativeAPIAuthorizedForRuntime:(nullable void *)runtimePointer {
  return [self sessionContextForRuntime:runtimePointer] != nil;
}

+ (void)setBundledMetadataPathOverride:(nullable NSString *)path {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sBundledMetadataPathOverride != path) {
    [sBundledMetadataPathOverride release];
    sBundledMetadataPathOverride = [path copy];
  }
}

+ (nullable NSString *)bundledMetadataPath {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sBundledMetadataPathOverride.length > 0 &&
      [[NSFileManager defaultManager] fileExistsAtPath:sBundledMetadataPathOverride]) {
    return sBundledMetadataPathOverride;
  }

#if TARGET_OS_SIMULATOR
#if defined(__x86_64__)
  NSString *metadataName = @"metadata.ios-sim.x86_64";
#else
  NSString *metadataName = @"metadata.ios-sim.arm64";
#endif
#else
  NSString *metadataName = @"metadata.ios.arm64";
#endif

  // 1. Check main bundle
  NSString *path = [[NSBundle mainBundle] pathForResource:metadataName ofType:@"nsmd"];
  if (path != nil) {
    return path;
  }

  // 2. Check HanlinExpoNativeAPI bundle
  NSBundle *bundle = [NSBundle bundleForClass:[HanlinExpoNativeAPIGate class]];
  path = [bundle pathForResource:metadataName ofType:@"nsmd"];
  if (path != nil) {
    return path;
  }

  // 3. Check subpath in module bundle
  NSString *subBundlePath = [bundle pathForResource:@"HanlinExpoNativeAPI_HanlinExpoNativeAPI" ofType:@"bundle"];
  if (subBundlePath != nil) {
    NSBundle *subBundle = [NSBundle bundleWithPath:subBundlePath];
    path = [subBundle pathForResource:metadataName ofType:@"nsmd"];
    if (path != nil) {
      return path;
    }
  }

  return nil;
}

+ (void)reset {
  [self invalidateAllSessions];
  std::lock_guard<std::mutex> lock(sGateMutex);
  [sBundledMetadataPathOverride release];
  sBundledMetadataPathOverride = nil;
}

@end
