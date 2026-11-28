// Original ScriptWidget JSX and $dynamic_island contracts. Full marker text is
// authored for identity; actual visibility/truncation/AX remain native evidence.
const runUUID = String($storage.get('runUUID') ?? 'missing-run');
const slot = String($storage.get('slot') ?? 'missing-slot');
const submittedRevision = String($storage.get('submittedRevision') ?? 'missing-revision');
function Region({code}) {
  return <text font="caption">{'LA|' + runUUID + '|' + slot + '|' + code + '|R' + submittedRevision}</text>;
}
$render(<Region code="banner"/>);
$dynamic_island({
  compactLeading: <Region code="compact-leading"/>,
  compactTrailing: <Region code="compact-trailing"/>,
  minimal: <Region code="minimal"/>,
  expanded: {
    leading: <Region code="expanded-leading"/>,
    trailing: <Region code="expanded-trailing"/>,
    center: <Region code="expanded-center"/>,
    bottom: <Region code="expanded-bottom"/>
  }
});
