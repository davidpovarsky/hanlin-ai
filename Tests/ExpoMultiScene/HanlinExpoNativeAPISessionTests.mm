#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "HanlinExpoNativeAPIGate.h"
#include "HanlinExpoSessionRuntimeRegistry.h"

#include <memory>
#include <unordered_map>

namespace {
struct FakeWorklet {
  std::unordered_map<std::string, int> hosts;
};
HanlinExpoSessionRuntimeRegistry<FakeWorklet> worklets;
int allClearCount = 0;
NSMutableArray<NSString*> *clearedSessions = nil;

HanlinExpoNativeAPISessionContext *context(NSString *session, BOOL granted = YES) {
  return [[[HanlinExpoNativeAPISessionContext alloc] initWithSessionID:session
      packageID:[@"test." stringByAppendingString:session] isNativeAPIGranted:granted generation:1] autorelease];
}
}

void HanlinExpoNativeAPIClearWorkletRuntime(void) {
  ++allClearCount;
  worklets.clearAll();
}
void HanlinExpoNativeAPIClearWorkletRuntimeForSession(NSString *sessionID) {
  [clearedSessions addObject:sessionID];
  worklets.clear(sessionID.UTF8String);
}

@interface HanlinExpoNativeAPISessionTests : XCTestCase
@end

@implementation HanlinExpoNativeAPISessionTests
- (void)setUp {
  [super setUp];
  [HanlinExpoNativeAPIGate reset];
  [clearedSessions release];
  clearedSessions = [[NSMutableArray alloc] init];
  allClearCount = 0;
}

- (void)testOpeningBPreservesAAndItsExistingGrantBehavior {
  int runtimeA = 0, runtimeB = 0;
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A", NO)];
  [HanlinExpoNativeAPIGate bindRuntime:&runtimeA forSessionID:@"A"];
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  [HanlinExpoNativeAPIGate bindRuntime:&runtimeB forSessionID:@"B"];
  XCTAssertTrue([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtimeA]);
  XCTAssertTrue([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtimeB]);
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForRuntime:&runtimeA].sessionID, @"A");
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForRuntime:&runtimeB].sessionID, @"B");
  XCTAssertFalse([HanlinExpoNativeAPIGate sessionContextForRuntime:&runtimeA].isNativeAPIGranted);
}

- (void)testClosingBOnlyClearsBAndAPreservesItsUIKitHostNamespace {
  int runtimeA = 0, runtimeB = 0;
  auto a = std::make_shared<FakeWorklet>();
  auto b = std::make_shared<FakeWorklet>();
  a->hosts["counter:1"] = 11;
  b->hosts["counter:1"] = 22;
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  [HanlinExpoNativeAPIGate bindRuntime:&runtimeA forSessionID:@"A"];
  [HanlinExpoNativeAPIGate bindRuntime:&runtimeB forSessionID:@"B"];
  worklets.bind("A", a);
  worklets.bind("B", b);
  XCTAssertEqual(worklets.find("A")->hosts["counter:1"], 11);
  XCTAssertEqual(worklets.find("B")->hosts["counter:1"], 22);
  [HanlinExpoNativeAPIGate revokeSession:@"B"];
  XCTAssertTrue([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtimeA]);
  XCTAssertFalse([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtimeB]);
  XCTAssertTrue(worklets.find("A") == a);
  XCTAssertTrue(worklets.find("B") == nullptr);
  XCTAssertEqual(worklets.find("A")->hosts["counter:1"], 11);
  XCTAssertEqual(allClearCount, 0);
  XCTAssertEqualObjects(clearedSessions, (@[@"B"]));
}

- (void)testUnboundRuntimeNeverInheritsTheMostRecentWindow {
  int runtime = 0;
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  XCTAssertFalse([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]);
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  XCTAssertFalse([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]);
  XCTAssertFalse([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:nullptr]);
  [HanlinExpoNativeAPIGate bindRuntime:&runtime forSessionID:@"A"];
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForRuntime:&runtime].sessionID, @"A");
}

