import type { NativeWindow, View, NavigationEntry } from '@nativescript/core';
import type { createHostServicesForBridge } from '@hanlin/host-services';

export interface MiniAppWindowContext {
  readonly id: string;
  readonly packageID: string;
  /** Explicit package/window environment; never process-global environment. */
  readonly environment: Readonly<Record<string, string>>;
  readonly storage: Readonly<{root?: string; state?: string; documents?: string; cache?: string}>;
  /** Absolute path constrained to this live window's immutable source namespace. */
  resourcePath(relativePath: string): string;
  readonly window: NativeWindow;
  readonly services: ReturnType<typeof createHostServicesForBridge>;
}
/** Called once per Host window. Capture this context in every async callback. */
export declare function registerWindowFactory(
  factory: (context: MiniAppWindowContext) => View | NavigationEntry | null | void |
    Promise<View | NavigationEntry | null | void>
): void;
