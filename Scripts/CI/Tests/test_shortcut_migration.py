"""Portable migration admission controls, not an old product or OS execution."""
import copy
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
with patch.object(sys, "path", [str(ROOT / "Scripts/ProductSplit"), str(Path(__file__).parent), *sys.path]), patch.dict(sys.modules):
    import shortcut_migration_contract as contract
    import observe_shortcut_migration as reader
    import upgrade_shortcut_migration as setup
    from test_shortcut_native_lists import wire

RUN = "11111111-1111-4111-8111-111111111111"
COMMAND = "22222222-2222-4222-8222-222222222222"
IDENTITY = {"identity": {"installedPackageID": "owned-package", "packageID": "source-package",
                        "generation": 1, "entrypointID": "native-lists-intent", "variantID": "default"}}


def example(engine="nativescript"):
    values = ["שלום", RUN, 7, 2.5, True, False]
    name = "Hanlin-migration-" + engine + "-" + RUN[:8]
    element = {"label": name, "identifier": "", "elementType": 9}
    request = {"runID": RUN, "engine": engine, "step": 0, "savedShortcutName": name,
        "builtInChain": ["Get Text from Input", "Show Result"],
        "editor": {"savedShortcutName": name, "savedAndReopened": True, "processRestarted": True,
                   "inputMode": "Dictionary or List (JSON)", "inputParameter": "input",
                   "openWhenRun": False, "values": values, "rawInput": json.dumps(values),
                   "builtInChain": ["Get Text from Input", "Show Result"],
                   **{key: copy.deepcopy(element) for key in
                      ("savedElement", "actionElement", "modeElement", "inputElement")}}}
    app = "hanlin.shortcutlists." + engine
    result = {"schema": 1, "appID": app, "actionID": "native-lists.echo", "values": values,
              "observedTypes": ["string", "string", "number", "number", "boolean", "boolean"],
              "nonce": "actual123-random456", "caller": "hanlin.host",
              "observedAt": "2026-11-28T08:00:00.100Z"}
    if engine == "nativescript":
        result.update(windowID="owned-window", statePath="/actual/private/State//native-list-actual123-random456.json",
                      executionMode="headless-action", attached=False)
    else:
        result.update(invocationID=COMMAND, stateFile="native-list-actual123-random456.json")
    row = {"id": COMMAND, "createdAt": 1795852800050,
           "invocation": {"identity": copy.deepcopy(IDENTITY["identity"]), "entityID": "native-lists.echo",
                          "parameters": wire(values), "continueInForeground": False,
                          "delivery": {"schemaVersion": 1, "appID": app, "source": "shortcuts",
                                       "userGesturePresent": True, "canPresentUI": False}},
           "receipt": {"status": "succeeded", "failure": None, "cancellationRequested": False,
                       "leaseID": None, "leaseExpiresAt": None, "attempt": 1, "value": wire(result)}}
    return request, {COMMAND: {"value": row}}, 1795852800000


