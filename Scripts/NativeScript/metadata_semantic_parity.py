"""Versioned compatibility check for the unchanged NativeScript metadata model.

The pinned BinaryTypeEncodingSerializer::visitTypeArgument serializes the
underlying type. Retain protocol bounds and all existing API fields while
comparing that representation. Raw YAML identities remain separate evidence.
"""
import copy
import json
from pathlib import Path
import subprocess

MEMBERS = {"Items", "InstanceMethods", "StaticMethods", "InstanceProperties", "StaticProperties"}


def erase_generic_encoding(value):
    if isinstance(value, list):
        return [erase_generic_encoding(item) for item in value]
    if not isinstance(value, dict):
        return value
    if value.get("Type") != "TypeArgument":
        return {key: erase_generic_encoding(item) for key, item in value.items()}
    if set(value) - {"Type", "Name", "UnderlyingType", "WithProtocols"} or not value.get("Name") or not isinstance(value.get("UnderlyingType"), dict):
        raise ValueError("Unreviewed TypeArgument model")
    underlying = erase_generic_encoding(value["UnderlyingType"])
    if value.get("WithProtocols"):
        underlying = copy.deepcopy(underlying)
        underlying["WithProtocols"] = sorted(set(underlying.get("WithProtocols", []) + value["WithProtocols"]))
    return underlying


def compare_models(original, candidate):
    differences, additions = [], []
    def walk(before, after, path):
        if before == after:
            return
        if isinstance(before, dict) and isinstance(after, dict):
            if set(before) != set(after):
                differences.append({"path": path, "reason": "model-keys", "before": sorted(before), "after": sorted(after)})
            for key in before.keys() & after.keys():
                walk(before[key], after[key], path + "/" + key)
        elif isinstance(before, list) and isinstance(after, list):
            if path.rsplit("/", 1)[-1] in MEMBERS:
                # Only named entities/members may be added. Signature arguments,
                # record fields, enum values, flags and protocol lists stay exact.
                if any(not isinstance(item, dict) or not isinstance(item.get("Name"), str) for item in before + after):
                    differences.append({"path": path, "reason": "unnamed-member"})
                    return
                # Top-level exports can share a native name but have distinct
                # JS identities (e.g. UIKeyInputF1 and UIKeyInputF1Var). Compare
                # every original field after matching its actual export identity.
                def identity(item):
                    return item.get("JsName", item["Name"]) if path.rsplit("/", 1)[-1] == "Items" else item["Name"]
                old = {identity(item): item for item in before}
                new = {identity(item): item for item in after}
                if len(old) != len(before) or len(new) != len(after):
                    differences.append({"path": path, "reason": "duplicate-member-identity"})
                    return
                for name in old:
                    if name not in new:
                        differences.append({"path": path + "/" + name, "reason": "missing-member"})
                    else:
                        walk(old[name], new[name], path + "/" + name)
                for name in new.keys() - old.keys():
                    additions.append({"path": path + "/" + name, "declaration": new[name]})
            elif len(before) != len(after):
                differences.append({"path": path, "reason": "ordered-list-length"})
            else:
                for index, (old, new) in enumerate(zip(before, after)):
                    walk(old, new, path + "/" + str(index))
        else:
            differences.append({"path": path, "reason": "value", "before": before, "after": after})
    walk(erase_generic_encoding(original), erase_generic_encoding(candidate), "")
    return {"status": "EXECUTED_PASS" if not differences else "FAILED", "differences": differences, "additions": additions}


def read_yaml(path):
    try:
        import yaml
    except ImportError:
        # macOS includes Ruby/Psych. Use its safe data loader when this actual
        # Python has no PyYAML; do not install a second toolchain for comparison.
        result = subprocess.run(["/usr/bin/ruby", "-ryaml", "-rjson", "-e",
            "puts JSON.generate(YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: false))",
            str(path)], capture_output=True, check=True, timeout=60)
        return json.loads(result.stdout)
    return yaml.load(Path(path).read_text(), Loader=getattr(yaml, "CSafeLoader", yaml.SafeLoader))


def compare_directories(original, candidate):
    references = sorted(Path(original).glob("*.yaml"))
    reports = {}
    for path in references:
        other = Path(candidate) / path.name
        reports[path.name] = compare_models(read_yaml(path), read_yaml(other)) if other.is_file() else {
            "status": "FAILED", "differences": [{"reason": "missing-module"}], "additions": []}
    return {"schemaVersion": 1, "status": "EXECUTED_PASS" if len(reports) == 31 and all(r["status"] == "EXECUTED_PASS" for r in reports.values()) else "FAILED",
        "referenceModules": len(reports), "modules": reports,
        "additionalModules": sorted(path.name for path in Path(candidate).glob("*.yaml") if not (Path(original) / path.name).is_file()),
        "boundary": "Existing API model preservation with generic type encoding erasure; additions are retained for review. Not runtime/ABI/device acceptance."}
