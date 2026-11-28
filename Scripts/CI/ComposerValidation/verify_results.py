"""Require unique, passing actual cases for the exact prepared Composer inputs."""
import argparse
from collections import Counter
import json
import sys

LEGACY_CASES = (
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


def verify(result, expected):
    nodes = [node for node in dictionaries(result) if node.get("nodeType") == "Test Case"]
    actual = []
    for node in nodes:
        identifier = node.get("nodeIdentifier") or node.get("nodeIdentifierURL", "")
        # Xcode exports either Suite/case() or a fully qualified test URL.
        identifier = "/".join(identifier.rstrip("/").split("/")[-2:])
        if node.get("result") != "Passed":
            raise ValueError(f"Non-passing actual case: {identifier}: {node.get('result')}")
        actual.append(identifier)
    counts = Counter(actual)
    if len(expected) != len(set(expected)) or any(count != 1 for count in counts.values()):
        raise ValueError("Duplicate expected or actual test identities")
    if set(actual) != set(expected):
        raise ValueError(f"Case mismatch; missing={sorted(set(expected) - set(actual))}, unexpected={sorted(set(actual) - set(expected))}")
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results")
    parser.add_argument("--inputs", help="The exact preparation proof-inputs.json")
    args = parser.parse_args()
    with open(args.results, encoding="utf-8") as stream:
        result = json.load(stream)
    if args.inputs:
        with open(args.inputs, encoding="utf-8") as stream:
            inputs = json.load(stream)
        expected = inputs["expected_case_ids"]
    else:
        # The historical five-case component recipe remains verifiable as such.
        expected = [f"HanlinMorphComposerTests/{case}()" for case in LEGACY_CASES]
    for case in verify(result, expected):
        print(f"EXECUTED_PASS {case}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
