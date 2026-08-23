# Scripting Apple device services

These adapters are downstream-owned and expose bounded values rather than raw
Apple framework objects. Package permission grants are evaluated by
`HanlinScriptServiceBroker` before an adapter is called; system authorization
is then requested at the point of use.

The app target already contains the required HealthKit and notification
entitlements and localized usage descriptions for HealthKit, Location,
Calendars, and Reminders. This commit intentionally preserves those signing
settings instead of duplicating or replacing them.

The implementation uses current asynchronous Apple APIs:

- `CLLocationUpdate.liveUpdates()` for one-shot current location delivery;
- async `UNUserNotificationCenter` authorization and scheduling;
- async `HKHealthStore` authorization and `HKStatisticsQueryDescriptor`;
- EventKit full-access authorization for events and reminders.

Widget and other presentation-constrained contexts remain denied for HealthKit
and EventKit in the explicit availability table. There are no permissive stubs:
an absent platform implementation is reported as unsupported by platform.