- (void)testUnknownAndRepeatedCloseCannotRevokeAnotherOwner {
  int runtimeA = 0;
  auto a = std::make_shared<FakeWorklet>();
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  [HanlinExpoNativeAPIGate bindRuntime:&runtimeA forSessionID:@"A"];
  worklets.bind("A", a);
  [HanlinExpoNativeAPIGate revokeSession:@"never-started"];
  [HanlinExpoNativeAPIGate revokeSession:@"never-started"];
  XCTAssertTrue([HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtimeA]);
  XCTAssertTrue(worklets.find("A") == a);
  XCTAssertEqual(allClearCount, 0);
}

- (void)testLegacyCleanupRequiresAnUnambiguousOwner {
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  XCTAssertNil([HanlinExpoNativeAPIGate activeSessionContext]);
  [HanlinExpoNativeAPIGate revokeActiveSession];
  XCTAssertNotNil([HanlinExpoNativeAPIGate sessionContextForSessionID:@"A"]);
  XCTAssertNotNil([HanlinExpoNativeAPIGate sessionContextForSessionID:@"B"]);
  [HanlinExpoNativeAPIGate revokeSession:@"B"];
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate activeSessionContext].sessionID, @"A");
  [HanlinExpoNativeAPIGate revokeActiveSession];
  XCTAssertNil([HanlinExpoNativeAPIGate activeSessionContext]);
}

- (void)testUIKitRootsResolveTheirOwnNestedViews {
  XCTAssertTrue([NSThread isMainThread]);
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  UIView *rootA = [[[UIView alloc] init] autorelease];
  UIView *rootB = [[[UIView alloc] init] autorelease];
  UIView *nested = [[[UIView alloc] init] autorelease];
  UIView *child = [[[UIView alloc] init] autorelease];
  [HanlinExpoNativeAPIGate bindView:rootA forSessionID:@"A"];
  [HanlinExpoNativeAPIGate bindView:rootB forSessionID:@"B"];
  [rootA addSubview:nested];
  [nested addSubview:child];
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForView:child].sessionID, @"A");
  [rootB addSubview:child];
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForView:child].sessionID, @"B");
  [HanlinExpoNativeAPIGate revokeSession:@"B"];
  XCTAssertNil([HanlinExpoNativeAPIGate sessionContextForView:child]);
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForView:nested].sessionID, @"A");
}

- (void)testReusedRuntimeAddressRequiresExplicitNewOwnerBinding {
  int runtime = 0;
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  [HanlinExpoNativeAPIGate bindRuntime:&runtime forSessionID:@"A"];
  [HanlinExpoNativeAPIGate revokeSession:@"A"];
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  XCTAssertNil([HanlinExpoNativeAPIGate sessionContextForRuntime:&runtime]);
  [HanlinExpoNativeAPIGate bindRuntime:&runtime forSessionID:@"B"];
  XCTAssertEqualObjects([HanlinExpoNativeAPIGate sessionContextForRuntime:&runtime].sessionID, @"B");
}

- (void)testRegistryDoesNotKeepClosedWorkletAlive {
  auto a = std::make_shared<FakeWorklet>();
  std::weak_ptr<FakeWorklet> observed = a;
  worklets.bind("A", a);
  a.reset();
  XCTAssertTrue(observed.expired());
  XCTAssertTrue(worklets.find("A") == nullptr);
}

- (void)testExplicitGlobalInvalidationRemovesAllSessionsAndWorklets {
  auto a = std::make_shared<FakeWorklet>();
  auto b = std::make_shared<FakeWorklet>();
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"A")];
  [HanlinExpoNativeAPIGate registerActiveSessionContext:context(@"B")];
  worklets.bind("A", a);
  worklets.bind("B", b);
  [HanlinExpoNativeAPIGate invalidateAllSessions];
  XCTAssertNil([HanlinExpoNativeAPIGate sessionContextForSessionID:@"A"]);
  XCTAssertNil([HanlinExpoNativeAPIGate sessionContextForSessionID:@"B"]);
  XCTAssertTrue(worklets.find("A") == nullptr);
  XCTAssertTrue(worklets.find("B") == nullptr);
  XCTAssertEqual(allClearCount, 1);
}
@end
