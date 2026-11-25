/** JSON data carried unchanged to the existing declared package action. */
export type HanlinNotificationJSONValue =
  | null | boolean | number | string
  | HanlinNotificationJSONValue[]
  | { [key: string]: HanlinNotificationJSONValue };

/** Values come from the current installed package, not an authored generation guess. */
export interface HanlinNotificationTargetV1 {
  installedPackageID: string;
  packageID: string;
  generation: number;
  entrypointID: string;
  variantID?: string;
}

/**
 * Data in userInfo["hanlin-miniapp-event"] for local/remote notifications.
 * Import this package with "import type"; it contains no JavaScript runtime.
 */
export interface HanlinNotificationEventV1 {
  schemaVersion: 1;
  /** Stable UUID for this event, reused for delivery and a later response. */
  id: string;
  /** Whole Unix milliseconds, independent of Foundation's Date coding strategy. */
  createdAtUnixMilliseconds: number;
  expiresAtUnixMilliseconds: number;
  appID: string;
  identity: HanlinNotificationTargetV1;
  /** Exact, case-preserving ID of an existing declared appIntent action. */
  actionID: string;
  parameters: HanlinNotificationJSONValue;
}

export interface HanlinNotificationUserInfoV1 {
  "hanlin-miniapp-event": HanlinNotificationEventV1;
  [key: string]: unknown;
}
