import type {createHostServices} from '@hanlin/host-services';
type Execute = ReturnType<typeof createHostServices>['executeRuntime'];

type Receipt = Awaited<ReturnType<Execute>>;
type RuntimeKind = Parameters<Execute>[0];
export type JSONValue = null | boolean | number | string | JSONValue[] | {[key: string]: JSONValue};

export interface PresentationSample {
  windowID: string;
  statePath: string;
  executionMode: string;
  attached: boolean;
}
export interface SurfaceResult {
  schemaVersion: 1;
  appID: string;
  action: 'surface.run';
  challenge: string;
  nonce: string;
  requestID: string;
  requestIDOrigin: 'host-invocation' | 'javascript-handler';
  caller: string;
  request: JSONValue;
  requestedSurface: string;
  counter: number;
  startedAt: string;
  finishedAt?: string;
  status: 'running' | 'completed' | 'failed';
  receipts: Array<{kind: RuntimeKind; marker: string; receipt: Receipt}>;
  error?: string;
  summary?: string;
  presentationSamples?: PresentationSample[];
}
export interface SurfaceState {
  schemaVersion: 1;
  appID: string;
  challenge: string;
  counter: number;
  activityID: string | null;
  lastResult: SurfaceResult | null;
}
export function emptyState(appID: string): SurfaceState {
  return {schemaVersion: 1, appID, challenge: '', counter: 0, activityID: null, lastResult: null};
}
export function statusLine(state: SurfaceState): string {
  return 'App ID: ' + state.appID + ' | Challenge: ' + (state.challenge || 'not-prepared') +
    ' | Counter: ' + state.counter + ' | Request ID: ' + (state.lastResult?.requestID ?? 'none');
}
function freshID(): string {
  return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2) + '-' + Math.random().toString(36).slice(2);
}
function requestedSurface(request: JSONValue): string {
  if (request && !Array.isArray(request) && typeof request === 'object') {
    if (typeof request.surface === 'string') return request.surface;
    if (typeof request.source === 'string') return request.source;
  }
  return 'external';
}
/** Uses only the existing typed executeRuntime facade. No engine is implemented
 * here; every retained receipt is the actual returned Host RuntimeExecutionResult. */
