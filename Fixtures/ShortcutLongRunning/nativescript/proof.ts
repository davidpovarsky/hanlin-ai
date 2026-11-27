import type {createHostServices} from '@hanlin/host-services';
type Execute = ReturnType<typeof createHostServices>['executeRuntime'];

type Receipt = Awaited<ReturnType<Execute>>;
type RuntimeKind = Parameters<Execute>[0];
export type JSONValue = null | boolean | number | string | JSONValue[] | {[key: string]: JSONValue};

export interface PreparedState {
  schemaVersion: 1;
  appID: string;
  challenge: string;
  counter: 0;
  lastResult: null;
}
export interface PresentationSample {
  windowID: string;
  statePath: string;
  executionMode: string;
  attached: boolean;
}
export interface LongRunningResult {
  schemaVersion: 1;
  appID: string;
  action: 'surface.run';
  challenge: string;
  nonce: string;
  requestID: string;
  requestIDOrigin: 'host-invocation' | 'javascript-handler';
  caller: string;
  request: JSONValue;
  requestedSurface: 'miniAppShortcutLongRunning';
  counter: 1;
  startedAt: string;
  finishedAt?: string;
  status: 'running' | 'completed' | 'failed';
  receipts: Array<{ordinal: number; kind: RuntimeKind; marker: string; receipt: Receipt}>;
  presentationSamples: PresentationSample[];
  error?: string;
  longRunning: {
    schema: 1;
    token: string;
    profile: 'paced-35-v1';
    journalFile: string;
    phase: 'entered' | 'executing' | 'pacing' | 'completed' | 'failed';
    completedUnitCount: number;
    totalUnitCount: 35;
    reportCount: number;
    reportedProgressAt?: string;
    progressMessage?: string;
    completedPacingTicks: number;
  };
}

export function emptyState(appID: string): PreparedState {
  return {schemaVersion: 1, appID, challenge: '', counter: 0, lastResult: null};
}
export function statusLine(state: PreparedState): string {
  return 'App ID: ' + state.appID + ' | Challenge: ' + (state.challenge || 'not-prepared') + ' | Counter: 0';
}
function freshID(): string {
  return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2) + '-' + Math.random().toString(36).slice(2);
}

/** Authored acceptance workload only. The original facade executes every unit.
 * This fixed profile has 35 real calls and 34 ten-second pacing intervals.
 * Pacing is not CPU/network work and never advances completed-unit progress.
 * There is no input-controlled duration, scale, source program, or runtime API.
 */
