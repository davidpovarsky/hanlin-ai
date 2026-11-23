#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId);

FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycle(
    NSString* hostId, NSString* phase);

FOUNDATION_EXPORT BOOL NativeScriptRefreshUIKitHostView(NSString* viewHandle);

// Host IDs are only unique within one JavaScript VM.
FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHostForSession(
    NSString* hostId, NSString* sessionID);
FOUNDATION_EXPORT NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycleForSession(
    NSString* hostId, NSString* phase, NSString* sessionID);