export function createSurfaceProof(input: {
  appID: string;
  executeRuntime: Execute;
  readText(): Promise<string | null>;
  writeText(text: string): Promise<void>;
  /** A fresh headless window starts from the actual Shortcut input. The
   * observer independently binds that input to the challenge prepared in UI;
   * no other window's private state is read or written. */
  acceptInputChallenge?: boolean;
  samplePresentation?(): PresentationSample;
  reportProgress?(progress: {completedUnitCount: number; totalUnitCount: number; message: string}): Promise<void>;
}) {
  let tail: Promise<unknown> = Promise.resolve();
  let observer: ((state: SurfaceState) => void) | undefined;
  const serial = <T>(operation: () => Promise<T>): Promise<T> => {
    const next = tail.then(operation, operation);
    tail = next.then(() => undefined, () => undefined);
    return next;
  };
  const read = async (): Promise<SurfaceState> => {
    const raw = await input.readText();
    if (raw === null) return emptyState(input.appID);
    const state = JSON.parse(raw) as SurfaceState;
    if (state.schemaVersion !== 1 || state.appID !== input.appID ||
        typeof state.challenge !== 'string' || !Number.isSafeInteger(state.counter) ||
        state.counter < 0 || !(state.activityID === null || typeof state.activityID === 'string')) {
      throw new Error('The actual private surface state has an invalid identity or shape.');
    }
    return state;
  };
  const save = async (state: SurfaceState): Promise<void> => {
    await input.writeText(JSON.stringify(state));
    observer?.(state);
  };
  return {
    observe(next: (state: SurfaceState) => void): () => void {
      observer = next;
      return () => { if (observer === next) observer = undefined; };
    },
    read: () => serial(async () => { const state = await read(); observer?.(state); return state; }),
    prepare: () => serial(async () => {
      const old = await read();
      const state = {...emptyState(input.appID), challenge: freshID(), activityID: old.activityID};
      await save(state);
      return state;
    }),
    setActivityID: (activityID: string | null) => serial(async () => {
      const state = {...await read(), activityID};
      await save(state);
      return state;
    }),
    run: (request: JSONValue, invocation: {id?: string; caller: string}) => serial(async () => {
      const state = await read();
      const payload = request && !Array.isArray(request) && typeof request === 'object' ? request : undefined;
      const inputChallenge = payload?.challenge;
      if (!state.challenge && input.acceptInputChallenge && typeof inputChallenge === 'string' &&
          /^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+$/.test(inputChallenge)) {
        state.challenge = inputChallenge;
      }
      if (!state.challenge) throw new Error('Use Prepare challenge in this proof app before the system-surface attempt.');
      if (inputChallenge !== undefined && inputChallenge !== state.challenge) {
        throw new Error('The actual incoming challenge differs from this invocation state.');
      }
      const nonce = freshID();
      const result: SurfaceResult = {
        schemaVersion: 1, appID: input.appID, action: 'surface.run', challenge: state.challenge, nonce,
        requestID: invocation.id ?? nonce,
        requestIDOrigin: invocation.id ? 'host-invocation' : 'javascript-handler',
        caller: invocation.caller, request, requestedSurface: requestedSurface(request),
        counter: state.counter + 1, startedAt: new Date().toISOString(), status: 'running', receipts: []
      };
      if (input.samplePresentation) result.presentationSamples = [input.samplePresentation()];
      state.counter = result.counter;
      state.lastResult = result;
      await save(state);
      try {
        const kinds: RuntimeKind[] = ['node', 'typeScript', 'localPython', 'javaScriptCore', 'shell'];
        if (result.requestedSurface === 'miniAppShortcut' && input.reportProgress) {
          await input.reportProgress({completedUnitCount: 0, totalUnitCount: kinds.length,
            message: 'Starting ' + state.challenge});
        }
        for (const kind of kinds) {
          // IDs are fresh ASCII clock/random tokens, never payload-supplied code.
          const marker = input.appID + ':' + state.challenge + ':' + nonce + ':' + result.counter + ':' + kind + ':42';
          const quoted = JSON.stringify(marker);
          const source = kind === 'node' ? 'console.log(' + quoted + ')'
            : kind === 'typeScript' ? 'const marker: string = ' + quoted + '; console.log(marker)'
            : kind === 'localPython' ? 'print(' + quoted + ')'
            : kind === 'javaScriptCore' ? quoted
            : "printf '%s\\n' '" + marker + "'";
          const receipt = await input.executeRuntime(kind, source);
          result.receipts.push({kind, marker, receipt});
          if (input.samplePresentation) result.presentationSamples!.push(input.samplePresentation());
          await save(state);
          if (!receipt.executionID || !Number.isFinite(receipt.durationMilliseconds) ||
              receipt.didTimeOut || receipt.wasCancelled || receipt.outputWasTruncated ||
              (receipt.exitCode !== undefined && receipt.exitCode !== 0)) {
            throw new Error(kind + ' returned a failed or incomplete real execution receipt.');
          }
          if (kind === 'javaScriptCore' ? receipt.value !== marker
              : !receipt.stdout.split(/\r?\n/).includes(marker)) {
            throw new Error(kind + " did not return this invocation's actual challenge/nonce marker.");
          }
          if (result.requestedSurface === 'miniAppShortcut' && input.reportProgress) {
            await input.reportProgress({completedUnitCount: result.receipts.length,
              totalUnitCount: kinds.length, message: kind + ' ' + state.challenge});
          }
        }
        result.status = 'completed';
        result.finishedAt = new Date().toISOString();
        result.summary = 'Surface result ' + input.appID + ' ' + state.challenge + ' ' + nonce + ' ' + result.counter;
        await save(state);
        return result;
      } catch (error) {
        result.status = 'failed';
        result.error = String(error);
        result.finishedAt = new Date().toISOString();
        await save(state);
        throw error;
      }
    })
  };
}