export function createLongRunningProof(input: {
  appID: string;
  executeRuntime: Execute;
  readText(): Promise<string | null>;
  writeText(text: string): Promise<void>;
  writeInvocation(filename: string, text: string): Promise<void>;
  reportProgress(progress: {completedUnitCount: number; totalUnitCount: number; message: string}): Promise<void>;
  samplePresentation?(filename: string): PresentationSample;
  invocationStarted?(identity: {token: string; nonce: string; journalFile: string}): void;
}) {
  const read = async (): Promise<PreparedState> => {
    const raw = await input.readText();
    if (raw === null) return emptyState(input.appID);
    const value = JSON.parse(raw) as PreparedState;
    if (value.schemaVersion !== 1 || value.appID !== input.appID ||
        typeof value.challenge !== 'string' || value.counter !== 0 || value.lastResult !== null) {
      throw new Error('The actual prepared private state has an invalid identity.');
    }
    return value;
  };
  return {
    read,
    prepare: async (): Promise<PreparedState> => {
      const state = {...emptyState(input.appID), challenge: freshID()};
      await input.writeText(JSON.stringify(state));
      return state;
    },
    run: async (request: JSONValue, invocation: {id?: string; caller: string}): Promise<LongRunningResult> => {
      if (!request || Array.isArray(request) || typeof request !== 'object' ||
          request.surface !== 'miniAppShortcutLongRunning' ||
          typeof request.challenge !== 'string' || !/^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+$/.test(request.challenge)) {
        throw new Error('The saved Shortcut must supply its actual prepared challenge.');
      }
      const options = request.longRunning;
      if (!options || Array.isArray(options) || typeof options !== 'object' ||
          Object.keys(options).sort().join(',') !== 'profile,schema,token' || options.schema !== 1 ||
          options.profile !== 'paced-35-v1' || typeof options.token !== 'string' ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(options.token)) {
        throw new Error('Only the fixed finite long-running acceptance profile is supported.');
      }
      const nonce = freshID();
      const journalFile = 'surface-invocation-' + options.token + '-' + nonce + '.json';
      const result: LongRunningResult = {
        schemaVersion: 1, appID: input.appID, action: 'surface.run', challenge: request.challenge,
        nonce, requestID: invocation.id ?? nonce,
        requestIDOrigin: invocation.id ? 'host-invocation' : 'javascript-handler',
        caller: invocation.caller, request, requestedSurface: 'miniAppShortcutLongRunning',
        counter: 1, startedAt: new Date().toISOString(), status: 'running', receipts: [],
        presentationSamples: [],
        longRunning: {schema: 1, token: options.token, profile: 'paced-35-v1', journalFile,
          phase: 'entered', completedUnitCount: 0, totalUnitCount: 35, reportCount: 0, completedPacingTicks: 0}
      };
      const note = result.longRunning;
      input.invocationStarted?.({token: note.token, nonce, journalFile});
      const save = async () => { await input.writeInvocation(journalFile, JSON.stringify(result)); };
      const sample = () => {
        if (input.samplePresentation) result.presentationSamples.push(input.samplePresentation(journalFile));
      };
      const report = async () => {
        const message = 'LR ' + note.token + ' ' + note.completedUnitCount + '/35 receipts';
        await input.reportProgress({completedUnitCount: note.completedUnitCount, totalUnitCount: 35, message});
        // Retain only an acknowledgement after the real native progress call.
        note.reportCount += 1;
        note.reportedProgressAt = new Date().toISOString();
        note.progressMessage = message;
        await save();
      };
      sample();
      await save();
      try {
        await report();
        const kinds: RuntimeKind[] = ['node', 'typeScript', 'localPython', 'javaScriptCore', 'shell'];
        for (let ordinal = 1; ordinal <= 35; ordinal += 1) {
          note.phase = 'executing';
          await save();
          const kind = kinds[(ordinal - 1) % kinds.length]!;
          const marker = input.appID + ':' + result.challenge + ':' + nonce + ':' + ordinal + ':' + kind + ':42';
          const quoted = JSON.stringify(marker);
          const source = kind === 'node' ? 'console.log(' + quoted + ')'
            : kind === 'typeScript' ? 'const marker: string = ' + quoted + '; console.log(marker)'
            : kind === 'localPython' ? 'print(' + quoted + ')'
            : kind === 'javaScriptCore' ? quoted
            : "printf '%s\\n' '" + marker + "'";
          const receipt = await input.executeRuntime(kind, source);
          result.receipts.push({ordinal, kind, marker, receipt});
          sample();
          await save();
          if (!receipt.executionID || !Number.isFinite(receipt.durationMilliseconds) ||
              receipt.durationMilliseconds < 0 || receipt.didTimeOut || receipt.wasCancelled || receipt.outputWasTruncated ||
              (receipt.exitCode !== undefined && receipt.exitCode !== 0) ||
              (kind === 'javaScriptCore' ? receipt.value !== marker
                : !receipt.stdout.split(/\r?\n/).includes(marker))) {
            throw new Error('Runtime unit ' + ordinal + ' did not return its exact real result.');
          }
          note.completedUnitCount = ordinal;
          await report();
          if (ordinal < 35) {
            note.phase = 'pacing';
            await save();
            for (let tick = 0; tick < 10; tick += 1) {
              await new Promise<void>(resolve => setTimeout(resolve, 1000));
              note.completedPacingTicks += 1;
              await report();
            }
          }
        }
        result.status = 'completed';
        result.finishedAt = new Date().toISOString();
        note.phase = 'completed';
        await save();
        return result;
      } catch (error) {
        result.status = 'failed'; result.error = String(error);
        result.finishedAt = new Date().toISOString(); note.phase = 'failed';
        // A disposed provider may reject this write. Only the actual native
        // cancelled receipt can qualify cancellation; this is not a receipt.
        await save();
        throw error;
      }
    }
  };
}
