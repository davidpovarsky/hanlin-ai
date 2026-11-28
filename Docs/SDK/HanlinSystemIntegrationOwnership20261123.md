# Original system integrations: host ownership correction

Date: 2026-11-23. Integration branch: codex/hanlin-sdk-unification-20261123.
The running native producer 45112778130 at e33247fb predates this correction.

## Observed gaps and correction

The original bootstrap called setNotificationCategories with a single Hanlin
category. Apple documents that this setter replaces the entire registered set.
The original Share Inbox also hard-coded Hanlin's App Group, and the exported
Vision intent always opened Hanlin's scheme and returned success without checking
whether the URL opened.

The existing original sources now read immutable host system integration
configuration installed with the same process runtime owner. Plain hosts inherit
none of Hanlin's group/category/camera URL. The .hanlin profile keeps all three
original values. The bootstrap preserves registered categories and their actions;
the original shared-batch storage, verified attachment copying, original UI,
draft cancellation, source-batch retention and invocation authorization are reused.
No extension, entitlement, store schema, batch serialization, engine or UI was
reimplemented.

Public entries: HanlinApplicationSystemIntegrations,
HanlinApplicationConfiguration.systemIntegrations, HanlinShareInboxView,
HanlinApplicationPanel.shareInbox, HanlinSharedDraft,
prepareSharedDraft, discardPreparedSharedDraft, and isVisionURL.
OpenVisionIntent uses the same configured route as the full application scene.

## Verification scope

- Real Swift 6 type-check of the Foundation-only runtime/system configuration:
  PASS on Oracle.
- Syntax parse of the other eight changed original Swift files and the new
  focused native suite: PASS.
- Whitespace/diff check: PASS.
- Prepared native selectors in HanlinApplicationSystemIntegrationTests:
  notificationBootstrapPreservesHostActionsAndCategories,
  plainHostsDoNotInheritHanlinShareGroupOrCameraRoute,
  liveSystemIntegrationOwnershipCannotBeRedirected.
- Actual UserNotifications/UIKit compilation and native test execution: pending
  the integrated source gate; the already running producer does not include this delta.
- Signed host App Groups, OS share sheet delivery, notification delivery and
  actual camera intent invocation remain separate physical acceptance gates.

## Primary API contracts

- [Apple: registering notification categories](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/setnotificationcategories(_:)).
- [Apple: application group container lookup](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)).
- [Apple: App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups).

The earlier Calendar privacy-key hypothesis was not adopted: current Hanlin and
MiniApps already declare the full-access usage strings in generated Info.plist
settings. Apple's current [EventKit access contract](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)
describes automatic denial for missing modern usage strings; its missing-key
crash warning concerns apps linked against iOS 10–16. No calendar crash cause is
claimed from this configuration inspection.
