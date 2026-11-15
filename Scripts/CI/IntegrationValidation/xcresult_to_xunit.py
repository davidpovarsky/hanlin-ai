"""Convert actual xcresulttool Test Case nodes for the owner's XML verifier.

No expected case list is synthesized here. Unknown status is an error and the
owner's unchanged recipe separately enforces its exact 25-case contract.
"""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def convert(data):
    root = ET.Element("testsuite", name="Actual xcresult export")
    identities = []
    failures = skips = 0
    for node in nodes(data):
        if str(node.get("nodeType", "")).replace(" ", "").lower() != "testcase":
            continue
        name = str(node.get("name", ""))
        identity = str(node.get("nodeIdentifier", ""))
        if not name or not identity:
            raise ValueError(f"Missing actual case identity: {node}")
        status = str(node.get("result", "")).lower()
        case = ET.SubElement(root, "testcase", name=name, classname=identity, status=status)
        identities.append({"name": name, "identifier": identity, "result": status})
        if status == "passed":
            continue
        if status == "skipped":
            ET.SubElement(case, "skipped")
            skips += 1
        else:
            ET.SubElement(case, "failure", message=f"Actual result: {status or 'unknown'}")
            failures += 1
    if not identities:
        raise ValueError("No actual Test Case nodes in xcresult export")
    root.set("tests", str(len(identities)))
    root.set("failures", str(failures))
    root.set("skipped", str(skips))
    return ET.ElementTree(root), identities


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    raw = args.source.read_bytes()
    tree, cases = convert(json.loads(raw))
    tree.write(args.destination, encoding="utf-8", xml_declaration=True)
    print(json.dumps({"source_export_sha256": hashlib.sha256(raw).hexdigest(),
                      "actual_cases": cases}, indent=2))
