"""Count actual compiled Mini App UI cases; never emit a full-app gate result."""
import json
import os
from pathlib import Path
import sys

from gate import nodes, test_identity

EXPECTED = {"ParityUITests/testActualPrivateStorageSurvivesProcessRelaunch", "ParityUITests/testReloadReplacesOnlyUnsavedDraft"}


def summarize(root, variant=None):
    if variant not in [None,'iPad-he']:raise ValueError('Unsupported continuation cohort')
    cases=[];errors=[]
    for family in ['iPhone','iPad']:
        for locale in ['en','he']:
            if variant and f'{family}-{locale}'!=variant:continue
            folder=root/f'{family}-{locale}';actual={};provenance_ok=False
            try:
                data=json.loads((folder/'tests.json').read_text())
                entries=[n for n in nodes(data) if n.get('nodeType')=='Test Case']
                actual={test_identity(n):n.get('result') for n in entries}
                assert len(entries)==2 and {test_identity(n) for n in entries}==EXPECTED,'Wrong actual case set'
                assert data.get('devices') and all(str(d.get('osVersion','')).startswith('27.') and str(d.get('modelName','')).startswith(family) for d in data['devices']),'Wrong actual OS/model family'
                context=json.loads((folder/'context.json').read_text())
                assert context['family']==family and context['locale']==locale,'Wrong matrix context'
                if context['xcodebuild_exit_code']!=0:errors.append(f'{family}-{locale}: UI command exited {context["xcodebuild_exit_code"]}')
                assert any((folder/'screenshots').rglob('*.png')),'No retained screenshots'
                assert (folder/'Tests.xcresult/Info.plist').is_file(),'Raw xcresult absent'
                provenance_ok=True
            except (OSError,ValueError,KeyError,AssertionError) as error:
                errors.append(f'{family}-{locale}: {error}')
                if not actual and (folder/'case-end-lines.jsonl').exists():
                    for line in (folder/'case-end-lines.jsonl').read_text().splitlines():
                        record=json.loads(line)
                        if record.get('selector') in EXPECTED:
                            actual[record['selector']]={'passed':'Passed','failed':'Failed','skipped':'Skipped'}.get(record.get('result'))
            for identity in sorted(EXPECTED):
                status={'Passed':'EXECUTED_PASS','Failed':'FAILED','Skipped':'SKIPPED'}.get(actual.get(identity),'NOT_RUN')
                if status=='EXECUTED_PASS' and not provenance_ok:status='BLOCKED'
                cases.append({'variant':f'{family}-{locale}','selector':identity,'status':status})
    counts={s:sum(c['status']==s for c in cases) for s in ['EXECUTED_PASS','REUSED_VERIFIED_PASS','FAILED','SKIPPED','NOT_RUN','BLOCKED']}
    expected=2 if variant else 8
    return {'scope':'compiled-swift-parity-miniapp-ui-only','selected_variant':variant or 'all-four','expected_cases':expected,'full_app_acceptance':False,'status':'PASS' if not errors and counts['EXECUTED_PASS']==expected else 'BLOCKED','counts':counts,'cases':cases,'errors':errors}


if __name__=='__main__':
    result=summarize(Path(sys.argv[1]),os.environ.get('HANLIN_PARITY_VARIANT') or None);print(json.dumps(result,indent=2));sys.exit(0 if result['status']=='PASS' else 1)
