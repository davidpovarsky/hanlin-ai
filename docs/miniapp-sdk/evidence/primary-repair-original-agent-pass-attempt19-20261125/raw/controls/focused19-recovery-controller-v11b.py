"""Only the remaining original repair UI after the shared importer lifecycle correction.
Rebuild both affected MiniApps and AI products from the current published source.
Preserve original SDK/probe outputs, all nine focused charges and each distinct grant.
Prior ManualInput proof remains historical; fresh original25+27 is never claimed here.
"""
from pathlib import Path
import argparse, datetime, fcntl, hashlib, importlib.util, json, math, os, shlex, signal, subprocess, sys, time, uuid

ID = "focused19-v11"
SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
PRIOR_CONSUMER_SOURCE = "4cde88df07a2f3cd86cc99ad87786c79ae207390"
V9_CONSUMER_SOURCE = "dc53a6c8ff1bb68bfbc52a64667e14ce688055b0"
V8_CONSUMER_SOURCE = "7bf0c2fdc2f7168d6b98dda66f443ae032fe1c11"
PREVIOUS_CONSUMER_SOURCE = "f6bb035f2828ec24a683bb2f5f1dddb27143dc4a"
PREVIOUS_REPAIR_SOURCE = "958cf666da7be83b9b63e46e3013e3344fb31585"
PRIOR_SOURCE = "6c006c948f0a6f371f7fc68b90e393f43734f8dd"
PREVIOUS_SOURCE = "62dfff9aebd0a272486c7770d4f77ba603d535ab"
TREE = "f7a6596a1ef53d8d962ceb9f619460ffa19ee91e"
PRODUCER_SOURCE = "a2c8a1b1be746461272ba77254603304567c309d"
PREFIX_SHA = "846d7b35087174f0c6d5032dc0615d04f5f50eaedc7e48447438d187da90b954"
PREFIX_BASELINE = 15472.911772584037
PRIOR_V1_CHARGE = 366.7222996670025
PRIOR_V2_CHARGE = 977.134837125006
PRIOR_ENV_CHARGE = 39.67624695900304
PRIOR_NATIVE_CHARGE = PRIOR_V1_CHARGE + PRIOR_V2_CHARGE
PRIOR_ENV_TOTAL = PRIOR_NATIVE_CHARGE + PRIOR_ENV_CHARGE
PRIOR_V5_CHARGE = 713.0760274589993
PRIOR_V6_CHARGE = 544.1797895409982
PRIOR_V5_TOTAL = math.fsum([PRIOR_V1_CHARGE, PRIOR_V2_CHARGE, PRIOR_ENV_CHARGE, PRIOR_V5_CHARGE])
PRIOR_V6_TOTAL = math.fsum([PRIOR_V1_CHARGE, PRIOR_V2_CHARGE, PRIOR_ENV_CHARGE, PRIOR_V5_CHARGE, PRIOR_V6_CHARGE])
PRIOR_V7_CHARGE = 443.2465754169971
PRIOR_V7_TOTAL = math.fsum([PRIOR_V1_CHARGE, PRIOR_V2_CHARGE, PRIOR_ENV_CHARGE, PRIOR_V5_CHARGE, PRIOR_V6_CHARGE, PRIOR_V7_CHARGE])
PRIOR_V8_CHARGE = 735.968727458996
PRIOR_V8_TOTAL = math.fsum([PRIOR_V1_CHARGE, PRIOR_V2_CHARGE, PRIOR_ENV_CHARGE, PRIOR_V5_CHARGE, PRIOR_V6_CHARGE, PRIOR_V7_CHARGE, PRIOR_V8_CHARGE])
PRIOR_V9_CHARGE = 493.8438168749999
PRIOR_V9_TOTAL = math.fsum([PRIOR_V1_CHARGE, PRIOR_V2_CHARGE, PRIOR_ENV_CHARGE, PRIOR_V5_CHARGE, PRIOR_V6_CHARGE, PRIOR_V7_CHARGE, PRIOR_V8_CHARGE, PRIOR_V9_CHARGE])
PRIOR_V10_CHARGE = 497.25722187499923
PRIOR_CHARGE = math.fsum([PRIOR_V1_CHARGE, PRIOR_V2_CHARGE, PRIOR_ENV_CHARGE, PRIOR_V5_CHARGE, PRIOR_V6_CHARGE, PRIOR_V7_CHARGE, PRIOR_V8_CHARGE, PRIOR_V9_CHARGE, PRIOR_V10_CHARGE])
NATIVE_BASELINE = 16816.768909376045
ENV_BASELINE = 16856.44515633505
V5_BASELINE = 17569.521183794048
V6_BASELINE = 18113.700973335046
V7_BASELINE = 18556.947548752043
V8_BASELINE = 19292.91627621104
V9_BASELINE = 19786.76009308604
ACTIVE_BASELINE = 20284.01731496104
ORIGINAL_ALLOWANCE = 3600
PRIOR_ADDITIONAL_ALLOWANCE = 400
PRIOR_TOTAL_ALLOWANCE = ORIGINAL_ALLOWANCE + PRIOR_ADDITIONAL_ALLOWANCE
PRIOR_CONTINUATION_GRANT = {"by": "/root", "additionalSeconds": 400, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600 and all six actual charges; add400 for the measured receiver-synchronization continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}
PRIOR_V8_CONTINUATION_GRANTS = [{"authority": {"path": "build/primary-control/focused19-v8/decision.json", "sha256": "7c16a01c08f9ebfe7ac34844afcf1008e8be97975449c7424c3640bbeeab640f"}, "grant": {"by": "/root", "additionalSeconds": 400, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600 and all six actual charges; add400 for the measured receiver-synchronization continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}]
V9_CONTINUATION_GRANT = {"by": "/root", "additionalSeconds": 750, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, prior explicit400 grant and all seven actual charges; add750 for the measured MiniApps receiver-presentation continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedMiniBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}
V9_SUPPLEMENTAL_CONTINUATION_GRANT = {"by": "/root", "additionalSeconds": 200, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, prior400, separate750 and all seven actual charges; add200 after the actual V8 transcript established pending receiver status before installation, requiring the provider correction and both original builds.", "plannedNextPhaseSeconds": 1080, "components": {"affectedMiniBuild": 180, "affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}
PRIOR_V9_TOTAL_ALLOWANCE = PRIOR_TOTAL_ALLOWANCE + V9_CONTINUATION_GRANT["additionalSeconds"] + V9_SUPPLEMENTAL_CONTINUATION_GRANT["additionalSeconds"]
PRIOR_CONTINUATION_GRANTS = [{"authority": {"path": "build/primary-control/focused19-v8/decision.json", "sha256": "7c16a01c08f9ebfe7ac34844afcf1008e8be97975449c7424c3640bbeeab640f"}, "grant": {"by": "/root", "additionalSeconds": 400, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600 and all six actual charges; add400 for the measured receiver-synchronization continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}, {"authority": {"path": "build/primary-control/focused19-v9/decision.json", "sha256": "dd38954a1f5db85b02c65c02566053e7c2dea660500ccb08c8220f34d5e7c6f9"}, "grant": {"by": "/root", "additionalSeconds": 750, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, prior explicit400 grant and all seven actual charges; add750 for the measured MiniApps receiver-presentation continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedMiniBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}, {"authority": {"path": "build/primary-control/focused19-v9/decision.json", "sha256": "dd38954a1f5db85b02c65c02566053e7c2dea660500ccb08c8220f34d5e7c6f9"}, "grant": {"by": "/root", "additionalSeconds": 200, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, prior400, separate750 and all seven actual charges; add200 after the actual V8 transcript established pending receiver status before installation, requiring the provider correction and both original builds.", "plannedNextPhaseSeconds": 1080, "components": {"affectedMiniBuild": 180, "affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}, {"authority": {"path": "build/primary-control/focused19-v10/decision.json", "sha256": "e5c4f55ab15c4b8360380bf2523847d073a1c47622fb06fce8b0c7bf83a7a01e"}, "grant": {"by": "/root", "additionalSeconds": 300, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, separate prior400/750/200 grants and all eight actual charges; add300 for the measured AI-only repair-coordinator continuation while authenticating unchanged dc53 MiniApps products.", "plannedNextPhaseSeconds": 900, "components": {"affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}]
PRIOR_V10_CONTINUATION_GRANTS = [{"authority": {"path": "build/primary-control/focused19-v8/decision.json", "sha256": "7c16a01c08f9ebfe7ac34844afcf1008e8be97975449c7424c3640bbeeab640f"}, "grant": {"by": "/root", "additionalSeconds": 400, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600 and all six actual charges; add400 for the measured receiver-synchronization continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}, {"authority": {"path": "build/primary-control/focused19-v9/decision.json", "sha256": "dd38954a1f5db85b02c65c02566053e7c2dea660500ccb08c8220f34d5e7c6f9"}, "grant": {"by": "/root", "additionalSeconds": 750, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, prior explicit400 grant and all seven actual charges; add750 for the measured MiniApps receiver-presentation continuation.", "plannedNextPhaseSeconds": 900, "components": {"affectedMiniBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}, {"authority": {"path": "build/primary-control/focused19-v9/decision.json", "sha256": "dd38954a1f5db85b02c65c02566053e7c2dea660500ccb08c8220f34d5e7c6f9"}, "grant": {"by": "/root", "additionalSeconds": 200, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, prior400, separate750 and all seven actual charges; add200 after the actual V8 transcript established pending receiver status before installation, requiring the provider correction and both original builds.", "plannedNextPhaseSeconds": 1080, "components": {"affectedMiniBuild": 180, "affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}}]
V10_CONTINUATION_GRANT = {"by": "/root", "additionalSeconds": 300, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, separate prior400/750/200 grants and all eight actual charges; add300 for the measured AI-only repair-coordinator continuation while authenticating unchanged dc53 MiniApps products.", "plannedNextPhaseSeconds": 900, "components": {"affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}
PRIOR_V10_TOTAL_ALLOWANCE = PRIOR_V9_TOTAL_ALLOWANCE + V10_CONTINUATION_GRANT["additionalSeconds"]
ADDITIONAL_ALLOWANCE = 650
TOTAL_ALLOWANCE = PRIOR_V10_TOTAL_ALLOWANCE + ADDITIONAL_ALLOWANCE
REMAINING_ALLOWANCE = TOTAL_ALLOWANCE - PRIOR_CHARGE
CONTINUATION_GRANT = {"by": "/root", "additionalSeconds": 650, "basis": "The user explicitly authorized completing the remaining implementation without repeated permission. Preserve the original3600, separate prior400/750/200/300 grants and all nine actual charges; add650 for the measured shared importer lifecycle correction requiring both original MiniApps and AI builds.", "plannedNextPhaseSeconds": 1080, "components": {"affectedMiniBuild": 180, "affectedAIBuild": 180, "originalCase": 600, "setupResultCleanup": 120}, "otherGrantsUnchanged": True}
CHANGED_SOURCES = ["AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests.swift",
                   "AI_HLY/Downstream/AgentDiagnostics/AgentRuntimeUIAcceptanceProvider.swift",
                   "Fixtures/ExpoSwiftUIProbe/ManualAdapterProbe.tsx",
                   "AI_HLY/Downstream/ChatCore/HanlinAppHostIntegration.swift",
                   "AI_HLYUITests/MiniAppAuthoringUITests.swift",
                   "HanlinMiniAppsApp/HanlinMiniAppsApp.swift",
                   "AI_HLY/Downstream/SDK/MiniAppRepairCoordinator.swift",
                   "AI_HLY/Downstream/ScriptingPlatform/ScriptingPackageCenterViews.swift"]
PROBE_FIXTURES = [folder + "/" + name + ".hanlinExpo"
                    for folder in ["Fixtures/ExpoSwiftUIProbe", "AI_HLYUITests/Fixtures"]
                    for name in ["ExpoSwiftUIProbe", "ExpoSwiftUIProbeA", "ExpoSwiftUIProbeB"]]
RECOVERY_INPUTS = "build/primary-control/focused19-v11-recovery-inputs.json"
RECOVERY_INPUTS_SHA = "eaccf3795eb755f1bfad0a89794a7ee59dbb4d8b0673d69e690b4bf5fbfa2524"
PRIOR_RECORDS = [{"path": "build/primary-control/focused19-v1/state.json", "sha256": "a7ae2d21b27503b71939ff72670333a7e05736e47e999801f52e6ee6c1520dd6"}, {"path": "build/primary-control/focused19-v1/ledger.json", "sha256": "c7835bb97d3017d305628e76ce25b35cfb415433780c4a43f806d0d56fbf708f"}, {"path": "build/primary-control/focused19-v1/decision.json", "sha256": "77eef76303d4df1ac274a6cbf3db71b8f7efc4ee7f4e9b623334d565dd3297a3"}, {"path": "build/primary-control/focused19-v1/native-result/state.json", "sha256": "f8f7fd1284b984d77237a2e487961eab0782ba079fadfe43f3805d68148fc24e"}, {"path": "build/primary-control/focused19-v2/state.json", "sha256": "9e199031a41095f66c101962da3c1c4ad330e748a9ac2afc267aac71384c2a21"}, {"path": "build/primary-control/focused19-v2/ledger.json", "sha256": "ec1d8b41595201d0a64b86d714a0fbd049cfbc9339b8a494fff25875cf6d6898"}, {"path": "build/primary-control/focused19-v2/decision.json", "sha256": "72608e39bc0987c619ea24b0eeea53b18cd5cca6f86c4a3dab688699580a315c"}, {"path": "build/primary-control/focused19-v2/native-result/state.json", "sha256": "5a0005645e789fc4979ff7515faf2c7ed28a589ff1f5aacdaa35cfdb388a3339"}, {"path": "build/primary-control/focused19-v3/state.json", "sha256": "fc722c1417dfcb5029336df1b27f06fd1ec636ae2bc5bcfc82a2258d4f894d25"}, {"path": "build/primary-control/focused19-v3/ledger.json", "sha256": "c69a3001ec612c74afeaeafcbdf3e8fc2b0ea59fbb96bf18488a2ff641e76ebf"}, {"path": "build/primary-control/focused19-v3/decision.json", "sha256": "e5317f244c6cf6cecb4b9a9c1b3043b1921fbe646d922f332d7bdcd103fea86a"}, {"path": "build/primary-control/focused19-v3/native-result/state.json", "sha256": "627355b9bb7c970106c2c5dee504937235d6d55e5782b2129b7427e3f1024e48"}, {"path": "build/primary-control/focused19-v5/state.json", "sha256": "a4cfa1c2803d9bd6df5353e0818ec412d51d4d6ae138385842341a9eeb574186"}, {"path": "build/primary-control/focused19-v5/ledger.json", "sha256": "fd8a062065a7b7124f68a7a58251238a503aa54797ce8d911b8e857a268fa5a6"}, {"path": "build/primary-control/focused19-v5/decision.json", "sha256": "288fff0babef0edb6cf02f392285a194d9707a79af6214fe4d1e1396a3dff51b"}, {"path": "build/primary-control/focused19-v5/native-result/state.json", "sha256": "7cb9bda65b2cad09de873402d449aee0999fa88ad6b47d713514149afaea8d23"}, {"path": "build/primary-control/focused19-v6/state.json", "sha256": "4ddca9a8b8bc061dc32e288a392b8ea1e36171617d120342106a7fe0cf8bb5a4"}, {"path": "build/primary-control/focused19-v6/ledger.json", "sha256": "1e48202497a91db193cfe656222d27fe8dafe75ddd886a8296f2975c91a59004"}, {"path": "build/primary-control/focused19-v6/decision.json", "sha256": "39b1aad0ac110ac97a638b08ec1d9c22b3efa4723cce1378e87a7028a056ce4f"}, {"path": "build/primary-control/focused19-v6/native-result/state.json", "sha256": "68715beec45e143bbf7cc46615aae1704348e6dba213760c970f47ffc8cd36c5"}, {"path": "build/primary-control/focused19-v7/state.json", "sha256": "b5910e3c415ba2fd73dac642483dc10314fc9d6c798d66049e4353013d89c971"}, {"path": "build/primary-control/focused19-v7/ledger.json", "sha256": "1af45eba7e832d63fea413326cdb232f4dba879771181669ad3bc8b324871685"}, {"path": "build/primary-control/focused19-v7/decision.json", "sha256": "51e5f719fc302d9e55dc5da77069b03cd33f1e2eae9def2c59a7c48a819abbb6"}, {"path": "build/primary-control/focused19-v7/native-result/state.json", "sha256": "38b0f5cf3b0c256050fc5e90c374ab2768592e67321cfc04007f2a7c8a7c9886"}, {"path": "build/primary-control/focused19-v8/state.json", "sha256": "67b563ebb5623d62b12970225a3644a81af55a8667090296de5fdc0db37541cc"}, {"path": "build/primary-control/focused19-v8/ledger.json", "sha256": "b6a1ca5c24d248c8f249e5e05f65b515bfd542c2716ebbf74e28bbc3853196a0"}, {"path": "build/primary-control/focused19-v8/decision.json", "sha256": "7c16a01c08f9ebfe7ac34844afcf1008e8be97975449c7424c3640bbeeab640f"}, {"path": "build/primary-control/focused19-v8/native-result/state.json", "sha256": "a99bebccbfe4f0edcbe1d319ac954b82be1264584cdf0194cd330ee533b5af5e"}, {"path": "build/primary-control/focused19-v9/state.json", "sha256": "33340d4bb32a7d89d48a1e10a112c8bc210e51370b7a41809f1cab9cf98e0b4e"}, {"path": "build/primary-control/focused19-v9/ledger.json", "sha256": "553df5216f223f237f7ede78e997ca21ebd6c8ad63ee591417b585bc9b2aa082"}, {"path": "build/primary-control/focused19-v9/decision.json", "sha256": "dd38954a1f5db85b02c65c02566053e7c2dea660500ccb08c8220f34d5e7c6f9"}, {"path": "build/primary-control/focused19-v9/native-result/state.json", "sha256": "02f2ee47df6f9efb0762f320fbacc6e1f187339d11f907e2a8dad1f8b2d90044"}, {"path": "build/primary-control/focused19-v10/state.json", "sha256": "dabb6291f9cf251526c229c42affed69b15cf6bae7702acb57bcff0a62bcee79"}, {"path": "build/primary-control/focused19-v10/ledger.json", "sha256": "6f87f56ae70751274ba77a623e88a40ee8e2febd39b64f7cfa98c4eb3e2ca855"}, {"path": "build/primary-control/focused19-v10/decision.json", "sha256": "e5c4f55ab15c4b8360380bf2523847d073a1c47622fb06fce8b0c7bf83a7a01e"}, {"path": "build/primary-control/focused19-v10/native-result/state.json", "sha256": "06e5aeeb03749df8b63b151b6cbac290040f95d6bbef9745928c91455754f703"}]

RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HELPER_SHA = "dad6581212134987b666a5161ab33994e6d79b57ed38108faba6ffb22c3bb520"
CHILD_SHA = "f5bf628915da0b169468d78dac232aa9e8b4d702995051049eaa8d75274dd644"
PREFIX_IDS = ["split-upstreams", "generate-manifest", "generate-project", "verify-targets",
              "lint-generated-project", "runtime-version-contract8", "split-native-preparation",
              "split-native-artifacts", "split-restore-inputs", "split-inputs"]
SOURCE_PATHS = ["AI_HLY/ChatView.swift", "AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests.swift", "HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift", "Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoUIModule.swift", "Packages/HanlinExpoUI/src/manual-components.tsx", "Scripts/ProductSplit/run_paired_acceptance.py", "Scripts/ProductSplit/test_run_paired_acceptance.py", "Fixtures/ExpoSwiftUIProbe/ManualAdapterProbe.tsx", "AI_HLY/Downstream/AgentDiagnostics/AgentRuntimeUIAcceptanceProvider.swift", "AI_HLYUITests/MiniAppAuthoringUITests.swift", "Scripts/Expo/build-probe.mjs", "AI_HLY/Downstream/ChatCore/HanlinAppHostIntegration.swift", "HanlinMiniAppsApp/HanlinMiniAppsApp.swift", "AI_HLY/Downstream/SDK/MiniAppRepairCoordinator.swift", "AI_HLY/Downstream/ScriptingPlatform/ScriptingPackageCenterViews.swift"]
MINI = []
AI = ['AI_HLYUITests/MiniAppAuthoringUITests/testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport']
GROUPS = {'FocusedRepair1': {'expected': 1, 'selectors': ['AI_HLYUITests/MiniAppAuthoringUITests/testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport']}}
AUTHORIZATION_SCOPE = "Only original repair UI after the shared importer lifecycle correction and both affected original MiniApps and AI builds; preserve original SDK/probe output, historical ManualInput PASS and owned E742. Preserve all original52 requirements, all nine actual focused charges, separate prior400/750/200/300 grants and reconciled historical collector warning; explicitly add650 seconds to the existing5250 focused allowance."

def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def historical_group_exclusion(terminal, authority, root, derived, live_group, utc):
    pgid = int(terminal["phasePID"])
    initial = live_group(pgid)
    if not initial:
        return None
    # Numeric process-group identifiers can be reused after an authenticated clear.
    assert terminal.get("remainingOwnedProcessGroup") == []
    finished = datetime.datetime.fromisoformat(terminal["finishedAt"])
    assert finished.tzinfo is not None
    finished = finished.astimezone(datetime.timezone.utc)
    pids = {line.split()[0] for line in initial}
    argv = ["/bin/ps", "-p", ",".join(sorted(pids, key=int)),
            "-o", "pid=,pgid=,state=,lstart=,command="]
    query = subprocess.run(argv, text=True, capture_output=True, timeout=10,
                           env=dict(os.environ, TZ="UTC", LC_ALL="C"))
    assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
    months = {month: number for number, month in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}
    markers = [str(root), str(derived)]
    device = terminal.get("ownedSimulatorCleanup", {}).get("device")
    if device:
        markers.append(str(device))
    members = []
    for line in query.stdout.splitlines():
        values = line.split(None, 8)
        assert len(values) == 9, line
        if values[0] not in pids or values[1] != str(pgid) or values[2].startswith("Z"):
            continue
        started = datetime.datetime(int(values[7]), months[values[4]], int(values[5]),
            *map(int, values[6].split(":")), tzinfo=datetime.timezone.utc)
        command = values[8]
        related = [marker for marker in markers if marker and marker in command]
        assert started > finished and not related, {"historicalPGID": pgid,
            "terminal": authority, "finishedAt": finished.isoformat(),
            "startedAtUTC": started.isoformat(), "command": command, "ownedMarkers": related}
        members.append({"pid": int(values[0]), "pgid": pgid, "state": values[2],
            "startedAtUTC": started.isoformat(), "command": command})
    remaining = {int(line.split()[0]) for line in live_group(pgid)}
    assert remaining <= {member["pid"] for member in members}, "Historical group changed during targeted identity observation"
    if not members:
        return None
    return {"terminal": authority, "historicalPGID": pgid, "priorFinishedAt": terminal["finishedAt"],
        "priorRemainingOwnedProcessGroup": [], "observedAt": utc(),
        "disposition": "UNRELATED_PGID_REUSE_AFTER_AUTHENTICATED_CLEAR",
        "query": {"argv": argv, "environment": {"TZ": "UTC", "LC_ALL": "C"},
                  "exitCode": query.returncode, "stdout": query.stdout, "stderr": query.stderr},
        "members": members, "recheckedLivePIDs": sorted(remaining)}

def main():
    assert isinstance(CHILD_SHA, str) and len(CHILD_SHA) == 64, "Unsealed native child binding"
    assert isinstance(RECOVERY_INPUTS_SHA, str) and len(RECOVERY_INPUTS_SHA) == 64, "Unsealed recovery binding"
    assert isinstance(SOURCE, str) and len(SOURCE) == 40, "Unsealed final source binding"
    assert isinstance(TREE, str) and len(TREE) == 40, "Unsealed final source tree binding"
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    args = parser.parse_args()
    decision_bytes = args.decision.resolve().read_bytes()
    d = json.loads(decision_bytes)
    assert d["schema"] == 1 and d["id"] == ID and d["owner"] == "/root/native_execution"
    assert d["authorization"] == {"by": "/root", "scope": AUTHORIZATION_SCOPE}
    assert d["source"] == SOURCE and d["sourceTree"] == TREE
    assert d["allowanceSeconds"] == REMAINING_ALLOWANCE and d["original52Unchanged"] is True
    assert d["priorContinuationGrants"] == PRIOR_CONTINUATION_GRANTS
    assert d["continuationGrant"] == CONTINUATION_GRANT
    assert "supplementalContinuationGrant" not in d
    assert d["producerSource"] == PRODUCER_SOURCE and d["activeBaselineSeconds"] == ACTIVE_BASELINE
    assert d["priorFocusRecords"] == PRIOR_RECORDS
    assert d["groups"] == GROUPS and d["commandCeilingsSeconds"] == {"FocusedRepair1": 2100}
    assert math.isfinite(d["activeBaselineSeconds"]) and d["activeBaselineSeconds"] >= 0
    root = Path(d["root"]).resolve()
    ctrl = root / "build/primary-control"
    helper_path = (root / d["originalController"]["path"]).resolve()
    child_path = (root / d["child"]["path"]).resolve()
    assert helper_path.is_relative_to(ctrl) and child_path.is_relative_to(ctrl)
    assert digest(helper_path) == d["originalController"]["sha256"] == HELPER_SHA
    assert digest(child_path) == d["child"]["sha256"] == CHILD_SHA
    h = module(helper_path, "original_native_continuation_helpers")
    out = h.relative(root, d["outputDirectory"])
    assert out == ctrl / ID and not out.exists()
    child_out = out / "native-result"
    ownership = child_out / "paired-prefix/created-simulator.txt"
    lock = (ctrl / "native-continuation-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    primary_path = ctrl / "state.json"
    assert digest(primary_path) == d["primaryStateSHA256"]
    primary_bytes = primary_path.read_bytes()
    primary = json.loads(primary_bytes)
    assert primary["status"] == "PAUSED_AFTER_PHASE" and primary["phase"] == "split-inputs"
    assert primary["source"] == SOURCE and primary["activeElapsedSeconds"] == d["activeBaselineSeconds"]
    assert h.run(["git", "rev-parse", "HEAD"], cwd=root) == SOURCE
    assert h.run(["git", "rev-parse", "HEAD^{tree}"], cwd=root) == TREE
    assert hashlib.sha256(subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)).hexdigest() == d["preparedTrackedDiffSHA256"]
    prefix_path = h.relative(root, d["prefix"]["path"])
    assert prefix_path.is_relative_to(ctrl) and digest(prefix_path) == d["prefix"]["sha256"] == PREFIX_SHA
    prefix_bytes = prefix_path.read_bytes()
    prefix = json.loads(prefix_bytes)
    assert prefix["source"] == PRODUCER_SOURCE and prefix["status"] == "PASS" and not prefix["cleanupErrors"]
    assert [x["id"] for x in prefix["steps"]] == PREFIX_IDS
    assert all(x["status"] == "PASS" and x["exitCode"] == 0 for x in prefix["steps"])
    assert prefix["cumulativeActiveSeconds"] == PREFIX_BASELINE and prefix["allowanceSeconds"] == 600
    prior = []
    for item in PRIOR_RECORDS:
        path = h.relative(root, item["path"])
        assert path.is_relative_to(ctrl) and digest(path) == item["sha256"]
        prior.append(json.loads(path.read_text()))
    first_state, first_ledger, first_decision, first_child, old_state, old_ledger, old_decision, old_child = prior[:8]
    environment_state, environment_ledger, environment_decision, environment_child = prior[8:12]
    last_state, last_ledger, last_decision, last_child = prior[12:16]
    repair_state, repair_ledger, repair_decision, repair_child = prior[16:20]
    assert first_state["source"] == first_decision["source"] == first_child["source"] == PRODUCER_SOURCE
    assert first_state["status"] == first_child["status"] == "FOCUSED_FAILED"
    assert first_state["chargeCommitted"] and not first_state["cleanupErrors"] and not first_state["sourceErrors"]
    assert not first_child["groups"] and not first_child["checkpointReached"]
    assert not first_child["cleanupErrors"] and not first_child["sourceErrors"]
    assert first_state["chargedSeconds"] == first_ledger["activeElapsedSeconds"] == PRIOR_V1_CHARGE
    assert first_state["activeBaselineSeconds"] == PREFIX_BASELINE
    assert first_state["cumulativeActiveSeconds"] == PREFIX_BASELINE + PRIOR_V1_CHARGE
    assert first_ledger["allowanceSeconds"] == first_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert len(first_ledger["charges"]) == 1 and first_state["decisionSHA256"] == PRIOR_RECORDS[2]["sha256"]
    assert old_state["source"] == old_decision["source"] == old_child["source"] == PREVIOUS_SOURCE
    assert old_state["status"] == old_child["status"] == "FOCUSED_FAILED"
    assert old_state["chargeCommitted"] and not old_state["cleanupErrors"] and not old_state["sourceErrors"]
    assert not old_child["cleanupErrors"] and not old_child["sourceErrors"]
    assert old_state["chargedSeconds"] == PRIOR_V2_CHARGE
    assert old_ledger["activeElapsedSeconds"] == old_state["cumulativeFocusedSeconds"] == PRIOR_NATIVE_CHARGE
    assert old_state["activeBaselineSeconds"] == first_state["cumulativeActiveSeconds"]
    assert old_state["cumulativeActiveSeconds"] == NATIVE_BASELINE
    assert old_ledger["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert old_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE - PRIOR_V1_CHARGE
    assert len(old_ledger["charges"]) == 2 and old_ledger["charges"][:1] == first_ledger["charges"]
    assert [x["elapsedSeconds"] for x in old_ledger["charges"]] == [PRIOR_V1_CHARGE, PRIOR_V2_CHARGE]
    assert all(x in primary["focusedCharges"] for x in old_ledger["charges"])
    assert old_state["decisionSHA256"] == PRIOR_RECORDS[6]["sha256"]
    for label, passed, failed in [("FocusedMini3", 2, 1), ("FocusedAI8", 7, 1)]:
        group = old_child["groups"][label]
        assert group["resultFinalized"] and group["summary"]["passedTests"] == passed
        assert group["summary"]["failedTests"] == failed and group["summary"]["skippedTests"] == 0
    assert environment_state["source"] == environment_decision["source"] == environment_child["source"] == PRIOR_SOURCE
    assert environment_state["status"] == environment_child["status"] == "FOCUSED_FAILED"
    assert environment_state["chargeCommitted"] and not environment_state["sourceErrors"] and not environment_state["cleanupErrors"]
    assert not environment_state["remainingOwnedProcessGroup"] and not environment_child["groups"]
    assert not environment_child["checkpointReached"] and not environment_child["sourceErrors"] and not environment_child["cleanupErrors"]
    assert environment_state["chargedSeconds"] == PRIOR_ENV_CHARGE
    assert environment_state["activeBaselineSeconds"] == NATIVE_BASELINE
    assert environment_state["cumulativeActiveSeconds"] == ENV_BASELINE
    assert environment_state["cumulativeFocusedSeconds"] == environment_ledger["activeElapsedSeconds"] == PRIOR_ENV_TOTAL
    assert environment_ledger["charges"][:2] == old_ledger["charges"] and len(environment_ledger["charges"]) == 3
    assert environment_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_ENV_CHARGE
    assert all(x in primary["focusedCharges"] for x in environment_ledger["charges"])
    assert environment_state["decisionSHA256"] == PRIOR_RECORDS[10]["sha256"]
    assert last_state["source"] == last_decision["source"] == last_child["source"] == PRIOR_SOURCE
    assert last_state["status"] == last_child["status"] == "FOCUSED_FAILED"
    assert last_state["chargeCommitted"] and not last_state["sourceErrors"] and not last_state["cleanupErrors"]
    assert not last_state["remainingOwnedProcessGroup"] and not last_child["sourceErrors"] and not last_child["cleanupErrors"]
    assert last_state["chargedSeconds"] == PRIOR_V5_CHARGE and last_state["activeBaselineSeconds"] == ENV_BASELINE
    assert last_state["cumulativeActiveSeconds"] == V5_BASELINE
    assert last_ledger["charges"][:3] == environment_ledger["charges"] and len(last_ledger["charges"]) == 4
    assert last_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_V5_CHARGE
    assert math.isclose(last_ledger["activeElapsedSeconds"], PRIOR_V5_TOTAL, abs_tol=1e-8)
    assert last_state["cumulativeFocusedSeconds"] == last_ledger["activeElapsedSeconds"]
    assert last_ledger["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert last_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE - PRIOR_ENV_TOTAL
    assert all(x in primary["focusedCharges"] for x in last_ledger["charges"])
    assert last_state["decisionSHA256"] == PRIOR_RECORDS[14]["sha256"]
    for label, passed, failed in [("FocusedManual1", 1, 0), ("FocusedRepair1", 0, 1)]:
        group = last_child["groups"][label]
        assert group["resultFinalized"] and group["summary"]["totalTestCount"] == 1
        assert group["summary"]["passedTests"] == passed and group["summary"]["failedTests"] == failed
        assert group["summary"]["skippedTests"] == 0
    manual = last_child["groups"]["FocusedManual1"]
    assert manual["status"] == "PASS" and manual["exitCode"] == 0
    assert manual["selectors"] == ["HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualInputLayoutAndDataAdapters"]
    assert {("/pixel.png", 200), ("/missing.png", 404)} <= {
        (x["path"], x["status"]) for x in last_child["nativeAdapterRequests"]}
    assert repair_state["source"] == repair_decision["source"] == repair_child["source"] == PREVIOUS_REPAIR_SOURCE
    assert repair_state["status"] == repair_child["status"] == "FOCUSED_FAILED"
    assert repair_state["chargeCommitted"] and not repair_state["sourceErrors"] and not repair_state["cleanupErrors"]
    assert not repair_state["remainingOwnedProcessGroup"] and not repair_child["sourceErrors"]
    prior_collector_warning = "Command '['ps', '-axo', 'pid=,ppid=,state=,command=']' timed out after 10 seconds"
    assert repair_child["cleanupErrors"] == [prior_collector_warning]
    assert repair_state["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    assert repair_state["chargedSeconds"] == PRIOR_V6_CHARGE
    assert repair_state["activeBaselineSeconds"] == V5_BASELINE
    assert repair_state["cumulativeActiveSeconds"] == V6_BASELINE
    assert repair_state["decisionSHA256"] == PRIOR_RECORDS[18]["sha256"]
    assert len(repair_ledger["charges"]) == 5 and repair_ledger["charges"][:4] == last_ledger["charges"]
    assert repair_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_V6_CHARGE
    assert math.isclose(repair_ledger["activeElapsedSeconds"], PRIOR_V6_TOTAL, abs_tol=1e-8)
    assert repair_state["cumulativeFocusedSeconds"] == repair_ledger["activeElapsedSeconds"]
    assert repair_ledger["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert repair_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE - PRIOR_V5_TOTAL
    assert all(x in primary["focusedCharges"] for x in repair_ledger["charges"])
    assert set(repair_child["groups"]) == {"FocusedRepair1"}
    prior_repair_group = repair_child["groups"]["FocusedRepair1"]
    assert prior_repair_group["status"] == "FAIL" and prior_repair_group["exitCode"] == 65
    assert prior_repair_group["resultFinalized"] and prior_repair_group["selectors"] == AI
    assert prior_repair_group["summary"]["totalTestCount"] == prior_repair_group["summary"]["failedTests"] == 1
    assert prior_repair_group["summary"]["passedTests"] == prior_repair_group["summary"]["skippedTests"] == 0
    latest_state, latest_ledger, latest_decision, latest_child = prior[20:24]
    assert latest_state["source"] == latest_decision["source"] == latest_child["source"] == PREVIOUS_CONSUMER_SOURCE
    assert latest_state["status"] == latest_child["status"] == "FOCUSED_FAILED"
    assert latest_state["chargeCommitted"] and not latest_state["sourceErrors"] and not latest_state["cleanupErrors"]
    assert not latest_state["remainingOwnedProcessGroup"] and not latest_child["sourceErrors"] and not latest_child["cleanupErrors"]
    assert latest_state["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    assert latest_state["chargedSeconds"] == PRIOR_V7_CHARGE and latest_state["activeBaselineSeconds"] == V6_BASELINE
    assert latest_state["cumulativeActiveSeconds"] == V7_BASELINE
    assert latest_state["decisionSHA256"] == PRIOR_RECORDS[22]["sha256"]
    assert len(latest_ledger["charges"]) == 6 and latest_ledger["charges"][:5] == repair_ledger["charges"]
    assert latest_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_V7_CHARGE
    assert latest_ledger["activeElapsedSeconds"] == math.fsum(x["elapsedSeconds"] for x in latest_ledger["charges"]) == PRIOR_V7_TOTAL
    assert latest_state["cumulativeFocusedSeconds"] == latest_ledger["activeElapsedSeconds"]
    assert latest_ledger["allowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert latest_decision["allowanceSeconds"] == ORIGINAL_ALLOWANCE - PRIOR_V6_TOTAL
    assert all(x in primary["focusedCharges"] for x in latest_ledger["charges"])
    assert set(latest_child["groups"]) == {"FocusedRepair1"}
    latest_group = latest_child["groups"]["FocusedRepair1"]
    assert latest_group["status"] == "FAIL" and latest_group["exitCode"] == 65
    assert latest_group["resultFinalized"] and latest_group["selectors"] == AI
    assert latest_group["summary"]["totalTestCount"] == latest_group["summary"]["failedTests"] == 1
    assert latest_group["summary"]["passedTests"] == latest_group["summary"]["skippedTests"] == 0
    recent_state, recent_ledger, recent_decision, recent_child = prior[24:28]
    assert recent_state["source"] == recent_decision["source"] == recent_child["source"] == V8_CONSUMER_SOURCE
    assert recent_state["status"] == recent_child["status"] == "FOCUSED_FAILED"
    assert recent_state["chargeCommitted"] and not recent_state["sourceErrors"] and not recent_state["cleanupErrors"]
    assert not recent_state["remainingOwnedProcessGroup"] and not recent_child["sourceErrors"] and not recent_child["cleanupErrors"]
    assert recent_state["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    assert recent_state["chargedSeconds"] == PRIOR_V8_CHARGE and recent_state["activeBaselineSeconds"] == V7_BASELINE
    assert recent_state["cumulativeActiveSeconds"] == V8_BASELINE
    assert recent_state["decisionSHA256"] == PRIOR_RECORDS[26]["sha256"]
    assert len(recent_ledger["charges"]) == 7 and recent_ledger["charges"][:6] == latest_ledger["charges"]
    assert recent_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_V8_CHARGE
    assert recent_ledger["activeElapsedSeconds"] == math.fsum(x["elapsedSeconds"] for x in recent_ledger["charges"]) == PRIOR_V8_TOTAL
    assert recent_state["cumulativeFocusedSeconds"] == recent_ledger["activeElapsedSeconds"]
    assert recent_state["originalAllowanceSeconds"] == recent_ledger["originalAllowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert recent_ledger["allowanceSeconds"] == PRIOR_TOTAL_ALLOWANCE == 4000
    assert recent_decision["allowanceSeconds"] == PRIOR_TOTAL_ALLOWANCE - PRIOR_V7_TOTAL
    assert recent_state["continuationGrant"] == recent_ledger["continuationGrant"] == recent_decision["continuationGrant"] == PRIOR_CONTINUATION_GRANT
    assert PRIOR_CONTINUATION_GRANT["additionalSeconds"] == PRIOR_ADDITIONAL_ALLOWANCE == 400
    assert all(x in primary["focusedCharges"] for x in recent_ledger["charges"])
    assert set(recent_child["groups"]) == {"FocusedRepair1"}
    recent_group = recent_child["groups"]["FocusedRepair1"]
    assert recent_group["status"] == "FAIL" and recent_group["exitCode"] == 65
    assert recent_group["resultFinalized"] and recent_group["selectors"] == AI
    assert recent_group["summary"]["totalTestCount"] == recent_group["summary"]["failedTests"] == 1
    assert recent_group["summary"]["passedTests"] == recent_group["summary"]["skippedTests"] == 0
    v9_state, v9_ledger, v9_decision, v9_child = prior[28:32]
    assert v9_state["source"] == v9_decision["source"] == v9_child["source"] == V9_CONSUMER_SOURCE
    assert v9_state["status"] == v9_child["status"] == "FOCUSED_FAILED"
    assert v9_state["chargeCommitted"] and not v9_state["sourceErrors"] and not v9_state["cleanupErrors"]
    assert not v9_state["remainingOwnedProcessGroup"] and not v9_child["sourceErrors"] and not v9_child["cleanupErrors"]
    assert v9_state["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    assert v9_state["chargedSeconds"] == PRIOR_V9_CHARGE and v9_state["activeBaselineSeconds"] == V8_BASELINE
    assert v9_state["cumulativeActiveSeconds"] == V9_BASELINE
    assert v9_state["decisionSHA256"] == PRIOR_RECORDS[30]["sha256"]
    assert len(v9_ledger["charges"]) == 8 and v9_ledger["charges"][:7] == recent_ledger["charges"]
    assert v9_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_V9_CHARGE
    assert v9_ledger["activeElapsedSeconds"] == math.fsum(x["elapsedSeconds"] for x in v9_ledger["charges"]) == PRIOR_V9_TOTAL
    assert v9_state["cumulativeFocusedSeconds"] == v9_ledger["activeElapsedSeconds"]
    assert v9_state["originalAllowanceSeconds"] == v9_ledger["originalAllowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert v9_ledger["allowanceSeconds"] == PRIOR_V9_TOTAL_ALLOWANCE == 4950
    assert v9_decision["allowanceSeconds"] == PRIOR_V9_TOTAL_ALLOWANCE - PRIOR_V8_TOTAL
    assert v9_state["priorContinuationGrants"] == v9_ledger["priorContinuationGrants"] == v9_decision["priorContinuationGrants"] == PRIOR_V8_CONTINUATION_GRANTS
    assert v9_state["continuationGrant"] == v9_ledger["continuationGrant"] == v9_decision["continuationGrant"] == V9_CONTINUATION_GRANT
    assert v9_state["supplementalContinuationGrant"] == v9_ledger["supplementalContinuationGrant"] == v9_decision["supplementalContinuationGrant"] == V9_SUPPLEMENTAL_CONTINUATION_GRANT
    assert all(x in primary["focusedCharges"] for x in v9_ledger["charges"])
    assert set(v9_child["groups"]) == {"FocusedRepair1"}
    v9_group = v9_child["groups"]["FocusedRepair1"]
    assert v9_group["status"] == "FAIL" and v9_group["exitCode"] == 65
    assert v9_group["resultFinalized"] and v9_group["selectors"] == AI
    assert v9_group["summary"]["totalTestCount"] == v9_group["summary"]["failedTests"] == 1
    assert v9_group["summary"]["passedTests"] == v9_group["summary"]["skippedTests"] == 0
    v10_state, v10_ledger, v10_decision, v10_child = prior[32:36]
    assert v10_state["source"] == v10_decision["source"] == v10_child["source"] == PRIOR_CONSUMER_SOURCE
    assert v10_state["status"] == v10_child["status"] == "FOCUSED_FAILED"
    assert v10_state["chargeCommitted"] and not v10_state["sourceErrors"] and not v10_state["cleanupErrors"]
    assert not v10_state["remainingOwnedProcessGroup"] and not v10_child["sourceErrors"] and not v10_child["cleanupErrors"]
    assert v10_state["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    assert v10_state["chargedSeconds"] == PRIOR_V10_CHARGE and v10_state["activeBaselineSeconds"] == V9_BASELINE
    assert v10_state["cumulativeActiveSeconds"] == ACTIVE_BASELINE
    assert v10_state["decisionSHA256"] == PRIOR_RECORDS[34]["sha256"]
    assert len(v10_ledger["charges"]) == 9 and v10_ledger["charges"][:8] == v9_ledger["charges"]
    assert v10_ledger["charges"][-1]["elapsedSeconds"] == PRIOR_V10_CHARGE
    assert v10_ledger["activeElapsedSeconds"] == math.fsum(x["elapsedSeconds"] for x in v10_ledger["charges"]) == PRIOR_CHARGE
    assert v10_state["cumulativeFocusedSeconds"] == v10_ledger["activeElapsedSeconds"]
    assert v10_state["originalAllowanceSeconds"] == v10_ledger["originalAllowanceSeconds"] == ORIGINAL_ALLOWANCE
    assert v10_ledger["allowanceSeconds"] == PRIOR_V10_TOTAL_ALLOWANCE == 5250
    assert v10_decision["allowanceSeconds"] == PRIOR_V10_TOTAL_ALLOWANCE - PRIOR_V9_TOTAL
    assert v10_state["priorContinuationGrants"] == v10_ledger["priorContinuationGrants"] == v10_decision["priorContinuationGrants"] == PRIOR_V10_CONTINUATION_GRANTS
    assert v10_state["continuationGrant"] == v10_ledger["continuationGrant"] == v10_decision["continuationGrant"] == V10_CONTINUATION_GRANT
    assert all("supplementalContinuationGrant" not in row for row in (v10_state, v10_ledger, v10_decision))
    assert all(x in primary["focusedCharges"] for x in v10_ledger["charges"])
    assert set(v10_child["groups"]) == {"FocusedRepair1"}
    v10_group = v10_child["groups"]["FocusedRepair1"]
    assert v10_group["status"] == "FAIL" and v10_group["exitCode"] == 65
    assert v10_group["resultFinalized"] and v10_group["selectors"] == AI
    assert v10_group["summary"]["totalTestCount"] == v10_group["summary"]["failedTests"] == 1
    assert v10_group["summary"]["passedTests"] == v10_group["summary"]["skippedTests"] == 0
    old_ledger = v10_ledger
    assert math.isclose(PREFIX_BASELINE + PRIOR_CHARGE, ACTIVE_BASELINE, abs_tol=1e-8)
    assert PRIOR_CHARGE + d["allowanceSeconds"] == TOTAL_ALLOWANCE
    assert set(h.run(["git", "diff", "--name-only", PRODUCER_SOURCE, SOURCE], cwd=root).splitlines()) == set(CHANGED_SOURCES)

    def live_group(pgid):
        pgid = int(pgid)
        assert pgid > 1
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return []
        candidates = subprocess.run(["/usr/bin/pgrep", "-g", str(pgid)],
                                    text=True, capture_output=True, timeout=10)
        assert candidates.returncode == 0 or (candidates.returncode == 1 and not candidates.stdout.strip() and not candidates.stderr.strip()), candidates.stderr
        pids = candidates.stdout.split()
        if not pids:
            return []
        assert all(pid.isdigit() and int(pid) > 1 for pid in pids)
        query = subprocess.run(["/bin/ps", "-p", ",".join(pids), "-o", "pid=,pgid=,state="],
                               text=True, capture_output=True, timeout=10)
        assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
        return [line for line in query.stdout.splitlines() if len(v := line.split()) == 3
                and v[0] in pids and v[1] == str(pgid) and not v[2].startswith("Z")]

    historical_group_exclusions = []
    terminal_rows = d["priorTerminals"]
    assert terminal_rows and PRIOR_RECORDS[0] in terminal_rows
    prior_controllers = {primary.get("controllerPID"), prefix.get("controllerPID")} - {None}
    for item in terminal_rows:
        path = h.relative(root, item["path"])
        assert path.is_relative_to(ctrl) and digest(path) == item["sha256"]
        old = json.loads(path.read_text())
        assert old["status"] not in ("STARTING", "RUNNING", "WAITING", "READY")
        assert not old.get("remainingOwnedProcessGroup", [])
        if item["path"] == PRIOR_RECORDS[19]["path"] and item["sha256"] == PRIOR_RECORDS[19]["sha256"]:
            assert old["cleanupErrors"] == [prior_collector_warning]
        else:
            assert not old.get("cleanupErrors", [])
        if old.get("phasePID") is not None:
            exclusion = historical_group_exclusion(old, item, root, Path(d["derivedData"]), live_group, h.utc)
            if exclusion is not None:
                historical_group_exclusions.append(exclusion)
        if old.get("controllerPID") is not None:
            prior_controllers.add(old["controllerPID"])
    historic_pids = prior_controllers - {os.getpid()}
    process_rows = []
    if historic_pids:
        query = subprocess.run(["/bin/ps", "-p", ",".join(str(pid) for pid in sorted(historic_pids)),
                                "-o", "pid=,state=,command="], text=True, capture_output=True, timeout=10)
        assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
        process_rows = query.stdout.splitlines()
    for pid in historic_pids:
        for line in process_rows:
            values = line.split(None, 2)
            if len(values) != 3 or values[0] != str(pid) or values[1].startswith("Z"):
                continue
            try:
                arguments = shlex.split(values[2])
            except ValueError:
                # ps renders argv without guaranteed shell quoting.
                arguments = values[2].split()
            # PIDs can be reused. Only the actual Python control script in this
            # owned checkout identifies a surviving controller; never stop or
            # reject an unrelated process merely because it has a historical PID.
            python = bool(arguments) and Path(arguments[0]).name.lower().startswith("python")
            owned_script = any(argument.startswith(str(ctrl) + "/")
                               and Path(argument).suffix == ".py" for argument in arguments[1:])
            if python and owned_script:
                raise RuntimeError("Prior owned controller remains active: " +
                                   json.dumps({"pid": pid, "argv": arguments}, sort_keys=True))

    required = d["requiredFiles"]
    assert len({x["path"] for x in required}) == len(required)
    required_map = {x["path"]: x["sha256"] for x in required}
    assert set(SOURCE_PATHS + ["Scripts/CI/verify_selected_tests.py", "AI_HLY/RuntimeHostResources.zip"]) <= required_map.keys()
    for item in required:
        assert digest(h.relative(root, item["path"])) == item["sha256"], item["path"]
    assert required_map[RUNNER] == RUNNER_SHA
    assert required_map.get(RECOVERY_INPUTS) == RECOVERY_INPUTS_SHA
    recovery_path = h.relative(root, RECOVERY_INPUTS)
    recovery = json.loads(recovery_path.read_text())
    assert recovery["schema"] == 8 and recovery["source"] == SOURCE and recovery["producerSource"] == PRODUCER_SOURCE
    assert recovery["priorConsumerSource"] == PRIOR_CONSUMER_SOURCE
    for key, item in [("priorTerminal", PRIOR_RECORDS[12]), ("priorChild", PRIOR_RECORDS[15]),
                      ("previousRepairTerminal", PRIOR_RECORDS[32]), ("previousRepairChild", PRIOR_RECORDS[35])]:
        assert h.relative(root, recovery[key]["path"]) == h.relative(root, item["path"])
        assert recovery[key]["sha256"] == item["sha256"]
    cleanup_proof = h.relative(root, recovery["cleanupReconciliation"]["path"])
    assert cleanup_proof.is_relative_to(ctrl)
    assert digest(cleanup_proof) == recovery["cleanupReconciliation"]["sha256"]
    assert required_map.get(cleanup_proof.relative_to(root).as_posix()) == recovery["cleanupReconciliation"]["sha256"]
    assert recovery["cleanupReconciliation"]["sha256"] == "886cb2a7694c2118d65248b33b736e82985e88f58b81e497c13eec025231de8b"
    reconciled = json.loads(cleanup_proof.read_text())
    assert reconciled["schema"] == 1 and reconciled["status"] == "EXECUTED_RECONCILIATION_PASS"
    assert reconciled["source"] == PREVIOUS_REPAIR_SOURCE
    assert reconciled["priorTerminal"]["sha256"] == PRIOR_RECORDS[16]["sha256"]
    assert reconciled["priorChild"]["sha256"] == PRIOR_RECORDS[19]["sha256"]
    assert reconciled["originalChildCleanupErrors"] == repair_child["cleanupErrors"]
    assert reconciled["originalOuterCleanupErrors"] == repair_state["cleanupErrors"]
    assert reconciled["originalOuterCleanup"] == repair_state["ownedSimulatorCleanup"]
    assert reconciled["observedState"] == "Shutdown"
    assert not reconciled["remainingOwnedProcessGroup"] and not reconciled["remainingOwnedControllers"]
    assert not reconciled["remainingOwnedRunners"] and reconciled["doesNotRewritePriorFailure"]
    fixture_path = h.relative(root, recovery["priorFixtureProduction"]["path"])
    assert fixture_path.is_relative_to(ctrl)
    assert digest(fixture_path) == recovery["priorFixtureProduction"]["sha256"] == "b83ff708fb95153e2b362843b77b0a1b0d1a7e174a8dac776bf5c0621e820e4a"
    assert last_child["fixtureProduction"]["sha256"] == recovery["priorFixtureProduction"]["sha256"]
    fixture = json.loads(fixture_path.read_text())
    assert fixture["source"] == PRIOR_SOURCE and fixture["SDKProducerSource"] == PRODUCER_SOURCE
    assert fixture["exitCode"] == 0 and fixture["argv"] == ["node", "Scripts/Expo/build-probe.mjs"]
    assert len(fixture["after"]) == 13 and len({x["path"] for x in fixture["after"]}) == 13
    for row in fixture["after"]:
        path = h.relative(root, row["path"])
        assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"]
    staged_path = h.relative(root, recovery["priorStagedInputs"]["path"])
    assert staged_path.is_relative_to(ctrl)
    assert digest(staged_path) == recovery["priorStagedInputs"]["sha256"] == "bdfb50639abf0a92cb97e9a20d01316452f171f4f7399d1c872106f5d51c7d7b"
    assert v10_child["stagedInputs"]["sha256"] == recovery["priorStagedInputs"]["sha256"]
    # The dc53 Mini observation authenticates only original argv, prior history and device ownership.
    # Both current consumer products are rebuilt; this historical record claims no current product reuse.
    mini_proof = h.relative(root, recovery["miniProductObservation"]["path"])
    assert mini_proof.is_relative_to(ctrl)
    assert required_map.get(mini_proof.relative_to(root).as_posix()) == recovery["miniProductObservation"]["sha256"]
    assert digest(mini_proof) == recovery["miniProductObservation"]["sha256"] == "c14c3639721a01a91f2f4f82b49b7eda3ceb38fcda5b03549a0579b8c1779284"
    reuse = json.loads(mini_proof.read_text())
    assert reuse["schema"] == 1 and reuse["source"] == V9_CONSUMER_SOURCE
    assert h.relative(root, reuse["priorTerminal"]["path"]) == h.relative(root, PRIOR_RECORDS[28]["path"])
    assert reuse["priorTerminal"]["sha256"] == PRIOR_RECORDS[28]["sha256"]
    assert reuse["originalMiniBuildCommand"]["exit"] == 0 and reuse["originalMiniBuildCommand"]["completion_recorded"]
    assert len(reuse["files"]) == 5697 and not reuse["symlinks"]
    assert not any(x["modifiedAfterBuildTerminal"] for x in reuse["files"])
    original_ownership = h.relative(root, reuse["ownership"]["path"])
    assert original_ownership == ctrl / "focused19-v1/native-result/paired-prefix/created-simulator.txt"
    assert digest(original_ownership) == reuse["ownership"]["sha256"]
    assert str(uuid.UUID(original_ownership.read_text().strip())).upper() == str(uuid.UUID(reuse["ownership"]["device"])).upper()
    impact_path = h.relative(root, recovery["importerSourceImpact"]["path"])
    assert impact_path.is_relative_to(ctrl)
    assert digest(impact_path) == recovery["importerSourceImpact"]["sha256"] == "e086b1661f99277ccdb18e5d84dca93311a7f65fe55cb004f79ff5771910e380"
    assert required_map.get(impact_path.relative_to(root).as_posix()) == recovery["importerSourceImpact"]["sha256"]
    impact = json.loads(impact_path.read_text())
    importer_path = "AI_HLY/Downstream/ScriptingPlatform/ScriptingPackageCenterViews.swift"
    assert impact["schema"] == 1 and impact["source"] == PRIOR_CONSUMER_SOURCE and impact["target"] == importer_path
    assert set(h.run(["git", "diff", "--name-only", PRIOR_CONSUMER_SOURCE, SOURCE], cwd=root).splitlines()) == {importer_path}
    assert hashlib.sha256(subprocess.check_output(["git", "show", PRIOR_CONSUMER_SOURCE + ":" + importer_path], cwd=root)).hexdigest() == impact["sourceSHA256"]
    assert impact["compilerCaptureSource"] == V9_CONSUMER_SOURCE and impact["targetUnchangedSinceCompilerCapture"]
    assert impact["allCompilerMembersVerified"] == 87
    mini_impact, ai_impact = impact["groups"]["mini-build.log"], impact["groups"]["ai-build.log"]
    for group, count, entries in ((mini_impact, 44, 704), (ai_impact, 43, 1227)):
        assert group["fileListCount"] == count and group["entryCount"] == entries
        assert len(group["matchingLists"]) == 1
        assert [row["entry"] for row in group["matchingLists"][0]["matches"]] == [str(root / importer_path)]
    assert mini_impact["buildLog"]["sha256"] == reuse["originalMiniBuildLogSHA256"] == reuse["originalMiniBuildCommand"]["sha256"]
    assert impact["SDK"]["producerSource"] == PRODUCER_SOURCE
    assert impact["SDK"]["manifest"]["sha256"] == "4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92"
    assert impact["SDK"]["sourceInputCount"] == 235 and not impact["SDK"]["matchingSourceInputs"]
    for name in SOURCE_PATHS:
        assert hashlib.sha256(subprocess.check_output(["git", "show", SOURCE + ":" + name], cwd=root)).hexdigest() == required_map[name]
    sdk_path = h.relative(root, d["sdk"]["manifestPath"])
    assert digest(sdk_path) == d["sdk"]["manifestSHA256"]
    sdk = json.loads(sdk_path.read_text())
    assert sdk["inputSHA256"] == d["sdk"]["inputSHA256"]
    assert len(sdk["sourceInputs"]) == d["sdk"]["sourceInputCount"] == 235
    assert not set(CHANGED_SOURCES + PROBE_FIXTURES) & {x["path"] for x in sdk["sourceInputs"]}
    assert d["sdk"]["inputSHA256"] == "ba8f3f1f09054887eed62532fa1d5ca2ac3bd60e6aa99a98ab1035c7653882a2"
    assert d["sdk"]["manifestSHA256"] == "4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92"
    assert d["sdk"]["archiveSHA256"] == "7a426675109c5ebc4c8b5824565547f8aea10584785932280fdb623128530ecc"
    assert len({x["path"] for x in sdk["sourceInputs"]}) == len(sdk["sourceInputs"])
    for row in sdk["sourceInputs"]:
        assert required_map.get(row["path"]) == row["sha256"], row["path"]
    assert digest(root / "AI_HLY/RuntimeHostResources.zip") == d["sdk"]["archiveSHA256"]
    assert required_map["AI_HLY/RuntimeHostResources.zip"] == d["sdk"]["archiveSHA256"]
    preserved = d["preservedLedgers"]
    assert preserved and len({x["path"] for x in preserved}) == len(preserved)
    for item in preserved:
        assert digest(h.relative(root, item["path"])) == item["sha256"], item["path"]
    assert d["resourceAssessment"]["decision"] == "FITS_MEASURED_NEXT_PHASE"
    disk = h.run(["df", "-k", "/System/Volumes/Data"])
    free = int(disk.splitlines()[-1].split()[3]) * 1024
    assert free >= d["resourceAssessment"]["estimatedIncrementalBytes"] + d["resourceAssessment"]["concurrentAndOSAllowanceBytes"]

    out.mkdir()
    # The child exclusively creates native-result and its original paired-prefix.
    frozen = out / "decision.json"
    frozen.write_bytes(decision_bytes)
    (out / "primary-state-before.json").write_bytes(primary_bytes)
    (out / "prefix-state-before.json").write_bytes(prefix_bytes)
    (out / "prior-focused-ledger.json").write_bytes(h.relative(root, PRIOR_RECORDS[33]["path"]).read_bytes())
    state_path, events = out / "state.json", out / "events.jsonl"
    baseline, allowance = d["activeBaselineSeconds"], d["allowanceSeconds"]
    state = {"schema": 1, "id": ID, "owner": d["owner"], "source": SOURCE, "sourceTree": TREE,
             "status": "STARTING", "expectedGroups": GROUPS, "expectedTotal": 1,
             "producerSource": PRODUCER_SOURCE, "originalFocusedAllowanceSeconds": ORIGINAL_ALLOWANCE,
             "priorFocusedChargeSeconds": PRIOR_CHARGE, "priorFocusRecords": PRIOR_RECORDS,
              "historicalProcessGroupExclusions": historical_group_exclusions,
              "originalAllowanceSeconds": ORIGINAL_ALLOWANCE, "priorContinuationGrants": PRIOR_CONTINUATION_GRANTS,
              "continuationGrant": CONTINUATION_GRANT,
              "totalFocusedAllowanceSeconds": TOTAL_ALLOWANCE,
             "controllerPID": os.getpid(), "activeBaselineSeconds": baseline,
             "allowanceSeconds": allowance, "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(),
             "original52": "UNCHANGED_BY_FOCUSED_RUN", "nativeResult": "NOT_RUN",
             "resourceObservationAtLaunch": {"observedAt": h.utc(), "freeBytes": free, "df": disk}}
    def checkpoint(event, **fields):
        state.update(fields)
        h.write(state_path, state)
        with events.open("a") as stream:
            stream.write(json.dumps({"at": h.utc(), "event": event, **fields}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
    env = dict(os.environ)
    original_node = d["originalNode"]
    node_path = Path(original_node["path"]).resolve(strict=True)
    assert node_path.is_file() and digest(node_path) == original_node["sha256"]
    installed_inputs = []
    for engine in ["Expo", "NativeScript"]:
        receipt = json.loads((root / "Scripts" / engine / "node_modules/.hanlin-miniapp-install.json").read_text())
        installed_inputs.append(receipt["inputs"])
    node_identity = json.loads(h.run([str(node_path), "-p",
        "JSON.stringify({node:process.versions.node,platform:process.platform,architecture:process.arch})"]))
    assert all(all(node_identity[k] == inputs[k] for k in node_identity) for inputs in installed_inputs)
    assert node_identity["node"] == original_node["version"] == "24.5.0"
    state["originalNode"] = {**original_node, "observedIdentity": node_identity}
    env.update(PATH=str(node_path.parent) + ":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
               DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
               GITHUB_WORKSPACE=str(root), GITHUB_SHA=SOURCE, SPLIT_EVIDENCE=str(child_out),
               SPLIT_DERIVED_DATA=d["derivedData"], PAIRED_TEST_SCOPE="miniapp_complete",
               RUNNER_TEMP=str(root / "build/primary-temp"))
    argv = [sys.executable, str(child_path), "--source", SOURCE, "--output", str(child_out)]
    log = out / "controller-child.log"
    process, exit_code, error = None, None, None
    start = time.monotonic()
    checkpoint("prepared", startedAt=h.utc(), argv=argv)
    running = dict(primary)
    running.update(status="RUNNING", controllerPID=os.getpid(), phase=ID)
    h.write(primary_path, running)
    h.write(out / "ledger.json", {"schema": 1, "id": ID, "allowanceSeconds": allowance,
                                 "activeElapsedSeconds": 0, "charges": [], "otherGrantsUnchanged": True})
    def interrupted(signum, frame):
        raise InterruptedError("Focused19 received signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        with log.open("xb") as stream:
            process = subprocess.Popen(argv, cwd=root, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            checkpoint("launched", status="RUNNING", phasePID=process.pid, nativeResult="RUNNING")
            while True:
                remaining = allowance - (time.monotonic() - start)
                if remaining <= 0:
                    raise TimeoutError("Focused19 original3600 plus historical400/750/200/300 and explicit650 continuation allowance elapsed")
                try:
                    exit_code = process.wait(timeout=min(30, remaining))
                    break
                except subprocess.TimeoutExpired:
                    checkpoint("heartbeat", elapsedSeconds=time.monotonic() - start, logBytes=log.stat().st_size)
        result_path = child_out / "state.json"
        result = json.loads(result_path.read_text())
        assert exit_code == 0 and result["status"] == "FOCUSED_PASS"
        assert ownership.is_file() and not ownership.is_symlink()
        owned_device = str(uuid.UUID(ownership.read_text().strip())).upper()
        assert owned_device == str(uuid.UUID(result["simulator"])).upper()
        assert result["source"] == SOURCE and result["tree"] == TREE and result["original52"] == "NOT_RUN"
        assert result["originalTestBuilds"] == "PASS"
        assert result["miniBuildProducerSource"] == SOURCE
        assert result["aiBuildProducerSource"] == SOURCE
        assert result["SDKProducerSource"] == PRODUCER_SOURCE
        assert result["recoveryInputSHA256"] == RECOVERY_INPUTS_SHA
        assert owned_device == str(uuid.UUID(reuse["ownership"]["device"])).upper()
        assert result["reusedSetup"] == [
            {"status": "REUSED_AUTHENTICATED_OWNED_DEVICE", "authority": reuse["ownership"]}]
        assert result["reusedManualProof"] == {"authority": recovery["priorChild"],
            "group": manual, "nativeAdapterRequests": last_child["nativeAdapterRequests"]}
        assert result["fixtureProduction"] == {**recovery["priorFixtureProduction"],
            "outputs": 13, "status": "REUSED_ORIGINAL_PRODUCER_PASS"}
        assert result["selectors"] == {k: v["selectors"] for k, v in GROUPS.items()}
        assert set(result["groups"]) == set(GROUPS)
        assert not result["sourceErrors"] and not result["cleanupErrors"] and not result["errors"]
        for label, expected in GROUPS.items():
            group = result["groups"][label]
            assert group["status"] == "PASS" and group["exitCode"] == 0 and group["resultFinalized"] is True
            assert group["selectors"] == expected["selectors"]
            summary = group["summary"]
            assert summary["totalTestCount"] == summary["passedTests"] == expected["expected"]
            assert summary["failedTests"] == summary["skippedTests"] == 0
        bindings = result["builtInputBindings"]
        product_receipt = Path(bindings["path"]).resolve()
        assert product_receipt == child_out / "built-input-bindings.json"
        assert digest(product_receipt) == bindings["sha256"]
        built = json.loads(product_receipt.read_text())
        assert built["source"] == SOURCE and built["miniBuildProducerSource"] == SOURCE
        assert built["aiBuildProducerSource"] == SOURCE
        assert built["SDKProducerSource"] == PRODUCER_SOURCE
        assert built["originalTestBuilds"] == "PASS"
        assert "authenticatedMiniReuse" not in built
        assert "authenticatedAIReuse" not in built
        assert result["hostArchiveSHA256"] == d["sdk"]["archiveSHA256"]
        checkpoint("actual_terminal", status="FOCUSED_PASS", nativeResult="EXECUTED_PASS",
                   exitCode=exit_code, childStateSHA256=digest(result_path),
                   builtInputBindingsSHA256=bindings["sha256"], groups=result["groups"])
    except BaseException as failure:
        error = type(failure).__name__ + ": " + str(failure)
        checkpoint("actual_terminal", status="TIMED_OUT" if isinstance(failure, TimeoutError) else "FOCUSED_FAILED",
                   nativeResult="FAILED_OR_INCOMPLETE", error=error, exitCode=exit_code)
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup = []
        if process is not None:
            try:
                members = live_group(process.pid)
                state["ownedProcessGroupAtCleanup"] = members
                for sig, seconds in [(signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not members:
                        break
                    try:
                        os.killpg(process.pid, sig)
                    except ProcessLookupError:
                        pass
                    until = time.monotonic() + seconds
                    while members and time.monotonic() < until:
                        if process.poll() is None:
                            try:
                                process.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                        else:
                            time.sleep(0.25)
                        members = live_group(process.pid)
                process.wait(timeout=5)
                state["remainingOwnedProcessGroup"] = members
                state["observedPhaseExitCode"] = process.returncode
                if members:
                    cleanup.append("Owned phase group survived bounded TERM/KILL")
            except Exception as failure:
                cleanup.append("Owned phase cleanup: " + str(failure))
        try:
            if ownership.exists():
                # No guessed or previously owned device is ever substituted here.
                assert ownership.is_file() and not ownership.is_symlink()
                device = str(uuid.UUID(ownership.read_text().strip())).upper()
                result = subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True,
                                        text=True, timeout=30, env=env)
                devices = json.loads(h.run(["xcrun", "simctl", "list", "devices", "-j"], env=env, timeout=15))
                found = [x for values in devices["devices"].values() for x in values if x["udid"].upper() == device]
                observed = found[0]["state"] if len(found) == 1 else "UNKNOWN"
                state["ownedSimulatorCleanup"] = {"device": device, "ownership": str(ownership),
                    "ownershipSHA256": digest(ownership), "exitCode": result.returncode,
                    "stdout": result.stdout, "stderr": result.stderr, "observedState": observed, "observedAt": h.utc()}
                if observed != "Shutdown":
                    cleanup.append("New owned simulator not confirmed Shutdown")
            else:
                state["ownedSimulatorCleanup"] = {"status": "NO_CHILD_OWNERSHIP_FILE", "ownership": str(ownership)}
        except Exception as failure:
            cleanup.append("Owned simulator cleanup: " + str(failure))
        state["cleanupErrors"] = cleanup
        if cleanup:
            state["status"] = "CLEANUP_INCOMPLETE"
        drift = []
        try:
            if h.run(["git", "rev-parse", "HEAD"], cwd=root) != SOURCE:
                drift.append("Git HEAD changed")
            for item in required:
                if digest(h.relative(root, item["path"])) != item["sha256"]:
                    drift.append("Canonical source/SDK input changed: " + item["path"])
            for row in fixture["after"]:
                path = h.relative(root, row["path"])
                if path.stat().st_size != row["bytes"] or digest(path) != row["sha256"]:
                    drift.append("Retained original probe output changed: " + row["path"])
            for item in [recovery["priorFixtureProduction"], recovery["priorStagedInputs"]]:
                if digest(h.relative(root, item["path"])) != item["sha256"]:
                    drift.append("Retained preparation receipt changed: " + item["path"])
            if digest(child_path) != CHILD_SHA or digest(helper_path) != HELPER_SHA:
                drift.append("Bound execution code changed")
            if digest(sdk_path) != d["sdk"]["manifestSHA256"]:
                drift.append("Prepared SDK manifest changed")
            for item in preserved + terminal_rows + [d["prefix"]] + PRIOR_RECORDS:
                if digest(h.relative(root, item["path"])) != item["sha256"]:
                    drift.append("Historical receipt/ledger changed: " + item["path"])
        except Exception as failure:
            drift.append("Final input observation: " + str(failure))
        state["sourceErrors"] = drift
        if drift:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - start
        checkpoint("charge_ready", finishedAt=h.utc(), elapsedSeconds=elapsed, chargedSeconds=elapsed,
                   cumulativeActiveSeconds=baseline + elapsed,
                   cumulativeFocusedSeconds=PRIOR_CHARGE + elapsed,
                   allowanceExceededDuringCleanup=elapsed > allowance,
                   logBytes=log.stat().st_size if log.exists() else 0,
                   logSHA256=digest(log) if log.exists() else None)
        try:
            current = json.loads(primary_path.read_text())
            assert current["activeElapsedSeconds"] == baseline and current.get("controllerPID") == os.getpid()
            charge = {"id": ID, "source": SOURCE, "status": state["status"], "elapsedSeconds": elapsed,
                      "statePath": str(state_path), "decisionSHA256": state["decisionSHA256"],
                      "logSHA256": state["logSHA256"], "exitCode": exit_code,
                      "expectedGroups": {"FocusedRepair1": 1}}
            h.write(out / "ledger.json", {"schema": 1, "id": ID, "allowanceSeconds": TOTAL_ALLOWANCE,
                                          "originalAllowanceSeconds": ORIGINAL_ALLOWANCE,
                                          "priorContinuationGrants": PRIOR_CONTINUATION_GRANTS,
                                          "continuationGrant": CONTINUATION_GRANT,
                                          "continuationAllowanceSeconds": allowance,
                                         "continuationElapsedSeconds": elapsed,
                                         "activeElapsedSeconds": PRIOR_CHARGE + elapsed,
                                         "charges": old_ledger["charges"] + [charge],
                                         "originalLedger": PRIOR_RECORDS[33], "otherGrantsUnchanged": True})
            current["activeElapsedSeconds"] = baseline + elapsed
            current.setdefault("focusedCharges", []).append(charge)
            current.update(status=primary["status"], phase=primary.get("phase"),
                           controllerPID=None, finishedAt=state["finishedAt"])
            # Original52, earlier acceptance and all separate grants are preserved.
            h.write(primary_path, current)
            state["chargeCommitted"] = True
            state["focusedLedgerSHA256"] = digest(out / "ledger.json")
        except Exception as failure:
            state.update(status="LEDGER_RECONCILIATION_REQUIRED", ledgerError=str(failure),
                         uncommittedOrPartiallyCommittedChargeSeconds=elapsed)
        checkpoint("finalized", status=state["status"])
    return 0 if state["status"] == "FOCUSED_PASS" else 1

if __name__ == "__main__":
    raise SystemExit(main())
