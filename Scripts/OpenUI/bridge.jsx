import React from 'react';
import { createRoot } from 'react-dom/client';
import { Renderer } from '@openuidev/react-lang';
import { ThemeProvider } from '@openuidev/react-ui';
import { libraries } from './catalogs.jsx';
import { NativeRuntime } from './native-runtime.mjs';
import '@openuidev/react-ui/index.css';
import './bridge.css';

const post = body => window.webkit.messageHandlers.hanlinOpenUI.postMessage(body);
const report = message => post({ kind: 'error', message: String(message) }).catch(() => {});
let mounted, native, libraryKey;
let previousState = {};
let current;
const toolProvider = { callTool: (name, args) => post({ kind: 'tool', name, args }) };
function stateChanged(state, previous = previousState) {
  const before = previous; previousState = state;
  if (JSON.stringify(before) !== JSON.stringify(state)) post({ kind: 'state', state, previous: before }).catch(report);
}
function action(event) { return post({ kind: 'action', event }); }

window.hanlinOpenUI = {
  update(input) {
    current = input;
    const key = input.catalogID ?? 'openui.original@1';
    const library = libraries[key];
    if (!library) { report(`Catalog unavailable: ${key}`); return; }
    previousState = input.state ?? {};
    if (input.target === 'swiftui') {
      if (!native || libraryKey !== key) {
        native?.dispose();
        native = new NativeRuntime({ library, toolProvider,
          onTree: tree => post({ kind: 'tree', tree }).catch(report),
          onState: stateChanged, onAction: action, onError: report });
      }
      libraryKey = key;
      native.update(input.program, input.complete, input.state);
    } else {
      mounted ??= createRoot(document.getElementById('root'));
      mounted.render(<ThemeProvider><Renderer library={library} response={input.program} isStreaming={!input.complete}
        initialState={input.state} onStateUpdate={stateChanged} onAction={action}
        toolProvider={toolProvider} publishObservability={false} /></ThemeProvider>);
    }
  },
  field(id, value) { native?.setField(id, value); },
  action(id) { native?.act(id).catch(report); },
  dispose() { native?.dispose(); mounted?.unmount(); },
};
new ResizeObserver(() => {
  if (current?.target !== 'swiftui') post({ kind: 'height', height: Math.ceil(document.getElementById('root').getBoundingClientRect().height) }).catch(report);
}).observe(document.getElementById('root'));
post({ kind: 'ready' }).catch(report);
