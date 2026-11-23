// Reproducible patches for the pinned @nativescript/react-native iOS sources.
// The preparation pipeline feeds pristine upstream files to these functions.
function replaceOnce(source, before, after, label) {
  const count = source.split(before).length - 1;
  if (count !== 1) throw new Error(`[HanlinExpoNativeAPI] ${label}: expected one anchor, found ${count}`);
  return source.replace(before, after);
}

export function patchNativeModuleForSessions(source) {
  source = '#include "HanlinExpoNativeAPIGate.h"\n#include "HanlinExpoSessionRuntimeRegistry.h"\n' + source;
  source = replaceOnce(source, 'std::string bundledMetadataPath() {', `std::string bundledMetadataPath() {
  NSString* gatePath = [HanlinExpoNativeAPIGate bundledMetadataPath];
  if (gatePath.length > 0) return gatePath.UTF8String;`, 'metadata path');

  const registryStart = source.indexOf('std::mutex& nativeScriptWorkletRuntimeMutex() {');
  const registryEnd = source.indexOf('NSString* stringProperty(', registryStart);
  if (registryStart < 0 || registryEnd < 0) throw new Error('Missing upstream worklet registry');
  source = source.slice(0, registryStart) + `HanlinExpoSessionRuntimeRegistry<worklets::WorkletRuntime>& nativeScriptWorkletRuntimes() {
  static HanlinExpoSessionRuntimeRegistry<worklets::WorkletRuntime> runtimes;
  return runtimes;
}

` + source.slice(registryEnd);

  source = replaceOnce(source,
    'runUIKitHostFunction(NSString* hostId, NSString* phase,',
    'runUIKitHostFunction(NSString* sessionID, NSString* hostId, NSString* phase,', 'UIKit host namespace');
  source = replaceOnce(source,
    '  auto workletRuntime = getNativeScriptWorkletRuntime();',
    `  if ([HanlinExpoNativeAPIGate sessionContextForSessionID:sessionID] == nil) return nil;
  auto workletRuntime = nativeScriptWorkletRuntimes().find(sessionID.UTF8String);`, 'UIKit worklet lookup');
  source = replaceOnce(source,
    `         globalName](facebook::jsi::Runtime& runtime) -> NSDictionary<NSString*, NSString*>* {
          auto global = runtime.global();`,
    `         globalName](facebook::jsi::Runtime& runtime) -> NSDictionary<NSString*, NSString*>* {
          if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]) return nil;
          auto global = runtime.global();`, 'UIKit deferred runtime lifetime');

  const createStart = source.indexOf('NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId) {');
  const createEnd = source.indexOf('namespace facebook::react {', createStart);
  if (createStart < 0 || createEnd < 0) throw new Error('Missing upstream UIKit host entry points');
  source = source.slice(0, createStart) + `NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId) {
  return NativeScriptCreateUIKitHostForSession(hostId, [HanlinExpoNativeAPIGate activeSessionContext].sessionID);
}

NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycle(NSString* hostId, NSString* phase) {
  return NativeScriptRunUIKitHostLifecycleForSession(hostId, phase, [HanlinExpoNativeAPIGate activeSessionContext].sessionID);
}

NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHostForSession(NSString* hostId, NSString* sessionID) {
  if ([HanlinExpoNativeAPIGate sessionContextForSessionID:sessionID] == nil) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] UIKit create has no live owning session.");
    return nil;
  }
  return runUIKitHostFunction(sessionID, hostId, nil, "__nativeScriptCreateUIKitHostFromNative", "create");
}

NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycleForSession(NSString* hostId, NSString* phase, NSString* sessionID) {
  if ([HanlinExpoNativeAPIGate sessionContextForSessionID:sessionID] == nil) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] UIKit lifecycle has no live owning session.");
    return nil;
  }
  return runUIKitHostFunction(sessionID, hostId, phase, "__nativeScriptRunUIKitHostLifecycleFromNative", "run");
}

` + source.slice(createEnd);

  for (const [anchor, name] of [
    ['bool NativeScriptNativeApiModule::install(jsi::Runtime& runtime, std::string metadataPath) {', 'install'],
    [`bool NativeScriptNativeApiModule::installWorkletRuntime(jsi::Runtime& runtime,
                                                        jsi::Object runtimeHolder,
                                                        std::string metadataPath) {`, 'installWorkletRuntime']
  ]) {
    source = replaceOnce(source, anchor, anchor + `
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] ${name} has no live owning runtime session.");
    return false;
  }`, name + ' gate');
  }

  source = replaceOnce(source, '  setNativeScriptWorkletRuntime(holder->runtime_);', `  HanlinExpoNativeAPISessionContext* context = [HanlinExpoNativeAPIGate sessionContextForRuntime:&runtime];
  if (context == nil) return false;
  std::string ownerSession = context.sessionID.UTF8String;
  nativeScriptWorkletRuntimes().bind(ownerSession, holder->runtime_);`, 'worklet owner registration');
  source = replaceOnce(source,
    `       workletRuntimeRef = std::move(workletRuntimeRef)](
          jsi::Runtime& workletRuntime) -> bool {
        if (!nativeApiInstalled(workletRuntime)) {`,
    `       workletRuntimeRef = std::move(workletRuntimeRef), ownerSession](
          jsi::Runtime& workletRuntime) -> bool {
        NSString* sessionID = [NSString stringWithUTF8String:ownerSession.c_str()];
        [HanlinExpoNativeAPIGate bindRuntime:&workletRuntime forSessionID:sessionID];
        if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&workletRuntime]) return false;
        if (!nativeApiInstalled(workletRuntime)) {`, 'worklet runtime binding');
  source = replaceOnce(source,
    `                    [taskBox = std::move(taskBox), done](jsi::Runtime&) mutable {
                      (*taskBox)();
                      dispatch_semaphore_signal(done);`,
    `                    [taskBox = std::move(taskBox), done](jsi::Runtime& callbackRuntime) mutable {
                      if ([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&callbackRuntime]) {
                        (*taskBox)();
                      }
                      dispatch_semaphore_signal(done);`, 'queued callback lifetime');

  source += `
void HanlinExpoNativeAPIClearWorkletRuntimeForSession(NSString* sessionID) {
  if (sessionID != nil) nativeScriptWorkletRuntimes().clear(sessionID.UTF8String);
}

void HanlinExpoNativeAPIClearWorkletRuntime(void) {
  nativeScriptWorkletRuntimes().clearAll();
}
`;
  if (source.split('[HANLIN_EXPO_NATIVEAPI_DENIAL]').length - 1 !== 4 ||
      source.split('installWorkletRuntime(').length - 1 !== 1 ||
      source.includes('getNativeScriptWorkletRuntime()')) {
    throw new Error('NativeAPI multiscene patch validation failed');
  }
  return source;
}

