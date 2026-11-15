"""Reject an empty, skipped, or partial focused Swift Testing run."""
import json
import sys

EXPECTED = (
    "heightAndOverflow",
    "remainingViewportBudget",
    "backSwipeThreshold",
    "pageIdentity",
    "coordinatorNavigationPreservesOpenState",
)


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)


with open(sys.argv[1], encoding="utf-8") as stream:
    result = json.load(stream)

nodes = list(dictionaries(result))
for case in EXPECTED:
    statuses = []
    for node in nodes:
        identifiers = (str(node.get(key, "")) for key in ("nodeIdentifier", "nodeIdentifierURL", "name"))
        if any(case in identifier for identifier in identifiers):
            status = node.get("result")
            if isinstance(status, str):
                statuses.append(status.lower())
    if not statuses or any(status != "passed" for status in statuses):
        raise SystemExit(f"Missing, skipped, or non-passing case {case}: {statuses}")
    print(f"EXECUTED_PASS {case}")
