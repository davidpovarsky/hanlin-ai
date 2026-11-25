export type MiniAppJSONValue = null | boolean | number | string | MiniAppJSONValue[] | { [key: string]: MiniAppJSONValue };

export interface MiniAppActionInvocation {
  id: string;
  action: string;
  caller: string;
  parameters: MiniAppJSONValue;
}

export type MiniAppActionHandler = (invocation: MiniAppActionInvocation) => MiniAppJSONValue | Promise<MiniAppJSONValue>;
export type MiniAppActionHandlers = Readonly<Record<string, MiniAppActionHandler>>;
export type MiniAppInvoke = <T>(operation: string, payload: unknown) => Promise<T>;

function assertJSONValue(value: unknown, ancestors = new Set<object>()): asserts value is MiniAppJSONValue {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error('Action result contains a non-finite number.');
    return;
  }
  if (typeof value !== 'object') throw new Error('Action result contains a non-JSON value.');
  if (ancestors.has(value)) throw new Error('Action result contains a cycle.');
  ancestors.add(value);
  try {
    if (Array.isArray(value)) {
      for (const item of value) assertJSONValue(item, ancestors);
    } else {
      const prototype = Object.getPrototypeOf(value);
      if (prototype !== Object.prototype && prototype !== null) throw new Error('Action result must contain plain JSON objects.');
      for (const item of Object.values(value)) assertJSONValue(item, ancestors);
    }
  } finally { ancestors.delete(value); }
}

/** Serves a complete handler table for the lifetime of this Expo session.
 * The returned promise remains pending while serving, and rejects on transport
 * errors. Each request is acknowledged only after its handler returns.
 */
export async function serveMiniAppActions(invoke: MiniAppInvoke, handlers: MiniAppActionHandlers): Promise<void> {
  await invoke('actions.register', { names: Object.keys(handlers) });
  for (;;) {
    const request = await invoke<MiniAppActionInvocation>('actions.next', {});
    let response: { id: string; value?: MiniAppJSONValue; error?: string };
    try {
      const handler = handlers[request.action];
      if (!handler) throw new Error(`No registered handler for ${request.action}`);
      const value = await handler(request);
      if (value === undefined) throw new Error('An action must return a JSON value (use null for no result).');
      // Verify the result before claiming success; cyclic and non-JSON data
      // must not leave the native invocation awaiting an impossible response.
      assertJSONValue(value);
      const encoded = JSON.stringify(value);
      if (encoded === undefined) throw new Error('Action result is not JSON serializable.');
      response = { id: request.id, value: JSON.parse(encoded) as MiniAppJSONValue };
    } catch (error) {
      response = { id: request.id, error: error instanceof Error ? error.message : String(error) };
    }
    await invoke('actions.complete', response);
  }
}
