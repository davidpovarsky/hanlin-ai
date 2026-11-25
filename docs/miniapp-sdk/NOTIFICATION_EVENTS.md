# Typed notification events and foreground actions

Hanlin AI and Hanlin MiniApps share the versioned notification contract, their existing product-scoped App Group queue, installed-package action broker and durable invocation receipts. Notifications carry JSON parameters for an installed action, never executable source or a replacement runtime.

## Typed authoring

The selected Expo/NativeScript engine from get_miniapp_sdk exposes notificationEvents metadata and the declaration-only package @hanlin/notification-events. Its packageVersions entry distinguishes this Hanlin Host contract from original upstream libraries. Import HanlinNotificationEventV1 with import type; this package has no JavaScript runtime.

Put that event object in userInfo["hanlin-miniapp-event"]. For an eligible remote alert, the outer provider payload also needs the original Apple aps.alert and aps.mutable-content=1. For local notifications, use the same custom userInfo key. The two existing hello-world SDK examples include typed event construction without sending notifications.

[The exact JSON schema](notification-event.schema.json) specifies all required top-level fields: schemaVersion=1, id, createdAtUnixMilliseconds, expiresAtUnixMilliseconds, appID, identity, actionID and parameters. Identity follows HanlinScriptExtensionIdentity: installedPackageID, packageID, generation, entrypointID and optional variantID (default "default").

Resolve the current installed identity and declared action from the product catalog. Use a fresh UUID and current whole Unix milliseconds. Reuse the identical event for retries/delivery/taps. The native decoder checks version, UUIDs, canonical identifiers, finite JSON and time relationships. App/package/installed IDs keep their existing lowercase ASCII rules; action IDs preserve declared case. TypeScript checks structure and literal version; native admission checks actual identity/time validity.

Expiry is after creation and uses the unchanged canonical queue maximumLifetime (24 hours), shared by the queue and adapter. This is the existing delivery contract, not an additional adapter quota. The manifest and original Host service must already declare/register the appIntent action. No notificationUI entrypoint is required; rich notification views are separate.

## Native ingress

| Delivery | Existing Apple entry point | Hanlin behavior |
| --- | --- | --- |
| Mutable remote alert | Product Notification Service Extension | Persist the event; preserve category/media handling; execute no package VM. |
| Local/remote foreground delivery | UNUserNotificationCenterDelegate.willPresent | Persist and schedule foreground continuation; forward the original delegate's presentation decision. With no earlier delegate, preserve no foreground presentation. |
| Notification open/custom response | UNUserNotificationCenterDelegate.didReceive | Enqueue the identical event and forward the actual response; a dismiss response enqueues no new work. |
| Foreground recovery | Original deliveredNotifications query and queue | Recover tagged OS-delivered events, including local/nonmutable background delivery and prior locked-storage failures; no polling. |

Both Apps install the shared delegate with UIApplicationDelegateAdaptor before didFinishLaunching returns. The service wrappers reuse HanlinNotificationService. MiniApps uses HanlinMiniApps/v1 within the original App Group; its event IDs never alias AI receipts.



Apple runs the [Notification Service Extension](https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension) for eligible remote alerts with mutable-content, not for local notifications, silent pushes or badge-only deliveries. The [notification center delegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate) supplies the separate foreground/response route. This integration does not request notification permission or configure an APNs provider. Delivery by the OS and by a remote provider needs its own actual evidence.

## Queue and live dispatch

The notification envelope enters the original durable queue before target dispatch. The published extension catalog is an asynchronous snapshot, so it cannot reject an otherwise valid new-generation event or authorize an obsolete one. Missing or stale publication does not discard a delivered event. Immediately before execution, the Host restores the actual installed package store and validates app/package/installed IDs, enabled state, current generation, the selected appIntent entrypoint, Expo/NativeScript runtime profile, exact case-preserved action ID and its declared handler.

An inactive Host leaves the invocation queued without consuming an action attempt. When the Host can resume, its existing broker and package session call the installed handler. The notification service extension never starts a package VM or promises background action execution. Local or nonmutable background notifications become available to this route on an actual response or foreground delivered-notification recovery; there is no background execution promise.

If App Group construction or a canonical queue write is temporarily unavailable during an app callback, the platform retains the exact decoded event in memory until its normal preparation/foreground retry can persist it. It does not depend on a tapped notification remaining in the delivered list. This memory retention is not a separate durable inbox: if the process terminates before canonical persistence, only an independently retained OS delivery can be recovered. Once enqueued, the original durable storage and receipts survive reopening.

## Results, errors and replay

Delivery and a later response use the same UUID and unchanged envelope. Canonical enqueue preserves the original command, lease and terminal receipt. Changed content under that UUID is rejected; it never replaces the prior event. No code is inferred from payload text. Use a new UUID for a genuinely new action.

The queue records the handler's actual value or failure. Stale/removed/disabled installations produce the existing stale failure receipt; an undeclared action produces unsupportedEntrypoint. Cancellation and expiry keep their existing distinct states, and an expired new event is terminal without invoking a handler. Interrupted unknown outcomes retain the existing queue recovery rules; notifications do not automatically replay a potentially executed non-idempotent action.

Read results through the existing invocation receipt interface (including HanlinAwaitInvocationResultIntent / HanlinInvocationSnippetIntent and the platform resumeReceipt method). The notification service adds hanlin-miniapp-delivery metadata with the actual receipt status at enqueue time, or an explicit ingress rejection. A queued status is not an action success; that observation is not a live result stream.


## Verification and regeneration

HanlinNotificationInvocationTests exercise actual durable queue persistence, reopened receipts, duplicate/conflicting IDs, live-generation/catalog races, undeclared or disabled targets, foreground deferral, expiry, cancellation and handler errors. Their supplied handler closure checks the queue/target contract; it is not proof that Expo or NativeScript executed a package. The existing MiniApps storage-isolation case also covers an early event retained while its product App Group is unavailable.

Scripts/MiniApps/Tests/notification-events.test.mjs uses the original installed TypeScript compiler: the valid wire type must compile, and invalid version, generation type, missing action, executable parameters and unknown fields must produce diagnostics. The event examples are included in the existing Expo and NativeScript documentation projects.

Use the existing unified manifest/project generators after changing the service dependency, shared app delegate or MiniApps extension target. The normal native preparation then regenerates source inventory, reachability dispositions, Host SDK inputs and the embedded RuntimeHostResources archive. Both actual consumer builds must bind the newly prepared bytes; a previous archive cannot establish the new ingress wiring. Native notification callbacks, real installed handler delivery and physical/provider contexts require their own recorded executions. Source reachability does not mean every OS-context matrix cell passed.
