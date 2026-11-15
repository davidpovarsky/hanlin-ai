"""Require each registered Swift Testing case once and actually passed."""
import json
import re
import sys

EXPECTED = {
    "canonicalBrokerRoundTripPreservesOriginAndConsumesReturn",
    "canonicalAuthorityDenialIsNotBypassedByAdapter",
    "absentTransportCannotAdvanceToDispatched",
    "registeredMigrationIsPureAndPreservesIdentityBytes",
    "unconfiguredDurableReceiverRejectsBeforePersistence",
}


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)


def verify(result):
    cases = []
    for node in dictionaries(result):
        if str(node.get("nodeType", "")).replace(" ", "").lower() != "testcase":
            continue
        identity = " ".join(str(node.get(key, "")) for key in ("name", "nodeIdentifier", "nodeIdentifierURL"))
        matches = [name for name in EXPECTED if re.search(r"\b" + name + r"\b", identity)]
        if len(matches) != 1 or str(node.get("result", "")).lower() != "passed":
            raise ValueError(f"Unexpected or non-passing test case: {node}")
        cases.extend(matches)
    if len(cases) != len(EXPECTED) or set(cases) != EXPECTED:
        raise ValueError(f"Missing/duplicate/zero test cases: {cases}")
    return sorted(cases)


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as stream:
        print(json.dumps({"status": "EXECUTED_PASS", "cases": verify(json.load(stream))}, indent=2))
