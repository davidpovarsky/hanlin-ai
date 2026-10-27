#import "HanlinExpoNativeAPIGate.h"
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
static HanlinExpoNativeAPISessionContext *sActiveContext = nil;
static NSString *sBundledMetadataPathOverride = nil;
static std::unordered_map<void*, std::string> sRuntimeToSessionMap;

// Forward declaration from NativeScriptNativeApiModule.mm
extern "C" void HanlinExpoNativeAPIClearWorkletRuntime(void) __attribute__((weak));

@implementation HanlinExpoNativeAPIGate

+ (void)registerActiveSessionContext:(HanlinExpoNativeAPISessionContext *)context {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext != context) {
    [sActiveContext release];
    sActiveContext = [context retain];
  }
  NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Registered session context session=%@ package=%@ gen=%llu granted=%d",
        context.sessionID, context.packageID, (unsigned long long)context.generation, context.isNativeAPIGranted);
}

+ (void)bindRuntime:(nullable void *)runtimePointer forSessionID:(NSString *)sessionID {
  if (runtimePointer == nullptr || sessionID == nil) {
    return;
  }
  std::lock_guard<std::mutex> lock(sGateMutex);
  sRuntimeToSessionMap[runtimePointer] = [sessionID UTF8String];
  NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Bound runtime %p to session %@", runtimePointer, sessionID);
}

+ (void)revokeSession:(NSString *)sessionID {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext != nil && [sActiveContext.sessionID isEqualToString:sessionID]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Revoked active session context session=%@ package=%@",
          sActiveContext.sessionID, sActiveContext.packageID);
    [sActiveContext release];
    sActiveContext = nil;
  }
  std::string targetSession = [sessionID UTF8String];
  for (auto it = sRuntimeToSessionMap.begin(); it != sRuntimeToSessionMap.end(); ) {
    if (it->second == targetSession) {
      it = sRuntimeToSessionMap.erase(it);
    } else {
      ++it;
    }
  }
  if (&HanlinExpoNativeAPIClearWorkletRuntime != NULL) {
    HanlinExpoNativeAPIClearWorkletRuntime();
  }
}

+ (void)revokeActiveSession {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext != nil) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Revoked active session synchronously session=%@ package=%@",
          sActiveContext.sessionID, sActiveContext.packageID);
    [sActiveContext release];
    sActiveContext = nil;
  }
  sRuntimeToSessionMap.clear();
  if (&HanlinExpoNativeAPIClearWorkletRuntime != NULL) {
    HanlinExpoNativeAPIClearWorkletRuntime();
  }
}

+ (void)invalidateAllSessions {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext != nil) {
    [sActiveContext release];
    sActiveContext = nil;
  }
  sRuntimeToSessionMap.clear();
  if (&HanlinExpoNativeAPIClearWorkletRuntime != NULL) {
    HanlinExpoNativeAPIClearWorkletRuntime();
  }
}

+ (nullable HanlinExpoNativeAPISessionContext *)activeSessionContext {
  std::lock_guard<std::mutex> lock(sGateMutex);
  return [[sActiveContext retain] autorelease];
}

+ (BOOL)isNativeAPIAuthorizedForCurrentSession {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext == nil) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE_DENIAL] No active session context registered.");
    return NO;
  }
  if (!sActiveContext.isNativeAPIGranted) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE_DENIAL] Active session %@ for package %@ is NOT granted 'ios-native-api'.",
          sActiveContext.sessionID, sActiveContext.packageID);
    return NO;
  }
  return YES;
}

+ (BOOL)isNativeAPIAuthorizedForRuntime:(nullable void *)runtimePointer {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext == nil || !sActiveContext.isNativeAPIGranted) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE_DENIAL] No active granted session context.");
    return NO;
  }
  if (runtimePointer != nullptr) {
    auto it = sRuntimeToSessionMap.find(runtimePointer);
    if (it != sRuntimeToSessionMap.end()) {
      if (it->second != [sActiveContext.sessionID UTF8String]) {
        NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE_DENIAL] Runtime %p bound to stale session %s, active is %@",
              runtimePointer, it->second.c_str(), sActiveContext.sessionID);
        return NO;
      }
    } else {
      sRuntimeToSessionMap[runtimePointer] = [sActiveContext.sessionID UTF8String];
    }
  }
  return YES;
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
  std::lock_guard<std::mutex> lock(sGateMutex);
  [sActiveContext release];
  sActiveContext = nil;
  [sBundledMetadataPathOverride release];
  sBundledMetadataPathOverride = nil;
  sRuntimeToSessionMap.clear();
  if (&HanlinExpoNativeAPIClearWorkletRuntime != NULL) {
    HanlinExpoNativeAPIClearWorkletRuntime();
  }
}

@end