export function patchUIKitHostHeaderForSessions(source) {
  return source + `
// Host IDs are only unique within one JavaScript VM.
FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHostForSession(
    NSString* hostId, NSString* sessionID);
FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycleForSession(
    NSString* hostId, NSString* phase, NSString* sessionID);
`;
}

export function patchUIKitViewForSessions(source) {
  source = '#import "HanlinExpoNativeAPIGate.h"\n' + source;
  source = replaceOnce(source, '  NSString* _lastHostReadyKey;\n}', `  NSString* _lastHostReadyKey;
  NSString* _hanlinSessionID;
}`, 'view owner storage');
  source = replaceOnce(source, `- (void)dealloc {
  if (_hostId.length > 0) {`, `// Cache ownership while attached, so disposal after removal still addresses
// the original VM. A host ID alone must never select another window's runtime.
- (NSString*)hanlinSessionID {
  if (_hanlinSessionID == nil) {
    _hanlinSessionID = [[HanlinExpoNativeAPIGate sessionContextForView:self].sessionID copy];
  }
  return _hanlinSessionID;
}

- (void)dealloc {
  if (_hostId.length > 0) {`, 'view owner resolution');
  source = replaceOnce(source, '    NativeScriptRunUIKitHostLifecycle(_hostId, @"dispose");',
    '    NativeScriptRunUIKitHostLifecycleForSession(_hostId, @"dispose", [self hanlinSessionID]);', 'view disposal owner');
  source = replaceOnce(source, '    NativeScriptRunUIKitHostLifecycle(previousHostId, @"dispose");',
    '    NativeScriptRunUIKitHostLifecycleForSession(previousHostId, @"dispose", [self hanlinSessionID]);', 'host replacement owner');
  source = replaceOnce(source, '  [_lastHostReadyKey release];\n  [super dealloc];',
    '  [_lastHostReadyKey release];\n  [_hanlinSessionID release];\n  [super dealloc];', 'view owner release');
  source = replaceOnce(source, 'NativeScriptCreateUIKitHost(_hostId)',
    'NativeScriptCreateUIKitHostForSession(_hostId, [self hanlinSessionID])', 'view mount owner');
  source = replaceOnce(source, 'NativeScriptRunUIKitHostLifecycle(_hostId, phase)',
    'NativeScriptRunUIKitHostLifecycleForSession(_hostId, phase, [self hanlinSessionID])', 'view lifecycle owner');
  return source;
}
