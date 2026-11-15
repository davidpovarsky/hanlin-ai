"""Report actual exact-source Apple SDK cases; no host/UI/native-model acceptance."""
import json
from pathlib import Path
import sys

from xcresult_to_xunit import nodes

EXPECTED = {
    'ProducerTests': {
        'RawToolInputPropagationTests': set(),
        'ToResponseMessagesTests': set(),
        'ExecuteToolCallProviderMetadataTests': set(),
        'ModelMessageCodableTests': set(),
    },
    'SDKTests': {
        'AgentSessionTests': {'nativeSnapshotsEmitOnlyNewSuffixAndRejectRevision','existingEngineRunsHostToolOnceAndPersistsCorrelation'},
        'ContextTests': {'decodedNamespacesCannotBypassValidation','persistedPresentationCarriesNoExecutionAuthority'},
        'StoreTests': {'sameConversationIDIsIsolatedBySpace'},
    },
    'CoreTests': {
        'HanlinInjectedProviderTests': {'nativeNonTextRejectedBeforeProviderCapabilityOrDownloadPath','nativeDescriptorNeverSelectsNetworkProvider','duplicateDefinitionsThrowBeforeDictionaryConstruction'},
        'HanlinAISDKProviderFactoryTests': set(),
        'HanlinAISDKAgentEngineTests': set(),
    },
}


def summarize(root):
    statuses=json.loads((root/'process-status.json').read_text());cases=[];errors=[]
    planned=json.loads((root/'expected-tests.json').read_text()) if (root/'expected-tests.json').exists() else {}
    for name,suites in EXPECTED.items():
        try:
            data=json.loads((root/f'{name}.json').read_text());actual=[n for n in nodes(data) if n.get('nodeType')=='Test Case']
        except (OSError,ValueError):actual=[]
        identities=[n.get('nodeIdentifier','') for n in actual]
        if len(set(identities))!=len(identities):errors.append(name+': duplicate actual identities')
        for suite,methods in suites.items():
            methods=set(planned.get(suite,methods))
            found=[n for n in actual if n.get('nodeIdentifier','').startswith(suite+'/')]
            if not found:errors.append(name+': no actual cases for '+suite)
            for method in methods:
                if not any(n.get('nodeIdentifier','').split('/')[-1].split('(')[0]==method for n in found):
                    errors.append(name+': missing '+suite+'/'+method)
                    cases.append({'id':suite+'/'+method,'status':'NOT_RUN','kind':'unexecuted_method_obligation'})
        for n in actual:cases.append({'id':n.get('nodeIdentifier'),'status':{'Passed':'EXECUTED_PASS','Failed':'FAILED','Skipped':'SKIPPED'}.get(n.get('result'),'NOT_RUN')})
    counts={s:sum(c['status']==s for c in cases) for s in ['EXECUTED_PASS','REUSED_VERIFIED_PASS','FAILED','SKIPPED','NOT_RUN','BLOCKED']}
    passed=bool(cases) and not errors and all(v==0 for v in statuses.values()) and counts['EXECUTED_PASS']==len(cases)
    return {'scope':'exact-source-Apple-producer-core-session-fixture-host-regression','status':'PASS' if passed else 'BLOCKED','counts':counts,'cases':cases,'process_status':statuses,'errors':errors,'ios_compile':'PASS' if statuses['ios_build_exit']==0 else 'NOT_RUN' if statuses['ios_build_exit'] is None else 'FAILED','not_asserted':['real FoundationModels generation/availability','native tools','real host/API/navigation','AI app migration/UI','physical iPad','release/TestFlight']}


if __name__=='__main__':
    result=summarize(Path(sys.argv[1]));print(json.dumps(result,indent=2));sys.exit(0 if result['status']=='PASS' else 1)
