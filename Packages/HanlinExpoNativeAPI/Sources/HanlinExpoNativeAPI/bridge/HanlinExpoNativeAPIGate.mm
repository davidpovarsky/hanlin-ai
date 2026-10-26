#import "HanlinExpoNativeAPIGate.h"
#import <mutex>

@implementation HanlinExpoNativeAPISessionContext

- (instancetype)initWithSessionID:(NSString *)sessionID
                        packageID:(NSString *)packageID
               isNativeAPIGranted:(BOOL)isNativeAPIGranted {
  if (self = [super init]) {
    _sessionID = [sessionID copy];
    _packageID = [packageID copy];
    _isNativeAPIGranted = isNativeAPIGranted;
  }
  return self;
}

@end

static std::mutex sGateMutex;
static HanlinExpoNativeAPISessionContext *sActiveContext = nil;
static NSString *sBundledMetadataPathOverride = nil;

@implementation HanlinExpoNativeAPIGate

+ (void)registerActiveSessionContext:(HanlinExpoNativeAPISessionContext *)context {
  std::lock_guard<std::mutex> lock(sGateMutex);
  sActiveContext = context;
  NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Registered session context session=%@ package=%@ granted=%d",
        context.sessionID, context.packageID, context.isNativeAPIGranted);
}

+ (void)revokeSession:(NSString *)sessionID {
  std::lock_guard<std::mutex> lock(sGateMutex);
  if (sActiveContext != nil && [sActiveContext.sessionID isEqualToString:sessionID]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_GATE] Revoked active session context session=%@ package=%@",
          sActiveContext.sessionID, sActiveContext.packageID);
    sActiveContext = nil;
  }
}

+ (nullable HanlinExpoNativeAPISessionContext *)activeSessionContext {
  std::lock_guard<std::mutex> lock(sGateMutex);
  return sActiveContext;
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

+ (void)setBundledMetadataPathOverride:(nullable NSString *)path {
  std::lock_guard<std::mutex> lock(sGateMutex);
  sBundledMetadataPathOverride = [path copy];
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
  sActiveContext = nil;
  sBundledMetadataPathOverride = nil;
}

@end
