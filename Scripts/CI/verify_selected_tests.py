"""Reject an empty/omitted requested XCTest or Swift Testing execution.

Uses actual xcresulttool test nodes, never the xcodebuild exit code or a suite
heading. A failed case counts as executed; xcodebuild still owns its failure.
"""
import argparse
import json
from pathlib import Path
from urllib.parse import unquote, urlparse


def missing_selectors(results, selectors):
    executed = []
    pending = list(results.get("testNodes", []))
    while pending:
        node = pending.pop()
        pending.extend(node.get("children", []))
        if node.get("nodeType") != "Test Case" or node.get("result") not in {"Passed", "Failed", "Expected Failure"}:
            continue
        identifier = node.get("nodeIdentifierURL") or node.get("nodeIdentifier", "")
        if identifier.startswith("test://"):
            identifier = unquote(urlparse(identifier).path).strip("/")
        executed.append(identifier.removesuffix("()"))
    missing = []
    for selector in selectors:
        requested = selector.strip().removesuffix("()")
        if not any(value == requested or value.endswith("/" + requested)
                   or ("/" + requested + "/") in ("/" + value + "/") for value in executed):
            # Older xcresult versions omit the bundle in nodeIdentifier.
            suffix = requested.split("/", 1)[-1]
            if not any(value == suffix or value.startswith(suffix + "/") for value in executed):
                missing.append(selector)
    return missing


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--selectors", required=True)
    args = parser.parse_args()
    missing = missing_selectors(json.loads(args.results.read_text(encoding="utf-8")), args.selectors.split(","))
    if missing:
        raise SystemExit("Requested tests did not execute: " + ", ".join(missing))
    print("Requested test execution found in actual xcresult nodes.")
