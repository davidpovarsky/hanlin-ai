import { createHostServices, type NativeSurfaceNode } from '../../host-services';

const root: NativeSurfaceNode = {
  kind: 'liveActivityUI',
  children: [
    {kind: 'liveActivityContent', children: [{kind: 'text', properties: {text: 'שלום🙂'}}]},
    {kind: 'liveActivityCompactLeading', children: [{kind: 'text', properties: {text: '3'}}]},
    {kind: 'liveActivityCompactTrailing', children: [{kind: 'text', properties: {text: 'tasks'}}]},
    {kind: 'liveActivityMinimal', children: [{kind: 'text', properties: {text: '3'}}]},
  ],
};
const host = createHostServices();
void host.liveActivities.start({root, state: {done: 2}, actionEntrypointID: 'appIntents'});
void host.liveActivities.update('native-id', {state: {done: 3}});
void host.liveActivities.end('native-id', {dismissAfterSeconds: 0});
// @ts-expect-error A native layout is required when starting.
void host.liveActivities.start({title: 'Missing layout'});
// @ts-expect-error A JavaScript callback is not a serializable native action.
void host.liveActivities.start({root: {kind: 'button', properties: {intent: () => {}}}});
// @ts-expect-error System timestamps are numeric milliseconds.
void host.liveActivities.update('native-id', {staleDateEpochMilliseconds: 'tomorrow'});
