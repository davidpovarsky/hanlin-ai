import type { HanlinNotificationEventV1 } from '@hanlin/notification-events';

/** A typed server/local-notification payload; resolve the actual installation before delivery. */
export function notificationEventForInstalledAction(
  identity: HanlinNotificationEventV1['identity'],
  appID: string,
  actionID: string,
  id: string,
  createdAtUnixMilliseconds: number,
): HanlinNotificationEventV1 {
  return {
    schemaVersion: 1, id, createdAtUnixMilliseconds,
    expiresAtUnixMilliseconds: createdAtUnixMilliseconds + 60_000,
    appID, identity, actionID,
    parameters: { text: 'שלום', sourceURL: 'https://example.test/source' },
  };
}
