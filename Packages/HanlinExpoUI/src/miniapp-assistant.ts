/** Session-bound native AI. Uses Hanlin's Swift engine and configured providers. */
export type MiniAppAssistantJSON =
  | null | boolean | number | string | MiniAppAssistantJSON[]
  | { [key: string]: MiniAppAssistantJSON };

export interface MiniAppAssistantModel {
  /** Stable UUID of the existing Hanlin model record. */
  id: string;
  modelID: string;
  displayName: string;
  provider: string;
  imageInput: boolean;
  structuredOutput: boolean;
  onDevice: boolean;
}
export type MiniAppAssistantPart =
  | {type: 'text'; text: string}
  | {type: 'image'; url: string; mediaType?: string}
  | {type: 'image'; base64: string; mediaType: string};
export interface MiniAppAssistantRequest {
  /** Choose an ID from models(); otherwise use Hanlin's configured default. */
  model?: string;
  /** Scoped to this actual MiniApp session by the native host. */
  conversationID?: string;
  system?: string;
  messages: {role: 'user' | 'assistant'; content: string | MiniAppAssistantPart[]}[];
  temperature?: number;
  maxOutputTokens?: number;
  reasoning?: boolean;
  /** Original JSON Schema. Structured mode emits no partial, unvalidated JSON. */
  responseSchema?: {[key: string]: MiniAppAssistantJSON};
}
export interface MiniAppAssistantUsage {
  inputTokens?: number;
  outputTokens?: number;
  reasoningTokens?: number;
  cachedInputTokens?: number;
  cacheWriteTokens?: number;
  totalTokens?: number;
}
export type MiniAppAssistantEvent =
  | {type: 'text'; text: string}
  | {type: 'reasoning'; text: string}
  | {type: 'source'; id: string; url: string; title?: string}
  | {type: 'structured'; value: MiniAppAssistantJSON}
  | {type: 'finish'; finishReason: string; usage: MiniAppAssistantUsage};
export interface MiniAppAssistantRun {
  readonly requestID: string;
  /** A single consumer, including for-await break/return cancellation. */
  readonly events: AsyncIterable<MiniAppAssistantEvent>;
  cancel(): Promise<void>;
}
export interface MiniAppAssistantResult {
  text: string;
  reasoning: string;
  value?: MiniAppAssistantJSON;
  sources: Extract<MiniAppAssistantEvent, {type: 'source'}>[];
  finishReason: string;
  usage: MiniAppAssistantUsage;
}
/** Compatible with AbortSignal without requiring a browser runtime. */
export interface MiniAppAssistantAbortSignal {
  readonly aborted: boolean;
  addEventListener(type: 'abort', listener: () => void): void;
  removeEventListener(type: 'abort', listener: () => void): void;
}
export interface MiniAppAssistantOptions { signal?: MiniAppAssistantAbortSignal }
export interface MiniAppAssistant {
  models(): Promise<MiniAppAssistantModel[]>;
  start(request: MiniAppAssistantRequest): Promise<MiniAppAssistantRun>;
  stream(request: MiniAppAssistantRequest, options?: MiniAppAssistantOptions): AsyncIterable<MiniAppAssistantEvent>;
  generate(request: MiniAppAssistantRequest, options?: MiniAppAssistantOptions): Promise<MiniAppAssistantResult>;
}
export type MiniAppAssistantInvoke = <T>(operation: string, payload: unknown) => Promise<T>;

function abortError(): Error {
  const error = new Error('Assistant request cancelled.');
  error.name = 'AbortError';
  return error;
}

/** Transport-only facade shared by Expo and NativeScript; no provider SDK or keys. */
export function createMiniAppAssistant(invoke: MiniAppAssistantInvoke): MiniAppAssistant {
  async function start(request: MiniAppAssistantRequest): Promise<MiniAppAssistantRun> {
    const {responseSchema, ...rest} = request;
    const wire = {...rest, responseSchemaJSON: responseSchema === undefined ? undefined : JSON.stringify(responseSchema)};
    const {requestID} = await invoke<{requestID: string}>('assistant.start', wire);
    if (typeof requestID !== 'string' || requestID.length === 0) throw new Error('Assistant returned an invalid request handle.');
    let cancellation: Promise<void> | undefined;
    let cancelled = false;
    let finished = false;
    let consuming = false;
    function cancel(): Promise<void> {
      cancelled = true;
      if (finished) return Promise.resolve();
      cancellation ??= invoke('assistant.cancel', {requestID}).then(() => {});
      return cancellation;
    }
    const events: AsyncIterable<MiniAppAssistantEvent> = {
      async *[Symbol.asyncIterator]() {
        if (consuming) throw new Error('Only one reader may consume an assistant request.');
        consuming = true;
        try {
          while (!finished) {
            if (cancelled) throw abortError();
            const receipt = await invoke<{event: MiniAppAssistantEvent}>('assistant.next', {requestID});
            if (cancelled) throw abortError();
            if (!receipt || !receipt.event || !['text', 'reasoning', 'source', 'structured', 'finish'].includes(receipt.event.type)) {
              throw new Error('Assistant returned an invalid event.');
            }
            if (receipt.event.type === 'finish') finished = true;
            yield receipt.event;
          }
        } catch (error) {
          if (cancelled) throw abortError();
          throw error;
        } finally {
          // Consumer break, transport failure and abort all reach native cancellation.
          if (!finished) await cancel().catch(() => {});
        }
      },
    };
    return {requestID, events, cancel};
  }

  async function* stream(request: MiniAppAssistantRequest, options: MiniAppAssistantOptions = {}) {
    const signal = options.signal;
    if (signal?.aborted) throw abortError();
    const run = await start(request);
    const onAbort = () => { void run.cancel().catch(() => {}); };
    signal?.addEventListener('abort', onAbort);
    try {
      // The signal can change while the native start admission is awaiting a model.
      if (signal?.aborted) { await run.cancel(); throw abortError(); }
      for await (const event of run.events) yield event;
    } finally {
      signal?.removeEventListener('abort', onAbort);
      await run.cancel().catch(() => {});
    }
  }

  return {
    models: () => invoke('assistant.models', {}),
    start,
    stream,
    async generate(request, options = {}) {
      const result: MiniAppAssistantResult = {text: '', reasoning: '', sources: [], finishReason: '', usage: {}};
      for await (const event of stream(request, options)) {
        switch (event.type) {
          case 'text': result.text += event.text; break;
          case 'reasoning': result.reasoning += event.text; break;
          case 'source': result.sources.push(event); break;
          case 'structured': result.value = event.value; break;
          case 'finish': result.finishReason = event.finishReason; result.usage = event.usage; break;
        }
      }
      return result;
    },
  };
}
