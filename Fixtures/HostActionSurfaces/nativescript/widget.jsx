// Original ScriptWidget JSX runtime. The foreground intent dispatches this
// declared Host action; no foreground VM is started inside the extension.
const liveActivity = $getenv('liveActivity') === true;
const parameters = {surface: liveActivity ? 'liveActivity' : 'widget', fixture: 'hanlin.surface.nativescript'};
function RunButton() {
  return <button actionID="surface-host-run" actionParameters={parameters}>
    <text>Run NativeScript Surface</text>
  </button>;
}
$render(<vstack spacing="8">
  <text font="headline">Surface NativeScript</text>
  <text font="caption">{'Challenge: ' + ($storage.get('challenge') ?? 'Prepared in app')}</text>
  <RunButton/>
</vstack>);
$dynamic_island({
  expanded: {
    leading: <text>NativeScript</text>,
    trailing: <text>5 runtimes</text>,
    center: <text>{String($storage.get('challenge') ?? '')}</text>,
    bottom: <RunButton/>
  },
  compactLeading: <text>NS</text>,
  compactTrailing: <text>5</text>,
  minimal: <text>5</text>
});
