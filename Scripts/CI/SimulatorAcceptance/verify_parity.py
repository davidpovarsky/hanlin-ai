"""Count actual compiled Mini App UI cases; never emit a full-app gate result."""
import json
from pathlib import Path
import sys

from gate import nodes, test_identity

EXPECTED = {"ParityUITests/testActualPrivateStorageSurvivesProcessRelaunch", "ParityUITests/testReloadReplacesOnlyUnsavedDraft"}


def summarize(root):
    cases=[];errors=[]
    for family in ['iPhone','iPad']:
        for locale in ['en','he']:
            folder=root/f'{family}-{locale}';actual={}
            try:
                data=json.loads((folder/'tests.json').read_text())
                entries=[n for n in nodes(data) if n.get('nodeType')=='Test Case']
                assert len(entries)==2 and {test_identity(n) for n in entries}==EXPECTED,'Wrong actual case set'
                assert data.get('devices') and all(str(d.get('osVersion','')).startswith('27.') and str(d.get('modelName','')).startswith(family) for d in data['devices']),'Wrong actual OS/model family'
                context=json.loads((folder/'context.json').read_text());assert context['xcodebuild_exit_code']==0,'UI command failed'
                assert any((folder/'screenshots').rglob('*.png')),'No retained screenshots'
                assert (folder/'Tests.xcresult/Info.plist').is_file(),'Raw xcresult absent'
                actual={test_identity(n):n.get('result') for n in entries}
            except (OSError,ValueError,KeyError,AssertionError) as error:errors.append(f'{family}-{locale}: {error}')
            for identity in sorted(EXPECTED):
                status={'Passed':'EXECUTED_PASS','Failed':'FAILED','Skipped':'SKIPPED'}.get(actual.get(identity),'NOT_RUN')
                cases.append({'variant':f'{family}-{locale}','selector':identity,'status':status})
    counts={s:sum(c['status']==s for c in cases) for s in ['EXECUTED_PASS','REUSED_VERIFIED_PASS','FAILED','SKIPPED','NOT_RUN','BLOCKED']}
    return {'scope':'compiled-swift-parity-miniapp-ui-only','full_app_acceptance':False,'status':'PASS' if not errors and counts['EXECUTED_PASS']==8 else 'BLOCKED','counts':counts,'cases':cases,'errors':errors}


if __name__=='__main__':
    result=summarize(Path(sys.argv[1]));print(json.dumps(result,indent=2));sys.exit(0 if result['status']=='PASS' else 1)
