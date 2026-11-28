import React from 'react';
import { createRoot } from 'react-dom/client';
import { Renderer } from '@openuidev/react-lang';
import { ThemeProvider } from '@openuidev/react-ui';
import { libraries } from './catalogs.jsx';
import { NativeRuntime } from './native-runtime.mjs';
import { encodeState, decodeState } from './state-wire.mjs';
import { createHostToolProviders } from './tool-wire.mjs';
import '@openuidev/react-ui/index.css';
import './bridge.css';

const post = body => window.webkit.messageHandlers.hanlinOpenUI.postMessage(body);
const report = message => post({ kind: 'error', message: String(message) }).catch(() => {});
let mounted, native, libraryKey;
let previousState = {};
let current;
// UI arguments remain normalized JSON; the original Host provenance checks apply.
const plainJSON = value => JSON.parse(JSON.stringify(value));
const { nativeToolProvider, reactToolProvider } = createHostToolProviders(post);
function stateChanged(state, previous = previousState) {
  const before = encodeState(previous); previousState = state;
  const encoded = encodeState(state);
  if (JSON.stringify(before) !== JSON.stringify(encoded)) post({ kind: 'state', state: encoded, previous: before }).catch(report);
}
function action(event) { return post({ kind: 'action', event: plainJSON(event) }); }

window.hanlinOpenUI = {
  update(input) {
    current = input;
    const key = input.catalogID ?? 'openui.original@1';
    const library = libraries[key];
    if (!library) { report(`Catalog unavailable: ${key}`); return; }
    const restoredState = decodeState(input.state ?? {});
    previousState = restoredState;
    if (input.target === 'swiftui') {
      if (!native || libraryKey !== key) {
        native?.dispose();
        native = new NativeRuntime({ library, toolProvider: nativeToolProvider,
          onTree: tree => post({ kind: 'tree', tree: encodeState(tree) }).catch(report),
          onState: stateChanged, onAction: action, onError: report });
      }
      libraryKey = key;
      native.update(input.program, input.complete, restoredState);
    } else {
      mounted ??= createRoot(document.getElementById('root'));
      mounted.render(<ThemeProvider><Renderer library={library} response={input.program} isStreaming={!input.complete}
        initialState={restoredState} onStateUpdate={stateChanged} onAction={action}
        toolProvider={reactToolProvider} publishObservability={false} /></ThemeProvider>);
    }
  },
  field(id, value) { native?.setField(id, decodeState(value)); },
  action(id) { native?.act(id).catch(report); },
  dispose() { native?.dispose(); mounted?.unmount(); },
};
new ResizeObserver(() => {
  if (current?.target !== 'swiftui') post({ kind: 'height', height: Math.ceil(document.getElementById('root').getBoundingClientRect().height) }).catch(report);
}).observe(document.getElementById('root'));
post({ kind: 'ready' }).catch(report);
