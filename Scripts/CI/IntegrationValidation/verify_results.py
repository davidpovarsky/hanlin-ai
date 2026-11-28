"""Require each registered Swift Testing case once and actually passed."""
import json
import re
import sys
import argparse

EXPECTED = {
    "canonicalBrokerRoundTripPreservesOriginAndConsumesReturn",
    "canonicalAuthorityDenialIsNotBypassedByAdapter",
    "absentTransportCannotAdvanceToDispatched",
    "registeredMigrationIsPureAndPreservesIdentityBytes",
    "unconfiguredDurableReceiverRejectsBeforePersistence",
    "recoveryDecisionSurvivesSerializationAndCannotReverse",
}


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)


def verify(result, expected=EXPECTED):
    cases = []
    for node in dictionaries(result):
        if str(node.get("nodeType", "")).replace(" ", "").lower() != "testcase":
            continue
        identity = " ".join(str(node.get(key, "")) for key in ("name", "nodeIdentifier", "nodeIdentifierURL"))
        matches = [name for name in expected if re.search(r"\b" + name + r"\b", identity)]
        if len(matches) != 1 or str(node.get("result", "")).lower() != "passed":
            raise ValueError(f"Unexpected or non-passing test case: {node}")
        cases.extend(matches)
    if len(cases) != len(expected) or set(cases) != expected:
        raise ValueError(f"Missing/duplicate/zero test cases: {cases}")
    return sorted(cases)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("--miniapps-ui", action="store_true")
    args = parser.parse_args()
    expected = ({"testCanonicalLibraryLaunchesRealCompiledSwiftApp", "testManagementPresentsExistingPackageImportScreen",
                 "testOrdinaryInstalledScriptUICatalogAndStatefulLaunch", "failureIsVisibleAndRetryReexecutesPreparation",
                 "concurrentPreparationDoesNotDuplicateTheBoundary", "successfulPreparationIsNotRepeated"}
                if args.miniapps_ui else EXPECTED)
    with open(args.source, encoding="utf-8") as stream:
        print(json.dumps({"status": "EXECUTED_PASS", "cases": verify(json.load(stream), expected)}, indent=2))
