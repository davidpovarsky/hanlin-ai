import type { NativeWindow, View, NavigationEntry } from '@nativescript/core';
import type { createHostServicesForBridge } from '@hanlin/host-services';

export interface MiniAppWindowContext {
  readonly id: string;
  readonly window: NativeWindow;
  readonly services: ReturnType<typeof createHostServicesForBridge>;
}
/** Called once per Host window. Capture this context in every async callback. */
export declare function registerWindowFactory(
  factory: (context: MiniAppWindowContext) => View | NavigationEntry | null | void |
    Promise<View | NavigationEntry | null | void>
): void;