def descriptor_fixture(root):
    # Controlled filesystem fixture for the public descriptor parser, never an
    # actual signed app/product or proof of native installation behavior.
    for relative in contract.DESCRIPTOR_PRODUCTS:
        path = root / "Debug-iphonesimulator" / relative
        path.mkdir(parents=True, exist_ok=True)
        executable = path.stem
        identifier = contract.AI if relative == "AI_Hanlin.app" else "controlled." + relative.replace("/", ".")
        (path / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": executable}))
        (path / executable).write_bytes(b"CONTROLLED_DESCRIPTOR_FIXTURE")
    target = {"TestHostPath": "__TESTROOT__/Debug-iphonesimulator/AI_HLYUITests-Runner.app",
              "TestBundlePath": "__TESTHOST__/PlugIns/AI_HLYUITests.xctest",
              "UITargetAppPath": "__TESTROOT__/Debug-iphonesimulator/AI_Hanlin.app",
              "DependentProductPaths": ["__TESTROOT__/Debug-iphonesimulator/" + name
                                       for name in contract.DESCRIPTOR_PRODUCTS],
              "IsUITestBundle": True, "EnvironmentVariables": {"ORIGINAL": "retained"},
              "TestingEnvironmentVariables": {"DYLD_FRAMEWORK_PATH": "__TESTROOT__/Debug-iphonesimulator"}}
    return {"AI_HLYTests": {"TestBundlePath": "unused-original-unit-target"},
            "AI_HLYUITests": target, "__xctestrun_metadata__": {"FormatVersion": 1}}


class GenuineShortcutMigrationTests(unittest.TestCase):
    def test_actual_current_metadata_and_controlled_old_shape_are_distinct(self):
        current = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        old = copy.deepcopy(current)
        old["actions"]["HanlinRunMiniAppShortcutIntent"]["parameters"] = [
            row for row in old["actions"]["HanlinRunMiniAppShortcutIntent"]["parameters"]
            if row["name"] in contract.PARAMETERS]
        before = contract.metadata_contract(old, "old")
        after = contract.metadata_contract(current, "current")
        self.assertEqual(len(before["parameters"]), 5)
        self.assertEqual(len(after["parameters"]), 9)
        self.assertEqual(before["originalParameters"], after["originalParameters"])

    def test_actual_old_input_alternative_permutation_preserves_complete_metadata(self):
        current = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        after = contract.metadata_contract(current, "current")["originalParameters"]
        before = copy.deepcopy(after)
        # Exact complete input alternatives from the genuine f45 actionsdata:
        # c37f688d78362bf040dc8b63e2c793a5caf3d4c7a7410494cca542522b70ac41.
        # This is a controlled metadata comparison, not old-product/OS acceptance.
        before["input"]["resolvableInputTypes"] = [
            {"kindValue": 0, "valueType": {"primitive": {"wrapper": {"typeIdentifier": 2}}}},
            {"kindValue": 0, "valueType": {"array": {"wrapper": {"capabilities": 3,
                "memberValueType": {"primitive": {"wrapper": {"typeIdentifier": 2}}}}}}},
            {"kindValue": 0, "valueType": {"primitive": {"wrapper": {"typeIdentifier": 0}}}},
        ]
        retained = copy.deepcopy((before, after))
        self.assertNotEqual(before, after)
        self.assertTrue(contract.original_parameters_equal(after, before))
        self.assertEqual((before, after), retained)

    def test_metadata_comparison_rejects_missing_duplicate_changed_and_other_order_drift(self):
        current = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        original = contract.metadata_contract(current, "current")["originalParameters"]
        for mutation in ("missing", "duplicate", "changed-alternative", "other-array", "other-field"):
            changed = copy.deepcopy(original)
            alternatives = changed["input"]["resolvableInputTypes"]
            if mutation == "missing":
                alternatives.pop()
            elif mutation == "duplicate":
                alternatives.append(copy.deepcopy(alternatives[0]))
            elif mutation == "changed-alternative":
                alternatives[0]["valueType"]["primitive"]["wrapper"]["typeIdentifier"] = 99
            elif mutation == "other-array":
                changed["input"]["typeSpecificMetadata"].reverse()
            else:
                changed["input"]["isOptional"] = True
            with self.subTest(mutation=mutation):
                self.assertFalse(contract.original_parameters_equal(original, changed))

    def test_current_product_cannot_substitute_for_old_baseline(self):
        current = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        with self.assertRaises(ValueError):
            contract.metadata_contract(current, "old")

    def test_wrong_or_duplicate_original_parameter_is_rejected(self):
        current = json.loads((Path(__file__).parent / "fixtures/native_lists_actionsdata.json").read_text())
        parameters = current["actions"]["HanlinRunMiniAppShortcutIntent"]["parameters"]
        old_rows = [row for row in parameters if row["name"] in contract.PARAMETERS]
        for replacement in ("differentAction", "input"):
            document = {"actions": {"HanlinRunMiniAppShortcutIntent": {
                "identifier": "HanlinRunMiniAppShortcutIntent", "parameters": copy.deepcopy(old_rows)}}}
            document["actions"]["HanlinRunMiniAppShortcutIntent"]["parameters"][0]["name"] = replacement
            with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                contract.metadata_contract(document, "old")

    def test_mixed_native_scalar_tags_reject_equal_number_bool_and_foreign_uuid(self):
        values = ["שלום", RUN, 7, 2.5, True, False]
        self.assertEqual(contract.native_values(wire(values), RUN), values)
        for index, replacement in ((2, wire(7.0)), (4, wire(1)), (1, wire(COMMAND))):
            value = wire(values)
            value["value"][index] = replacement
            with self.subTest(index=index), self.assertRaises(ValueError):
                contract.native_values(value, RUN)

    def test_both_real_handler_contracts_accept_the_mixed_array(self):
        for engine in ("nativescript", "expo"):
            request, commands, armed = example(engine)
            with self.subTest(engine=engine):
                result = reader.terminal_result(request, IDENTITY, set(), commands, armed)
                self.assertEqual(result["invocationID"], COMMAND)
                self.assertEqual(result["result"]["values"], ["שלום", RUN, 7, 2.5, True, False])

    def test_stale_duplicate_and_replayed_commands_cannot_prove_upgrade(self):
        request, commands, armed = example()
        self.assertIsNone(reader.terminal_result(request, IDENTITY, {COMMAND}, commands, armed))
        commands[COMMAND]["value"]["createdAt"] = armed - 1
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)
        request, commands, armed = example()
        commands["33333333-3333-4333-8333-333333333333"] = copy.deepcopy(commands[COMMAND])
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_foreign_generation_or_expo_invocation_cannot_prove_our_saved_action(self):
        request, commands, armed = example()
        commands[COMMAND]["value"]["invocation"]["identity"]["generation"] = 2
        self.assertIsNone(reader.terminal_result(request, IDENTITY, set(), commands, armed))
        request, commands, armed = example("expo")
        result = reader.shared.decode_value(commands[COMMAND]["value"]["receipt"]["value"])
        result["invocationID"] = "33333333-3333-4333-8333-333333333333"
        commands[COMMAND]["value"]["receipt"]["value"] = wire(result)
        with self.assertRaises(ValueError):
            reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_running_failed_retried_and_leased_commands_are_not_completed(self):
        for key, value in (("status", "running"), ("status", "failed"), ("attempt", 2), ("leaseID", COMMAND)):
            request, commands, armed = example()
            commands[COMMAND]["value"]["receipt"][key] = value
            if value == "running":
                self.assertIsNone(reader.terminal_result(request, IDENTITY, set(), commands, armed))
            else:
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    reader.terminal_result(request, IDENTITY, set(), commands, armed)

    def test_saved_name_mode_raw_input_and_chain_are_required(self):
        for key, value in (("savedShortcutName", "newly-created-current-shortcut"),
                           ("inputMode", "Text List"), ("rawInput", '["different"]'),
                           ("openWhenRun", True), ("builtInChain", ["Show Result"])):
            request, _, _ = example()
            request["editor"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                contract.saved_editor(request)

    def test_actual_ai_only_descriptor_shape_retains_original_environment(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = descriptor_fixture(root)
            selected, closure = contract.descriptor_installation(original, root)
            self.assertEqual(set(selected), {"AI_HLYUITests", "__xctestrun_metadata__"})
            self.assertEqual(selected["AI_HLYUITests"], original["AI_HLYUITests"])
            self.assertEqual(len(closure["products"]), 8)
            target = {**original["AI_HLYUITests"], "BlueprintName": "AI_HLYUITests"}
            version2 = {"TestConfigurations": [{"Name": "Original", "TestTargets": [
                {"BlueprintName": "AI_HLYTests", "TestBundlePath": "unselected"}, target]}],
                "__xctestrun_metadata__": {"FormatVersion": 2}}
            copied, actual = contract.descriptor_installation(version2, root)
            self.assertEqual(copied["TestConfigurations"][0]["TestTargets"], [target])
            self.assertEqual(actual, closure)

    def test_descriptor_rejects_miniapps_dependency_and_disguised_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = descriptor_fixture(root)
            changed = copy.deepcopy(original)
            changed["AI_HLYUITests"]["DependentProductPaths"].append("__TESTROOT__/Debug-iphonesimulator/HanlinMiniApps.app")
            (root / "Debug-iphonesimulator/HanlinMiniApps.app").mkdir()
            with self.assertRaises(ValueError):
                contract.descriptor_installation(changed, root)
            info = root / "Debug-iphonesimulator/AI_Hanlin.app/Info.plist"
            document = plistlib.loads(info.read_bytes()); document["CFBundleIdentifier"] = contract.APP
            info.write_bytes(plistlib.dumps(document))
            with self.assertRaises(ValueError):
                contract.descriptor_installation(original, root)

    def test_descriptor_rejects_escape_duplicate_and_changed_test_selection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = descriptor_fixture(root)
            for mutation in ("escape", "duplicate", "selection"):
                changed = copy.deepcopy(original); target = changed["AI_HLYUITests"]
                if mutation == "escape":
                    target["UITargetAppPath"] = "__TESTROOT__/../other.app"
                elif mutation == "duplicate":
                    target["DependentProductPaths"].append(target["DependentProductPaths"][0])
                else:
                    target["SkipTestIdentifiers"] = ["a/real/original/test"]
                with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                    contract.descriptor_installation(changed, root)

    def test_upgrade_requires_actual_not_running_observations_without_guessing_raw_enum_values(self):
        request = {"miniAppsNotRunning": True, "shortcutsNotRunning": True,
                   "miniAppsStateBeforeUpgrade": 1, "shortcutsStateBeforeUpgrade": 1}
        self.assertEqual(contract.terminated_apps(request), request)
        for key, value in (("miniAppsNotRunning", False), ("shortcutsNotRunning", False),
                           ("miniAppsStateBeforeUpgrade", None), ("shortcutsStateBeforeUpgrade", True)):
            changed = {**request, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                contract.terminated_apps(changed)

    def test_restarted_setup_rejects_existing_install_intent_before_any_os_access(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "migration-upgrade-intent.json").write_text('{"status":"prior actual or uncertain install"}')
            with patch.object(setup.shared, "os_container") as lookup, patch.object(setup, "run_install") as install:
                with self.assertRaises(ValueError):
                    setup.upgrade_once(root / "absent-input.json", "0" * 64, root, {}, lambda: False)
                lookup.assert_not_called()
                install.assert_not_called()

    def test_same_containers_are_required_after_in_place_install(self):
        baseline = {"data": "/owned/data", "group": "/owned/group", "extensions": "/owned/group/extensions"}
        roots = {key: Path(value) for key, value in baseline.items()}
        self.assertEqual(setup.preserved_containers(roots, baseline), baseline)
        for key in baseline:
            changed = dict(roots); changed[key] = Path("/different/" + key)
            with self.subTest(key=key), self.assertRaises(ValueError):
                setup.preserved_containers(changed, baseline)


if __name__ == "__main__":
    unittest.main()
